import Foundation

enum LLMError: LocalizedError {
    case notConfigured
    case networkError(String)
    case apiError(String)
    case noContent

    var errorDescription: String? {
        switch self {
        case .notConfigured:
            return "OpenRouter API Key fehlt. Bitte in den Einstellungen hinterlegen."
        case .networkError(let msg):
            return "Verbindungsproblem: \(msg)"
        case .apiError(let msg):
            return "Fehler von OpenRouter: \(msg)"
        case .noContent:
            return "Keine Antwort erhalten. Bitte nochmal versuchen."
        }
    }
}

private struct OpenRouterChatRequest: Encodable {
    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let messages: [Message]
    let temperature: Double
    let top_p: Double?
    let max_tokens: Int?
    let provider: OpenRouterConfig.ProviderPreference?
}

private struct OpenRouterChatResponse: Decodable {
    struct Choice: Decodable {
        struct Message: Decodable {
            let content: String?
        }

        let message: Message?
    }

    let choices: [Choice]?
}

private struct OpenRouterErrorResponse: Decodable {
    struct APIError: Decodable {
        let message: String?
    }

    let error: APIError?
}

enum LLMService {
    private static let session: URLSession = {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.waitsForConnectivity = false
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 45
        configuration.timeoutIntervalForResource = 45
        return URLSession(configuration: configuration)
    }()

    // MARK: - Smart Dictation (HushType prompt)

