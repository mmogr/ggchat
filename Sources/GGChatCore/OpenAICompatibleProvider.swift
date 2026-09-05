import Foundation

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// The only real provider. URLSession, SSE, bearer auth when a key is set.
/// gglib's proxy status lives here too, as plain endpoints that any server
/// may or may not answer.
public struct OpenAICompatibleProvider: Provider {
    public let baseURL: URL
    let apiKey: String?
    let session: URLSession
    let log: any LogSink
    let decoder = JSONDecoder()

    public init(
        baseURL: URL,
        apiKey: String? = nil,
        session: URLSession = .shared,
        log: any LogSink = NoopLogSink()
    ) {
        self.baseURL = baseURL
        self.apiKey = apiKey.flatMap { $0.isEmpty ? nil : $0 }
        self.session = session
        self.log = log
    }

    public func models() async throws -> [ModelInfo] {
        let request = makeRequest(path: "models", method: "GET", body: nil)
        let (data, response) = try await perform(request)
        try checkStatus(response, data: data)
        return try decode(ModelsResponse.self, from: data).data
    }

    /// nil when the server answers 404: the pane is hidden for that provider.
    public func proxyStatus() async throws -> ProxyStatus? {
        let request = makeRequest(path: "proxy/status", method: "GET", body: nil)
        let (data, response) = try await perform(request)
        if response.statusCode == 404 { return nil }
        try checkStatus(response, data: data)
        return try decode(ProxyStatus.self, from: data)
    }

    // MARK: - Requests

    func makeRequest(path: String, method: String, body: Data?) -> URLRequest {
        var request = URLRequest(url: baseURL.appending(path: path))
        request.httpMethod = method
        request.httpBody = body
        if body != nil { request.setValue("application/json", forHTTPHeaderField: "Content-Type") }
        if let apiKey { request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization") }
        request.setValue("text/event-stream, application/json", forHTTPHeaderField: "Accept")
        return request
    }

    func perform(_ request: URLRequest) async throws(ProviderError) -> (Data, HTTPURLResponse) {
        log.log(.debug, "\(request.httpMethod ?? "GET") \(Redaction.describe(request.url!))")
        do {
            let (data, response) = try await session.data(for: request)
            guard let http = response as? HTTPURLResponse else {
                throw ProviderError.invalidResponse(String(describing: type(of: response)))
            }
            return (data, http)
        } catch let error as ProviderError {
            throw error
        } catch {
            log.log(.error, "transport failure: \(error.localizedDescription)")
            throw ProviderError.transport(error.localizedDescription)
        }
    }

    func checkStatus(_ response: HTTPURLResponse, data: Data) throws(ProviderError) {
        guard !(200..<300).contains(response.statusCode) else { return }
        throw Self.serverError(status: response.statusCode, body: data)
    }

    func decode<T: Decodable>(_ type: T.Type, from data: Data) throws(ProviderError) -> T {
        do {
            return try decoder.decode(type, from: data)
        } catch {
            throw ProviderError.decoding(String(describing: error))
        }
    }

    static func serverError(status: Int, body: Data) -> ProviderError {
        if let parsed = try? JSONDecoder().decode(APIErrorBody.self, from: body) {
            return .server(status: status, code: parsed.error.code, message: parsed.error.message)
        }
        let text = String(decoding: body.prefix(512), as: UTF8.self)
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let message = text.isEmpty ? "The server answered with HTTP \(status)." : text
        return .server(status: status, code: nil, message: message)
    }
}
