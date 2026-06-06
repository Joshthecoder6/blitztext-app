import Foundation

// MARK: - Workflow Types

enum WorkflowType: String, CaseIterable, Identifiable, Codable {
    case transcription
    case localTranscription
    case textImprover
    case dampfAblassen
    case emojiText

    var id: String { rawValue }

    static var mainMenuCases: [WorkflowType] {
        allCases.filter { $0 != .localTranscription }
    }

    var displayName: String {
        switch self {
        case .transcription: return "Blitztext"
        case .localTranscription: return "Blitztext Lokal"
        case .textImprover: return "Blitztext+"
        case .dampfAblassen: return "Blitztext $%&!"
        case .emojiText: return "Blitztext :)"
        }
    }

    var icon: String {
        switch self {
        case .transcription: return "mic.fill"
        case .localTranscription: return "lock.shield.fill"
        case .textImprover: return "text.badge.checkmark"
        case .dampfAblassen: return "flame.fill"
        case .emojiText: return "face.smiling"
        }
    }

    var subtitle: String {
        switch self {
        case .transcription: return "Sprechen. Sauber formatiert raus."
        case .localTranscription: return "Nur lokal. Kein Server."
        case .textImprover: return "Geschrieben sprechen."
        case .dampfAblassen: return "Frust rein. Entspannt raus."
        case .emojiText: return "Text rein. Emojis dazu."
        }
    }

    var hotkeyLabel: String {
        switch self {
        case .transcription: return "fn + Leertaste"
        case .localTranscription: return "fn + Shift + Ctrl"
        case .textImprover: return "fn + Control"
        case .dampfAblassen: return "fn + Option"
        case .emojiText: return "fn + Cmd"
        }
    }

    var accentColor: String {
        switch self {
        case .transcription: return "blue"
        case .localTranscription: return "green"
        case .textImprover: return "purple"
        case .dampfAblassen: return "orange"
        case .emojiText: return "cyan"
        }
    }
}

// MARK: - Workflow State

enum WorkflowPhase: Equatable {
    case idle
    case running(String)
    case done(String)
    case error(String)

    var isActive: Bool {
        switch self {
        case .idle: return false
        default: return true
        }
    }
}

enum WorkflowLaunchSource: Equatable {
    case manual
    case hotkeyBackground

    var presentsWorkflowPage: Bool {
        switch self {
        case .manual:
            return true
        case .hotkeyBackground:
            return false
        }
    }
}

typealias WorkflowOutputHandler = @MainActor (String) -> Void
typealias WorkflowPhaseChangeHandler = @MainActor (WorkflowPhase) -> Void

// MARK: - Workflow Protocol

@MainActor
protocol Workflow: AnyObject, Observable {
    var type: WorkflowType { get }
    var phase: WorkflowPhase { get set }
    var isRecording: Bool { get }
    var onOutput: WorkflowOutputHandler? { get set }
    var onPhaseChange: WorkflowPhaseChangeHandler? { get set }

    func start()
    func stop()
    func reset()
}

// MARK: - App Settings

struct AppSettings: Codable {
    var hotkeyMode: HotkeyMode = .toggle
    var hasSeenOnboarding: Bool = false
    var secureLocalModeEnabled: Bool = false
    var selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName
    var hasAutoSelectedFastLocalModel: Bool = false
    /// OpenRouter Whisper model id used for transcription (user-selectable).
    var transcriptionModel: String = OpenRouterConfig.defaultTranscriptionModel
    /// OpenRouter Llama model id used for the smart formatting / rewrites.
    var formattingModel: String = OpenRouterConfig.defaultFormattingModel
    /// When on, the main dictation hotkey runs the Llama smart formatting after transcription.
    var smartFormattingEnabled: Bool = true

    init(
        hotkeyMode: HotkeyMode = .toggle,
        hasSeenOnboarding: Bool = false,
        secureLocalModeEnabled: Bool = false,
        selectedLocalTranscriptionModelName: String = LocalTranscriptionService.recommendedFastModelName,
        hasAutoSelectedFastLocalModel: Bool = false,
        transcriptionModel: String = OpenRouterConfig.defaultTranscriptionModel,
        formattingModel: String = OpenRouterConfig.defaultFormattingModel,
        smartFormattingEnabled: Bool = true
    ) {
        self.hotkeyMode = hotkeyMode
        self.hasSeenOnboarding = hasSeenOnboarding
        self.secureLocalModeEnabled = secureLocalModeEnabled
        self.selectedLocalTranscriptionModelName = selectedLocalTranscriptionModelName
        self.hasAutoSelectedFastLocalModel = hasAutoSelectedFastLocalModel
        self.transcriptionModel = transcriptionModel
        self.formattingModel = formattingModel
        self.smartFormattingEnabled = smartFormattingEnabled
    }

