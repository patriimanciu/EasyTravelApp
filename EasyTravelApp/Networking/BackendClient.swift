import Foundation

enum BackendClientError: Error, LocalizedError {
    case invalidBaseURL
    case invalidResponse
    case serverError(statusCode: Int, message: String?)

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL:
            "Invalid backend base URL."
        case .invalidResponse:
            "Invalid response from server."
        case let .serverError(statusCode, message):
            if let message, !message.isEmpty {
                "Server error (\(statusCode)): \(message)"
            } else {
                "Server error (\(statusCode))."
            }
        }
    }
}

struct BackendClient {
    var baseURLString: String

    func processVideo(url videoURL: String) async throws -> LocationExtractionDTO {
        guard let baseURL = URL(string: baseURLString) else { throw BackendClientError.invalidBaseURL }
        let endpoint = baseURL.appending(path: "api/process-video")

        var req = URLRequest(url: endpoint)
        req.httpMethod = "POST"
        req.setValue("application/json", forHTTPHeaderField: "Content-Type")

        let payload = VideoRequestDTO(url: videoURL)
        req.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await URLSession.shared.data(for: req)
        guard let http = response as? HTTPURLResponse else { throw BackendClientError.invalidResponse }

        if !(200..<300).contains(http.statusCode) {
            let message = (try? JSONDecoder().decode(BackendErrorDTO.self, from: data))?.detail
            throw BackendClientError.serverError(statusCode: http.statusCode, message: message)
        }

        return try JSONDecoder().decode(LocationExtractionDTO.self, from: data)
    }
}

