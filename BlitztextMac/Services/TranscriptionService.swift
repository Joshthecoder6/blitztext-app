import Foundation
import OSLog

private let sttLogger = Logger(subsystem: "app.blitztext.mac", category: "STT")

enum TranscriptionError: LocalizedError {
    case noFile
    case notConfigured
    case networkError(String)
    case apiError(String)
    case emptyResult

    var errorDescription: String? {
        switch self {
        case .noFile:
            return "Keine Audio-Datei gefunden"
        case .notConfigured:
            return "API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        case .apiError(let msg):
            return "Fehler bei der Transkription: \(msg)"
        case .emptyResult:
            return "Aufnahme war leer (kein Text erkannt). Prüfe Mikrofon-Zugriff und Eingabegerät und sprich etwas lauter/länger."
        }
    }
}

private struct JSONTranscriptionRequest: Encodable {
    struct InputAudio: Encodable {
        let data: String
        let format: String
    }

    let model: String
    let input_audio: InputAudio
    let language: String?
    let temperature: Double
    let provider: ProviderRouting?
}

private struct TranscriptionResponse: Decodable {
    let text: String?
}

private struct TranscriptionErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}

enum TranscriptionService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 60
        return URLSession(configuration: configuration)
    }()

    static func transcribe(
        audioURL: URL,
        customTerms: [String] = [],
        language: String? = nil,
        provider: AIProvider,
        model: String
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: provider.keychainKey) else {
            throw TranscriptionError.notConfigured
        }

        return try await Task.detached(priority: .userInitiated) {
            defer {
                try? FileManager.default.removeItem(at: audioURL)
            }

            let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])
            let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
            let lang = (trimmedLanguage?.isEmpty == false) ? trimmedLanguage : nil
            let audioFormat = format(for: audioURL)

            sttLogger.info("STT request provider=\(provider.rawValue, privacy: .public) model=\(model, privacy: .public) format=\(audioFormat, privacy: .public) audioBytes=\(audioData.count, privacy: .public)")

            var request = URLRequest(url: provider.transcriptionsURL)
            request.httpMethod = "POST"
            provider.authorize(&request, apiKey: apiKey)
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData

            if provider.transcriptionUsesMultipart {
                let boundary = UUID().uuidString
                request.setValue("multipart/form-data; boundary=\(boundary)", forHTTPHeaderField: "Content-Type")
                request.httpBody = multipartBody(
                    boundary: boundary,
                    audioData: audioData,
                    model: model,
                    language: lang,
                    customTerms: customTerms
                )
            } else {
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                let payload = JSONTranscriptionRequest(
                    model: model,
                    input_audio: .init(data: audioData.base64EncodedString(), format: audioFormat),
                    language: lang,
                    temperature: 0,
                    provider: provider.supportsProviderRouting ? ProviderRouting(sort: "throughput") : nil
                )
                request.httpBody = try JSONEncoder().encode(payload)
            }

            let (data, response) = try await session.data(for: request)

            guard let httpResponse = response as? HTTPURLResponse else {
                throw TranscriptionError.networkError("Ungueltige Antwort")
            }

            guard httpResponse.statusCode == 200 else {
                let bodySnippet = String(data: data.prefix(400), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
                sttLogger.error("STT failed status=\(httpResponse.statusCode, privacy: .public) body=\(bodySnippet, privacy: .public)")
                throw TranscriptionError.apiError(errorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
            }

            guard let decoded = try? JSONDecoder().decode(TranscriptionResponse.self, from: data) else {
                let bodySnippet = String(data: data.prefix(400), encoding: .utf8) ?? "<non-utf8 \(data.count) bytes>"
                sttLogger.error("STT undecodable body=\(bodySnippet, privacy: .public)")
                throw TranscriptionError.apiError("Antwort nicht lesbar")
            }

            let text = (decoded.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty else {
                sttLogger.error("STT empty result (audioBytes=\(audioData.count, privacy: .public))")
                throw TranscriptionError.emptyResult
            }

            sttLogger.info("STT ok chars=\(text.count, privacy: .public)")
            return text
        }.value
    }

    private static func multipartBody(
        boundary: String,
        audioData: Data,
        model: String,
        language: String?,
        customTerms: [String]
    ) -> Data {
        var body = Data()
        func field(_ name: String, _ value: String) {
            body.append("--\(boundary)\r\n")
            body.append("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
            body.append(value)
            body.append("\r\n")
        }

        body.append("--\(boundary)\r\n")
        body.append("Content-Disposition: form-data; name=\"file\"; filename=\"audio.m4a\"\r\n")
        body.append("Content-Type: audio/m4a\r\n\r\n")
        body.append(audioData)
        body.append("\r\n")

        field("model", model)
        field("response_format", "json")
        field("temperature", "0")
        if !customTerms.isEmpty {
            field("prompt", "Eigennamen und Begriffe: \(customTerms.joined(separator: ", "))")
        }
        if let language, !language.isEmpty {
            field("language", language)
        }

        body.append("--\(boundary)--\r\n")
        return body
    }

    private static func format(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "m4a" : ext
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(TranscriptionErrorResponse.self, from: data))?.error?.message
    }
}

private extension Data {
    mutating func append(_ string: String) {
        if let data = string.data(using: .utf8) {
            append(data)
        }
    }
}
