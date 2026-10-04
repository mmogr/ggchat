import CoreGraphics
import Foundation
import GGChatCore
import Observation

/// The images of the Mac's chat open, as this phone holds them: in memory
/// only, each read once by its id when a row is drawn, and all dropped when
/// the chat is left (ADR 0007). Never the store, a file or a URL cache: the
/// fetch itself asks for nothing to be cached, on a session with no cache.
@Observable
final class HubImages {
    enum State: Equatable {
        case fetching
        case held
        /// The Mac did not send it, or sent other bytes than its id names.
        case missing
    }

    /// What is known of each image the chat open has drawn. Observed, so a
    /// row is drawn again when its image arrives.
    private(set) var states: [String: State] = [:]
    @ObservationIgnored private let bytes = NSCache<NSString, NSData>()
    @ObservationIgnored private let thumbnails = NSCache<NSString, CGImage>()
    /// Moved on each time everything is dropped, so a fetch that lands after
    /// its chat was left keeps nothing.
    @ObservationIgnored private(set) var generation = 0

    /// The image's bytes, while they are held.
    func data(_ id: String) -> Data? {
        bytes.object(forKey: id as NSString).map { Data(referencing: $0) }
    }

    func hold(_ data: Data, for id: String) {
        bytes.setObject(data as NSData, forKey: id as NSString, cost: data.count)
        states[id] = .held
    }

    /// Whether the image is to be read: it is not held, and not being read.
    func needsFetch(_ id: String) -> Bool {
        data(id) == nil && states[id] != .fetching
    }

    func fetching(_ id: String) {
        states[id] = .fetching
    }

    func missing(_ id: String) {
        states[id] = .missing
    }

    /// A small upright picture of a held image, made once.
    func thumbnail(of id: String) -> CGImage? {
        _ = states[id]
        if let kept = thumbnails.object(forKey: id as NSString) { return kept }
        guard let data = data(id), let picture = ImageDownscale.thumbnail(of: data) else { return nil }
        thumbnails.setObject(picture, forKey: id as NSString)
        return picture
    }

    /// Drops every image and every fetch under way.
    func removeAll() {
        bytes.removeAllObjects()
        thumbnails.removeAllObjects()
        states = [:]
        generation += 1
    }
}

extension AppModel {
    /// Reads one image of the chat open from its Mac, once, into memory. One
    /// this phone sent is held from its send, so it is not read back while
    /// held, and is read like any other once the chat is left and opened
    /// again. Bytes whose hash is not the id are not kept.
    func fetchHubImage(_ image: ImageRef) async {
        guard hubImages.needsFetch(image.id), let open = openedHubChat else { return }
        guard let config = providers.first(where: { $0.id == open.providerID }),
            let hub = reachableHubChats(for: config)
        else { return }
        let generation = hubImages.generation
        hubImages.fetching(image.id)
        let answer: Result<Data, HubChatsFailure>
        do throws(HubChatsFailure) {
            answer = .success(try await hub.fetchImage(id: image.id))
        } catch {
            answer = .failure(error)
        }
        guard hubImages.generation == generation else { return }
        switch answer {
        case .success(let data) where ImageRef.id(of: data) == image.id:
            hubImages.hold(data, for: image.id)
        case .success:
            log.log(.info, "\(config.name) sent an image whose bytes are not its id")
            hubImages.missing(image.id)
        case .failure(let failure):
            log.log(.info, "\(config.name) did not send an image: \(Self.kind(of: failure))")
            hubImages.missing(image.id)
        }
    }

    /// A small picture of an image of the chat open, once it is held.
    func hubThumbnail(of image: ImageRef) -> CGImage? {
        hubImages.thumbnail(of: image.id)
    }

    /// An image of the chat open at its own size, upright, once it is held.
    func hubPicture(of image: ImageRef) -> CGImage? {
        hubImages.data(image.id).flatMap {
            ImageDownscale.thumbnail(of: $0, longEdge: max(image.width, image.height, 1))
        }
    }
}
