import Foundation

nonisolated protocol UsageTelemetrySending: Sendable {
    func send(_ payload: UsageTelemetryPayload) async throws
}

nonisolated struct UsageTelemetryEndpoint {
    static let production = URL(string: "https://shatl-telemetry.mamontov-design.workers.dev/launch")!
}

nonisolated enum UsageTelemetryRequestBuilder {
    static func request(
        payload: UsageTelemetryPayload,
        endpointURL: URL,
        encoder: JSONEncoder = JSONEncoder()
    ) throws -> URLRequest {
        var request = URLRequest(url: endpointURL)
        request.httpMethod = "POST"
        request.cachePolicy = .reloadIgnoringLocalCacheData
        request.timeoutInterval = 10
        request.setValue("application/json; charset=utf-8", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.httpBody = try encoder.encode(payload)
        return request
    }
}

final class UsageTelemetryHTTPSender: UsageTelemetrySending, @unchecked Sendable {
    private let endpointURL: URL
    private let session: URLSession

    init(
        endpointURL: URL = UsageTelemetryEndpoint.production,
        session: URLSession = .shared
    ) {
        self.endpointURL = endpointURL
        self.session = session
    }

    func send(_ payload: UsageTelemetryPayload) async throws {
        let request = try UsageTelemetryRequestBuilder.request(
            payload: payload,
            endpointURL: endpointURL
        )
        let (_, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200..<300).contains(httpResponse.statusCode)
        else {
            throw UsageTelemetrySendError.unexpectedResponse
        }
    }
}

nonisolated enum UsageTelemetrySendError: Error {
    case unexpectedResponse
}
