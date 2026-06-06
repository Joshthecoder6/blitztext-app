import Foundation

/// Central configuration for the OpenRouter backend.
///
/// Blitztext talks to a single provider: OpenRouter (https://openrouter.ai),
/// which exposes an OpenAI-compatible API. Transcription runs on a Whisper model
/// via the `/audio/transcriptions` endpoint, text cleanup / formatting runs on a
/// Llama model via the `/chat/completions` endpoint.
enum OpenRouterConfig {
    static let baseURL = URL(string: "https://openrouter.ai/api/v1")!
    static let chatCompletionsURL = baseURL.appendingPathComponent("chat/completions")
    static let transcriptionsURL = baseURL.appendingPathComponent("audio/transcriptions")

    /// Transcription model (user-selectable in settings). Microsoft MAI-Transcribe by default.
    static let defaultTranscriptionModel = "microsoft/mai-transcribe-1.5"

    /// Llama model used for the dictation cleanup / structuring and rewrites.
    static let defaultFormattingModel = "meta-llama/llama-3.3-70b-instruct"

    /// Shared inference parameters for the Llama dictation call (from the HushType stack).
    static let llamaTopP = 0.1
    static let llamaMaxTokens = 4096

    /// OpenRouter provider routing preference.
    /// - `order` pins specific upstream providers (tried in order).
    /// - `sort` ("throughput"/"latency"/"price") picks the best matching provider.
    /// - `allowFallbacks` lets OpenRouter use another provider if the preferred one is unavailable.
    struct ProviderPreference: Encodable {
        var order: [String]?
        var sort: String?
        var allowFallbacks: Bool?

        enum CodingKeys: String, CodingKey {
            case order
            case sort
            case allowFallbacks = "allow_fallbacks"
        }

        init(order: [String]? = nil, sort: String? = nil, allowFallbacks: Bool? = nil) {
            self.order = order
            self.sort = sort
            self.allowFallbacks = allowFallbacks
        }
    }

    /// Llama formatting: pin Groq for speed, fall back to other hosts if it's down.
    static let llamaProvider = ProviderPreference(order: ["Groq"], allowFallbacks: true)

    /// Transcription: just use the fastest available provider.
    static let transcriptionProvider = ProviderPreference(sort: "throughput")

    /// Optional ranking headers OpenRouter recommends for apps.
    static let referer = "https://blitztext.de"
    static let title = "Blitztext"

    /// Adds the shared OpenRouter headers (auth + ranking) to a request.
    static func authorize(_ request: inout URLRequest, apiKey: String) {
        request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        request.setValue(referer, forHTTPHeaderField: "HTTP-Referer")
        request.setValue(title, forHTTPHeaderField: "X-Title")
    }
}
