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
            return "OpenRouter API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Netzwerkfehler: \(msg)"
        case .apiError(let msg):
            return "OpenRouter-Fehler: \(msg)"
        case .emptyResult:
            return "Aufnahme war leer (kein Text erkannt). Prüfe Mikrofon-Zugriff und Eingabegerät und sprich etwas lauter/länger."
        }
    }
}

private struct TranscriptionRequest: Encodable {
    struct InputAudio: Encodable {
        let data: String
        let format: String
    }

    let model: String
    let input_audio: InputAudio
    let language: String?
    let temperature: Double
    let provider: OpenRouterConfig.ProviderPreference?
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

    /// Transcribes audio with a Whisper / transcription model via OpenRouter's
    /// dedicated speech-to-text endpoint (JSON body with base64-encoded audio,
    /// `temperature=0`).
    ///
    /// - Note: `customTerms` is accepted for call-site compatibility. The
    ///   transcription endpoint has no vocabulary/prompt field, so exact spelling
    ///   of proper nouns is enforced later in the Llama formatting step instead.
    static func transcribe(
        audioURL: URL,
        customTerms: [String] = [],
        language: String? = nil,
        model: String = OpenRouterConfig.defaultTranscriptionModel
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: .openRouterAPIKey) else {
            throw TranscriptionError.notConfigured
        }

        return try await Task.detached(priority: .userInitiated) {
            defer {
                try? FileManager.default.removeItem(at: audioURL)
            }

            let audioData = try Data(contentsOf: audioURL, options: [.mappedIfSafe])
            let trimmedLanguage = language?.trimmingCharacters(in: .whitespacesAndNewlines)
            let audioFormat = format(for: audioURL)

            sttLogger.info("STT request model=\(model, privacy: .public) format=\(audioFormat, privacy: .public) audioBytes=\(audioData.count, privacy: .public) lang=\(trimmedLanguage ?? "auto", privacy: .public)")

            let payload = TranscriptionRequest(
                model: model,
                input_audio: .init(
                    data: audioData.base64EncodedString(),
                    format: audioFormat
                ),
                language: (trimmedLanguage?.isEmpty == false) ? trimmedLanguage : nil,
                temperature: 0,
                provider: OpenRouterConfig.transcriptionProvider
            )

            var request = URLRequest(url: OpenRouterConfig.transcriptionsURL)
            request.httpMethod = "POST"
            OpenRouterConfig.authorize(&request, apiKey: apiKey)
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.setValue("application/json", forHTTPHeaderField: "Accept")
            request.timeoutInterval = 60
            request.cachePolicy = .reloadIgnoringLocalCacheData
            request.httpBody = try JSONEncoder().encode(payload)

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

            sttLogger.info("STT ok responseBytes=\(data.count, privacy: .public) chars=\(text.count, privacy: .public)")
            return text
        }.value
    }

    private static func format(for url: URL) -> String {
        let ext = url.pathExtension.lowercased()
        return ext.isEmpty ? "m4a" : ext
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(TranscriptionErrorResponse.self, from: data))?.error?.message
    }
}
