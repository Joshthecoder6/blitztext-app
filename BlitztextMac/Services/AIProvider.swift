import Foundation

/// An AI backend provider. Both expose an OpenAI-compatible API, but differ in
/// endpoints, transcription request shape, model ids and routing options.
enum AIProvider: String, Codable, CaseIterable, Identifiable {
    case openRouter
    case groq

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .openRouter: return "OpenRouter"
        case .groq: return "Groq"
        }
    }

    // MARK: Endpoints

    var baseURL: URL {
        switch self {
        case .openRouter: return URL(string: "https://openrouter.ai/api/v1")!
        case .groq: return URL(string: "https://api.groq.com/openai/v1")!
        }
    }

    var chatCompletionsURL: URL { baseURL.appendingPathComponent("chat/completions") }
    var transcriptionsURL: URL { baseURL.appendingPathComponent("audio/transcriptions") }
    var modelsURL: URL { baseURL.appendingPathComponent("models") }

    // MARK: Credentials

    var keychainKey: KeychainKey {
        switch self {
        case .openRouter: return .openRouterAPIKey
        case .groq: return .groqAPIKey
        }
    }

    var keyPlaceholder: String {
        switch self {
        case .openRouter: return "sk-or-..."
        case .groq: return "gsk_..."
        }
    }

    var keyConsoleURL: String {
        switch self {
        case .openRouter: return "openrouter.ai/keys"
        case .groq: return "console.groq.com/keys"
        }
    }

    /// Loose validation for a pasted key.
    var keyPattern: String {
        switch self {
        case .openRouter: return #"^sk-(or-)?[A-Za-z0-9_-]{20,}$"#
        case .groq: return #"^gsk_[A-Za-z0-9_-]{20,}$"#
        }
    }

    // MARK: Behaviour differences

    /// Groq uses the OpenAI-style multipart transcription endpoint; OpenRouter
    /// uses a JSON body with base64-encoded `input_audio`.
    var transcriptionUsesMultipart: Bool { self == .groq }

    /// Only OpenRouter understands the `provider` routing field + ranking headers.
    var supportsProviderRouting: Bool { self == .openRouter }

    /// Groq requires the API key to list models; OpenRouter's list is public.
    var modelsListNeedsKey: Bool { self == .groq }

    // MARK: Default models

    var defaultTranscriptionModel: String {
        switch self {
        case .openRouter: return "microsoft/mai-transcribe-1.5"
        case .groq: return "whisper-large-v3-turbo"
        }
    }

    var defaultFormattingModel: String {
        switch self {
        case .openRouter: return "meta-llama/llama-3.3-70b-instruct"
        case .groq: return "llama-3.3-70b-versatile"
        }
    }

    // MARK: Requests

    func authorize(_ request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        if self == .openRouter {
            request.setValue("https://blitztext.de", forHTTPHeaderField: "HTTP-Referer")
            request.setValue("Blitztext", forHTTPHeaderField: "X-Title")
        }
    }

    /// Llama routing preference (pins Groq's fast host on OpenRouter); nil for Groq.
    var chatProviderRouting: ProviderRouting? {
        switch self {
        case .openRouter: return ProviderRouting(order: ["Groq"], allowFallbacks: true)
        case .groq: return nil
        }
    }

    /// Heuristic: does this look like a transcription/speech-to-text model id?
    static func isTranscriptionModelID(_ id: String) -> Bool {
        let lower = id.lowercased()
        return lower.contains("whisper") || lower.contains("transcribe") || lower.contains("asr")
    }
}

/// OpenRouter provider-routing preference (ignored by Groq).
struct ProviderRouting: Encodable {
    var order: [String]?
    var sort: String?
    var allowFallbacks: Bool?

    enum CodingKeys: String, CodingKey {
        case order, sort
        case allowFallbacks = "allow_fallbacks"
    }

    init(order: [String]? = nil, sort: String? = nil, allowFallbacks: Bool? = nil) {
        self.order = order
        self.sort = sort
        self.allowFallbacks = allowFallbacks
    }
}

/// Shared Llama inference parameters (from the HushType stack).
enum LlamaParams {
    static let topP = 0.1
    static let maxTokens = 4096
}
