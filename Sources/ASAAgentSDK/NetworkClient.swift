import Foundation

/// Handles HTTP communication with the ASA Agent backend.
final class NetworkClient {

    private let baseURL: URL
    private let apiKey: String
    private let appId: String
    private let logger: Logger
    private let session: URLSession
    private let encoder: JSONEncoder

    init(baseURL: URL, apiKey: String, appId: String, logger: Logger) {
        self.baseURL = baseURL
        self.apiKey = apiKey
        self.appId = appId
        self.logger = logger

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.waitsForConnectivity = true
        self.session = URLSession(configuration: config)

        self.encoder = JSONEncoder()
        self.encoder.keyEncodingStrategy = .convertToSnakeCase
    }

    // MARK: - Attribution

    func sendAttribution(
        _ payload: AttributionPayload,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        post(path: "/api/sdk/v1/attribution", body: payload, completion: completion)
    }

    // MARK: - Revenue Events

    func sendEvent(
        _ event: RevenueEvent,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        post(path: "/api/sdk/v1/event", body: event, completion: completion)
    }

    // MARK: - HTTP

    private func post<T: Encodable>(
        path: String,
        body: T,
        completion: @escaping (Result<Void, Error>) -> Void
    ) {
        let url = baseURL.appendingPathComponent(path)
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue(apiKey, forHTTPHeaderField: "X-API-Key")
        request.setValue(appId, forHTTPHeaderField: "X-App-Id")
        request.setValue("ios-sdk/\(SDKConstants.version)", forHTTPHeaderField: "User-Agent")

        do {
            request.httpBody = try encoder.encode(body)
        } catch {
            completion(.failure(error))
            return
        }

        session.dataTask(with: request) { [logger] data, response, error in
            if let error = error {
                completion(.failure(error))
                return
            }

            guard let httpResponse = response as? HTTPURLResponse else {
                completion(.failure(SDKError.invalidResponse))
                return
            }

            if (200...299).contains(httpResponse.statusCode) {
                completion(.success(()))
            } else {
                let body = data.flatMap { String(data: $0, encoding: .utf8) } ?? "no body"
                logger.log("API error \(httpResponse.statusCode): \(body)")
                completion(.failure(SDKError.apiError(statusCode: httpResponse.statusCode, message: body)))
            }
        }.resume()
    }
}

// MARK: - Errors

enum SDKError: LocalizedError {
    case invalidResponse
    case apiError(statusCode: Int, message: String)

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "Invalid server response"
        case .apiError(let code, let message):
            return "API error \(code): \(message)"
        }
    }
}
