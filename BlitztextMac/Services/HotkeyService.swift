import Cocoa
import Observation

/// Hotkey mode is kept for settings compatibility, but all hotkeys work as a
/// toggle: press once to start, press again to stop.
enum HotkeyMode: String, Codable, CaseIterable, Identifiable {
    case toggle

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .toggle: return "Drücken"
        }
    }

    var description: String {
        switch self {
        case .toggle: return "Einmal drücken zum Starten, nochmal drücken oder Escape zum Stoppen"
        }
    }
}

enum HotkeyEvent {
    case toggle(WorkflowType)   // a hotkey combo was pressed -> toggle that workflow
    case cancel                 // Escape pressed
}

/// Global hotkeys via a single `CGEventTap`.
///
/// - **fn + Leertaste (Space)** toggles the main dictation. The space keypress is
///   consumed so it is not typed into the focused field.
/// - **fn + modifier** combos toggle the secondary workflows (these are pure
///   modifiers, so they are passed through, not consumed):
///   `fn+Ctrl` → Blitztext+, `fn+Option` → $%&!, `fn+Cmd` → :), `fn+Shift+Ctrl` → Lokal.
///
/// Creating the tap requires Accessibility permission, which the app guides the
/// user to grant. If the tap cannot be created, `isActive` stays `false`.
final class HotkeyService {
    /// Virtual keycode for the Space bar (Leertaste).
    static let toggleKeyCode: Int64 = 49
    /// Virtual keycode for Escape.
    private static let escapeKeyCode: Int64 = 53

    var onHotkeyEvent: ((HotkeyEvent) -> Void)?
    private(set) var isActive = false

    private var eventTap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    /// Modifier combo currently held, so each press fires exactly one toggle.
    private var activeCombo: WorkflowType?

    func start() {
        guard eventTap == nil else {
            if let eventTap, !CGEvent.tapIsEnabled(tap: eventTap) {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return
        }

        let mask = (1 << CGEventType.keyDown.rawValue) | (1 << CGEventType.flagsChanged.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, refcon in
            guard let refcon else { return Unmanaged.passUnretained(event) }
            let service = Unmanaged<HotkeyService>.fromOpaque(refcon).takeUnretainedValue()
            return service.handle(type: type, event: event)
        }

        guard let tap = CGEvent.tapCreate(
            tap: .cgSessionEventTap,
            place: .headInsertEventTap,
            options: .defaultTap,
            eventsOfInterest: CGEventMask(mask),
            callback: callback,
            userInfo: Unmanaged.passUnretained(self).toOpaque()
        ) else {
            isActive = false
            return
        }

        eventTap = tap
        let source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        runLoopSource = source
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        isActive = true
    }

    func stop() {
        if let eventTap {
            CGEvent.tapEnable(tap: eventTap, enable: false)
        }
        if let runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes)
        }
        runLoopSource = nil
        eventTap = nil
        isActive = false
    }

    // MARK: - Event Handling

    /// Runs on the main run loop thread (the tap is added to the main run loop).
    private func handle(type: CGEventType, event: CGEvent) -> Unmanaged<CGEvent>? {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let eventTap {
                CGEvent.tapEnable(tap: eventTap, enable: true)
            }
            return Unmanaged.passUnretained(event)
        }

        if type == .flagsChanged {
            handleFlags(event.flags)
            return Unmanaged.passUnretained(event)
        }

        guard type == .keyDown else {
            return Unmanaged.passUnretained(event)
        }

        let keyCode = event.getIntegerValueField(.keyboardEventKeycode)
        let hasFn = event.flags.contains(.maskSecondaryFn)

        if keyCode == Self.toggleKeyCode && hasFn {
            emit(.toggle(.transcription))
            return nil // consume so the space is not typed into the focused app
        }

        if keyCode == Self.escapeKeyCode {
            emit(.cancel)
            // Let Escape pass through to the focused app as usual.
        }

        return Unmanaged.passUnretained(event)
    }

    private func handleFlags(_ flags: CGEventFlags) {
        if let combo = workflow(for: flags) {
            if activeCombo == nil {
                activeCombo = combo
                emit(.toggle(combo))
            }
        } else {
            activeCombo = nil
        }
    }

    /// Maps a pure modifier combo to its workflow (Space is handled separately).
    private func workflow(for flags: CGEventFlags) -> WorkflowType? {
        let relevant: CGEventFlags = [.maskShift, .maskControl, .maskAlternate, .maskCommand, .maskSecondaryFn]
        let mods = flags.intersection(relevant)

        if mods == [.maskSecondaryFn, .maskShift, .maskControl] { return .localTranscription }
        if mods == [.maskSecondaryFn, .maskControl] { return .textImprover }
        if mods == [.maskSecondaryFn, .maskAlternate] { return .dampfAblassen }
        if mods == [.maskSecondaryFn, .maskCommand] { return .emojiText }
        return nil
    }

    private func emit(_ event: HotkeyEvent) {
        // The tap runs on the main run loop; the handler hops to the main actor itself.
        onHotkeyEvent?(event)
    }

    deinit {
        stop()
    }
}
