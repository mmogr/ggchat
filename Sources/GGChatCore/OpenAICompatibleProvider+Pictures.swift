import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

// A picture drawn again, and kept: gglib's `images/generations` read as the
// stream it answers, and `chats/{id}/pictures`. Same base URL, same key.
extension OpenAICompatibleProvider: PictureProvider {
    /// `POST images/generations` with the picture in its body, read on the
    /// session a reply streams on, since a render can take minutes. The
    /// stream ends at the first picture or the first failure: a refusal's
    /// own sentence, an `error` event's, or that the render ended without a
    /// picture. Cancelling the reader closes the request.
    public func redraw(_ redraw: PictureRedraw) -> AsyncStream<RedrawEvent> {
        AsyncStream { continuation in
            let task = Task {
                if let last = await self.render(redraw, into: continuation) { continuation.yield(last) }
                continuation.finish()
            }
            continuation.onTermination = { _ in task.cancel() }
        }
    }

    /// Passes the render's progress on, and answers how it ended: nil when
    /// the reader left.
    private func render(
        _ redraw: PictureRedraw, into continuation: AsyncStream<RedrawEvent>.Continuation
    ) async -> RedrawEvent? {
        guard let body = try? JSONEncoder().encode(redraw) else {
            return .failed("The picture could not be sent.")
        }
        let request = makeRequest(path: "images/generations", method: "POST", body: body)
        do {
            for try await item in try await eventStream(request, over: streamingSession) {
                guard case .event(let event) = item else { break }
                switch RedrawEvent(event) {
                case .progress(let progress)?: continuation.yield(.progress(progress))
                case .drawn(let picture)?: return .drawn(picture)
                case .failed(let why)?: return .failed(why)
                case nil: continue
                }
            }
            return Task.isCancelled ? nil : .failed(RedrawEvent.endedWithoutAPicture)
        } catch is CancellationError {
            return nil
        } catch let error as ProviderError {
            return .failed(error.errorDescription ?? RedrawEvent.noReason)
        } catch {
            if Task.isCancelled { return nil }
            log.log(.error, "a redraw's stream failed: \(error.localizedDescription)")
            return .failed(ProviderError.transport(error.localizedDescription).errorDescription ?? RedrawEvent.noReason)
        }
    }

    /// `POST chats/{id}/pictures` with `{from, image}`: the hub links the
    /// stored picture `image` to the tool row that carries `from`, after the
    /// images that row has, and answers the row's images, oldest first.
    /// Anything but a 200 that reads is the error it is.
    public func keepPicture(chatID: Int64, _ kept: KeptPicture) async throws(ProviderError) -> [ImageRef] {
        let body: Data
        do {
            body = try JSONEncoder().encode(kept)
        } catch {
            throw .decoding("could not encode the request: \(error)")
        }
        let (data, response) = try await perform(
            makeRequest(path: "chats/\(chatID)/pictures", method: "POST", body: body))
        guard response.statusCode == 200 else { throw Self.serverError(status: response.statusCode, body: data) }
        return try decode([ImageRef].self, from: data)
    }
}
