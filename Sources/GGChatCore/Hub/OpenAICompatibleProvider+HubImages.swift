import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// The images of the hub's chats: gglib's `attachments` routes, beside its
// chats routes. Same base URL, same key. Neither body is JSON: an upload is
// the image's bytes, and a fetch answers them.
extension OpenAICompatibleProvider {
    /// `POST attachments` with the image as the whole body. gglib reads the
    /// type from the first bytes and answers its `AttachmentInfo`, whose
    /// `image_tokens` is passed over here. A 404 is a gglib from before
    /// images, with no such route.
    public func uploadImage(_ data: Data, mime: String) async throws(HubTurnFailure) -> ImageRef {
        var request = rawRequest(path: "attachments", method: "POST", accept: "application/json")
        request.httpBody = data
        request.setValue(mime, forHTTPHeaderField: "Content-Type")
        let answer: Answer
        do {
            answer = try await perform(request)
        } catch {
            throw Self.turnFailure(error)
        }
        let (body, response) = answer
        guard (200..<300).contains(response.statusCode) else {
            if response.statusCode == 404 { throw .takesNoImages }
            throw Self.turnFailure(Self.serverError(status: response.statusCode, body: body))
        }
        do {
            return try decode(ImageRef.self, from: body)
        } catch {
            throw .refused(error)
        }
    }

    /// `GET attachments/{id}`: the image's bytes. Asked with nothing cached
    /// and on a session with no cache, so the bytes are never written to
    /// this device's disk, whatever the answer's headers say. An id the hub
    /// does not hold is a 404, and so is one gglib cannot read as an id.
    public func fetchImage(id: String) async throws(HubChatsFailure) -> Data {
        let session = uncachedSession()
        defer { session.finishTasksAndInvalidate() }
        let answer: Answer
        do {
            answer = try await perform(imageRequest(id: id), on: session)
        } catch {
            throw Self.hubFailure(error)
        }
        let (data, response) = answer
        guard (200..<300).contains(response.statusCode) else {
            throw Self.hubFailure(Self.serverError(status: response.statusCode, body: data))
        }
        // The hub answers an image as PNG or JPEG. Anything else is a page
        // something in front of it sent.
        let type = response.value(forHTTPHeaderField: "Content-Type") ?? ""
        guard [ImageRef.png, ImageRef.jpeg].contains(where: type.hasPrefix) else {
            throw .dropped(.invalidResponse("the answer was not an image"))
        }
        return data
    }

    /// The request for one image: nothing read from a cache, and an image
    /// asked for.
    func imageRequest(id: String) -> URLRequest {
        var request = rawRequest(
            path: "attachments/\(id)", method: "GET", accept: "\(ImageRef.png), \(ImageRef.jpeg)")
        request.cachePolicy = .reloadIgnoringLocalCacheData
        return request
    }

    /// A session like `session`, with no URL cache at all: what it fetches
    /// is held by the caller and nowhere else.
    func uncachedSession() -> URLSession {
        let configuration = session.configuration
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        return URLSession(configuration: configuration)
    }

    /// A request whose body, if any, is not JSON: `makeRequest`'s key, with
    /// its own `Accept`.
    private func rawRequest(path: String, method: String, accept: String) -> URLRequest {
        var request = makeRequest(path: path, method: method, body: nil)
        request.setValue(accept, forHTTPHeaderField: "Accept")
        return request
    }
}