    enum CodingKeys: String, CodingKey {
        case hotkeyMode
        case hasSeenOnboarding
        case secureLocalModeEnabled
        case selectedLocalTranscriptionModelName
        case hasAutoSelectedFastLocalModel
        case transcriptionModel
        case formattingModel
        case smartFormattingEnabled
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Old builds may have stored a now-removed mode ("hold"); fall back to toggle.
        hotkeyMode = (try? container.decodeIfPresent(HotkeyMode.self, forKey: .hotkeyMode)) ?? .toggle
        hasSeenOnboarding = try container.decodeIfPresent(Bool.self, forKey: .hasSeenOnboarding) ?? false
        secureLocalModeEnabled = try container.decodeIfPresent(Bool.self, forKey: .secureLocalModeEnabled) ?? false
        selectedLocalTranscriptionModelName = try container.decodeIfPresent(
            String.self,
            forKey: .selectedLocalTranscriptionModelName
        ) ?? LocalTranscriptionService.recommendedFastModelName
        hasAutoSelectedFastLocalModel = try container.decodeIfPresent(
            Bool.self,
            forKey: .hasAutoSelectedFastLocalModel
        ) ?? false
        let storedTranscription = ((try? container.decodeIfPresent(String.self, forKey: .transcriptionModel)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        transcriptionModel = (storedTranscription?.isEmpty == false)
            ? storedTranscription!
            : OpenRouterConfig.defaultTranscriptionModel
        let storedFormatting = ((try? container.decodeIfPresent(String.self, forKey: .formattingModel)) ?? nil)?
            .trimmingCharacters(in: .whitespacesAndNewlines)
        formattingModel = (storedFormatting?.isEmpty == false)
            ? storedFormatting!
            : OpenRouterConfig.defaultFormattingModel
        smartFormattingEnabled = try container.decodeIfPresent(Bool.self, forKey: .smartFormattingEnabled) ?? true
    }
}

enum TranscriptionBackend: String, Codable {
    case remote
    case local
}

// MARK: - Workflow Settings

struct TranscriptionSettings: Codable {
    var language: String = "de"
}

struct DampfAblassenSettings: Codable {
    var systemPrompt: String = "Du erhältst ein emotional gesprochenes Transkript. Erkenne zuerst das eigentliche Ziel, Anliegen und den wahren Frust der Person. Formuliere daraus eine klare, respektvolle und wirksame Nachricht, mit der die Person ihr Ziel eher erreicht. Bewahre relevante Fakten, konkrete Probleme, Grenzen, Erwartungen und die nötige Dringlichkeit. Entferne Beleidigungen, Drohungen, Sarkasmus, Unterstellungen und unnötige Eskalation. Wenn mehrere Vorwürfe genannt werden, verdichte sie auf die entscheidenden Kernpunkte. Der Ton soll ruhig, menschlich, bestimmt und lösungsorientiert sein. Gib NUR die fertige Nachricht zurück."
    var customName: String = ""
}

struct EmojiTextSettings: Codable {
    var emojiDensity: EmojiDensity = .mittel
    var customName: String = ""

    enum EmojiDensity: String, Codable, CaseIterable, Identifiable {
        case wenig
        case mittel
        case viel

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .wenig: return "Wenig"
            case .mittel: return "Mittel"
            case .viel: return "Viel"
            }
        }
    }
}

struct TextImprovementSettings: Codable {
    var systemPrompt: String = ""
    var customTerms: [String] = []
    var context: String = ""
    var tone: TextTone = .neutral
    var customName: String = ""

    enum TextTone: String, Codable, CaseIterable, Identifiable {
        case formal
        case neutral
        case casual

        var id: String { rawValue }

        var displayName: String {
            switch self {
            case .formal: return "Formell"
            case .neutral: return "Neutral"
            case .casual: return "Locker"
            }
        }
    }
}

// MARK: - Dictionary (Wispr-Flow-style)

/// A single dictionary entry.
/// - `spoken`: what you say (the trigger / how it sounds).
/// - `written`: how it should be written. If empty, the term is simply spelled
///   exactly as `spoken` (vocabulary). If set, it's a replacement (spoken -> written).
struct DictionaryEntry: Codable, Identifiable, Hashable {
    var id: UUID = UUID()
    var spoken: String = ""
    var written: String = ""

    var trimmedSpoken: String { spoken.trimmingCharacters(in: .whitespacesAndNewlines) }
    var trimmedWritten: String { written.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// The form that should appear in the output (written if given, else spoken).
    var canonicalForm: String { trimmedWritten.isEmpty ? trimmedSpoken : trimmedWritten }

    /// A real replacement only exists when written differs from spoken.
    var isReplacement: Bool {
        !trimmedWritten.isEmpty && trimmedWritten.caseInsensitiveCompare(trimmedSpoken) != .orderedSame
    }
}

struct DictionarySettings: Codable {
    var entries: [DictionaryEntry] = []

    /// Terms whose exact spelling should be enforced in the output.
    var spellingTerms: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            let term = entry.canonicalForm
            guard !term.isEmpty, seen.insert(term.lowercased()).inserted else { continue }
            result.append(term)
        }
        return result
    }

    /// Spoken -> written replacements.
    var replacements: [(from: String, to: String)] {
        entries.filter { $0.isReplacement }.map { ($0.trimmedSpoken, $0.trimmedWritten) }
    }

    /// All words worth hinting to the transcription model (spoken + written forms).
    var vocabulary: [String] {
        var seen = Set<String>()
        var result: [String] = []
        for entry in entries {
            for term in [entry.trimmedSpoken, entry.trimmedWritten] where !term.isEmpty {
                if seen.insert(term.lowercased()).inserted { result.append(term) }
            }
        }
        return result
    }
}