    /// Cleans up a raw dictation transcript with the exact HushType dictation
    /// prompt: applies spoken corrections, detects ordered/unordered lists,
    /// removes filler words, and adapts tone to the context app.
    static func smartFormat(
        text: String,
        contextApp: String,
        settings: TextImprovementSettings,
        dictionary: [DictionaryEntry] = [],
        model: String = OpenRouterConfig.defaultFormattingModel
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: dictatePrompt(contextApp: contextApp, settings: settings, dictionary: dictionary),
            model: model,
            temperature: 0,
            topP: OpenRouterConfig.llamaTopP,
            maxTokens: OpenRouterConfig.llamaMaxTokens
        )
    }

    // MARK: - Classic Rewrites

    static func improve(
        text: String,
        settings: TextImprovementSettings,
        dictionary: [DictionaryEntry] = [],
        model: String = OpenRouterConfig.defaultFormattingModel
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildSystemPrompt(settings: settings) + dictionaryInstructions(dictionary),
            model: model,
            temperature: 0.3,
            topP: nil,
            maxTokens: OpenRouterConfig.llamaMaxTokens
        )
    }

    static func dampfAblassen(
        text: String,
        systemPrompt: String,
        model: String = OpenRouterConfig.defaultFormattingModel
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: systemPrompt,
            model: model,
            temperature: 0.4,
            topP: nil,
            maxTokens: OpenRouterConfig.llamaMaxTokens
        )
    }

    static func addEmojis(
        text: String,
        settings: EmojiTextSettings,
        model: String = OpenRouterConfig.defaultFormattingModel
    ) async throws -> String {
        try await complete(
            text: text,
            systemPrompt: buildEmojiSystemPrompt(density: settings.emojiDensity),
            model: model,
            temperature: 0.3,
            topP: nil,
            maxTokens: OpenRouterConfig.llamaMaxTokens
        )
    }

    private static func complete(
        text: String,
        systemPrompt: String,
        model: String,
        temperature: Double,
        topP: Double?,
        maxTokens: Int?
    ) async throws -> String {
        guard let apiKey = KeychainService.load(key: .openRouterAPIKey) else {
            throw LLMError.notConfigured
        }

        let payload = OpenRouterChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: systemPrompt),
                .init(role: "user", content: text),
            ],
            temperature: temperature,
            top_p: topP,
            max_tokens: maxTokens,
            provider: OpenRouterConfig.llamaProvider
        )

        var request = URLRequest(url: OpenRouterConfig.chatCompletionsURL)
        request.httpMethod = "POST"
        OpenRouterConfig.authorize(&request, apiKey: apiKey)
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.timeoutInterval = 45
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse else {
            throw LLMError.networkError("Keine gültige Antwort")
        }

        guard httpResponse.statusCode == 200 else {
            throw LLMError.apiError(errorMessage(from: data) ?? "Status \(httpResponse.statusCode)")
        }

        let result = try JSONDecoder().decode(OpenRouterChatResponse.self, from: data)
        guard let content = result.choices?.first?.message?.content,
              !content.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw LLMError.noContent
        }

        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func errorMessage(from data: Data) -> String? {
        (try? JSONDecoder().decode(OpenRouterErrorResponse.self, from: data))?.error?.message
    }

    // MARK: - Prompts

    /// The HushType dictation system prompt. Static core + a dynamic line for the
    /// context app, plus optional reinforcement for the user's custom terms /
    /// instruction so the in-app customization keeps working.
    /// A "WÖRTERBUCH" prompt block from the dictionary: exact spellings + replacements.
    private static func dictionaryInstructions(_ entries: [DictionaryEntry]) -> String {
        let dict = DictionarySettings(entries: entries)
        var lines: [String] = []
        if !dict.spellingTerms.isEmpty {
            lines.append("Schreibe diese Eigennamen/Begriffe immer exakt so: \(dict.spellingTerms.joined(separator: ", ")).")
        }
        if !dict.replacements.isEmpty {
            let repl = dict.replacements.map { "\"\($0.from)\" → \"\($0.to)\"" }.joined(separator: "; ")
            lines.append("Ersetzungen (wenn sinngemäß das Linke gesprochen wird, schreibe das Rechte): \(repl).")
        }
        guard !lines.isEmpty else { return "" }
        return "\n\n===== WÖRTERBUCH =====\n" + lines.joined(separator: "\n")
    }

    private static func dictatePrompt(contextApp: String, settings: TextImprovementSettings, dictionary: [DictionaryEntry]) -> String {
        var prompt = """
        Du bist HushType, ein unsichtbares Diktier-Tool. Deine EINZIGE Aufgabe ist es, gesprochenen Text in geschriebenen Text zu wandeln. Du bist KEIN Assistent und KEIN Berater.

        ===== HARTE REGELN - befolge wortwoertlich =====
        1. Gib NUR den vom Nutzer gesprochenen Text aus - bereinigt, aber inhaltlich identisch.
        2. Fuege NIEMALS eigene Kommentare, Erklaerungen, Meta-Aussagen oder Hinweise hinzu.
           Verboten sind insbesondere Formulierungen wie:
             - "dieser Punkt ist identisch mit ..."
             - "es waere besser zu sagen ..."
             - "stattdessen koennte man ..."
             - "es wurden keine weiteren Punkte erwaehnt"
             - "der Sprecher meint vermutlich ..."
           Wenn der Nutzer denselben Satz mehrfach sagt: gib ihn auch mehrfach aus, exakt so.
        3. Keine Einleitung, kein Vor- oder Nachwort. Beginne direkt mit dem ersten Wort.
        4. Aendere KEINE Inhalte. Ergaenze nichts, lasse nichts weg. Reduziere nicht zusammen.
        5. Erlaubt sind nur: Fuellwoerter (aeh, aehm, also) entfernen, Grammatik/Satzzeichen korrigieren, Selbstkorrekturen im Satz aufloesen (z.B. "ich gehe ins Kino, ach nein, ins Theater" -> "ich gehe ins Theater"), Casing/Grossschreibung.

        ===== AUFZAEHLUNGEN (sprach-agnostisch) =====
        Wenn der Diktattext eine geordnete Aufzaehlung enthaelt ("erstens/zweitens/drittens", "first/second/third", "primero/segundo", "punkt eins, punkt zwei", "one, two, three" usw.), formatiere die Antwort als nummerierte Markdown-Liste - jeder Punkt auf eigener Zeile im Format "1. ...", "2. ...". Auch wenn zwei Punkte denselben Inhalt haben, beide werden ausgegeben.
        Ungeordnete Aufzaehlungen ("ausserdem", "weiterhin", "also", "plus") -> Bullets mit "- ".
        Normaler Fliesstext -> keine Liste erzwingen.

        ===== TONFALL =====
        Passe den Stil an die Kontext-App an: Slack/iMessage = casual, Mail/Mail-Apps = professionell, Code-Editoren (Cursor, VS Code, Xcode) = reiner Code ohne Prosa.
        """

        let trimmedContext = contextApp.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmedContext.isEmpty {
            prompt += "\n\nDie Kontext-App ist nicht bekannt - verwende einen neutralen, professionellen Ton."
        } else {
            prompt += "\n\nDie Kontext-App ist: \(trimmedContext)."
        }

        let extraInstruction = settings.systemPrompt.trimmingCharacters(in: .whitespacesAndNewlines)
        if !extraInstruction.isEmpty {
            prompt += "\n\nZusaetzliche Anweisung des Nutzers: \(extraInstruction)"
        }

        prompt += dictionaryInstructions(dictionary)

        return prompt
    }

    private static func buildEmojiSystemPrompt(density: EmojiTextSettings.EmojiDensity) -> String {
        let densityInstruction: String
        switch density {
        case .wenig:
            densityInstruction = "Setze nur vereinzelt Emojis ein, maximal 1-2 pro Absatz."
        case .mittel:
            densityInstruction = "Setze regelmaessig passende Emojis ein, etwa alle 1-2 Saetze."
        case .viel:
            densityInstruction = "Setze grosszuegig Emojis ein, gerne mehrere pro Satz."
        }

        return "Du erhaeltst ein gesprochenes Transkript. Gib den Text moeglichst originalgetreu zurueck, aber fuege passende Emojis ein. \(densityInstruction) Korrigiere offensichtliche Sprach- und Grammatikfehler. Behalte den Stil und die Bedeutung bei. Gib NUR den Text mit Emojis zurueck, keine Erklaerungen."
    }

    private static func buildSystemPrompt(settings: TextImprovementSettings) -> String {
        if !settings.systemPrompt.isEmpty {
            var prompt = settings.systemPrompt
            if !settings.customTerms.isEmpty {
                prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
            }
            return prompt
        }

        var prompt = """
        Du bist ein Lektor und Schreibassistent. Verbessere den folgenden Text:
        - Korrigiere Rechtschreibung und Grammatik
        - Verbessere die Formulierung und den Lesefluss
        - Behalte die urspruengliche Bedeutung bei
        - Gib NUR den verbesserten Text zurueck, keine Erklaerungen
        """

        switch settings.tone {
        case .formal:
            prompt += "\n- Verwende einen formellen, professionellen Ton"
        case .neutral:
            prompt += "\n- Verwende einen neutralen, klaren Ton"
        case .casual:
            prompt += "\n- Verwende einen lockeren, natuerlichen Ton"
        }

        if !settings.customTerms.isEmpty {
            prompt += "\n\nWichtig: Diese Eigennamen und Fachbegriffe muessen exakt so geschrieben werden: \(settings.customTerms.joined(separator: ", "))"
        }

        if !settings.context.isEmpty {
            prompt += "\n\nKontext: \(settings.context)"
        }

        return prompt
    }
}
