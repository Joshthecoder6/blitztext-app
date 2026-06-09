import Foundation

/// Available models for a provider, split into transcription (STT) and chat (LLM).
struct ModelCatalog: Equatable {
    var transcription: [String] = []
    var chat: [String] = []

    var isEmpty: Bool { transcription.isEmpty && chat.isEmpty }
}

enum ModelCatalogError: LocalizedError {
    case notConfigured
    case requestFailed(String)

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "API Key fehlt – für die Modell-Liste von Groq wird der Key benötigt."
        case .requestFailed(let msg):
            return "Modelle konnten nicht geladen werden: \(msg)"
        }
    }
}

enum ModelCatalogService {
    private struct ModelsResponse: Decodable {
        struct Model: Decodable {
            let id: String
            struct Architecture: Decodable {
                let input_modalities: [String]?
                let output_modalities: [String]?
            }
            let architecture: Architecture?
        }
        let data: [Model]?
    }

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }()

    /// Fetches and categorizes the provider's model list. OpenRouter's list is
    /// public; Groq's needs the API key.
    static func fetch(provider: AIProvider) async throws -> ModelCatalog {
        let apiKey = KeychainService.load(key: provider.keychainKey)
        if provider.modelsListNeedsKey, apiKey == nil {
            throw ModelCatalogError.notConfigured
        }

        var request = URLRequest(url: provider.modelsURL)
        request.httpMethod = "GET"
        if let apiKey {
            provider.authorize(&request, apiKey: apiKey)
        }
        request.setValue("application/json", forHTTPHeaderField: "Accept")

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw ModelCatalogError.requestFailed("Ungültige Antwort")
        }
        guard http.statusCode == 200 else {
            throw ModelCatalogError.requestFailed("Status \(http.statusCode)")
        }

        let decoded = try JSONDecoder().decode(ModelsResponse.self, from: data)
        let models = decoded.data ?? []

        var transcription = Set<String>()
        var chat = Set<String>()

        for model in models {
            let id = model.id
            let inputs = model.architecture?.input_modalities ?? []
            let outputs = model.architecture?.output_modalities ?? []
            let lower = id.lowercased()

            if AIProvider.isTranscriptionModelID(id) || (inputs.contains("audio") && !inputs.contains("text")) {
                transcription.insert(id)
                continue
            }

            // Skip non-chat helpers (TTS / speech / safety / embeddings).
            if lower.contains("tts") || lower.contains("-speech") || lower.contains("guard")
                || lower.contains("embed") || lower.contains("moderation") || lower.contains("rerank") {
                continue
            }

            // Chat-capable: produces text from text (Groq has no architecture field → assume chat).
            let producesText = outputs.contains("text") || outputs.isEmpty
            let acceptsText = inputs.contains("text") || inputs.isEmpty
            if producesText && acceptsText {
                chat.insert(id)
            }
        }

        return ModelCatalog(
            transcription: transcription.sorted(),
            chat: chat.sorted()
        )
    }
}
