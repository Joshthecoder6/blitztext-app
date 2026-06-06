import SwiftUI
import AVFoundation

@main
struct BlitztextMacApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    var body: some Scene {
        Settings {
            EmptyView()
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate, NSPopoverDelegate {
    private var statusItem: NSStatusItem!
    private var popover: NSPopover!
    private let menuBarStatusController = MenuBarStatusController()
    let appState = AppState()

    func applicationDidFinishLaunching(_ notification: Notification) {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)

        if let button = statusItem.button {
            menuBarStatusController.attach(to: button)
            button.action = #selector(togglePopover)
            button.target = self
        }

        popover = NSPopover()
        popover.contentSize = NSSize(width: 340, height: 480)
        popover.behavior = .transient
        popover.delegate = self
        popover.contentViewController = NSHostingController(rootView: MenuBarView(appState: appState))

        NSApp.setActivationPolicy(.accessory)

        // Trigger the microphone permission prompt early so dictation isn't silent.
        if AVCaptureDevice.authorizationStatus(for: .audio) == .notDetermined {
            AVCaptureDevice.requestAccess(for: .audio) { _ in }
        }

        // Hotkey events (the tap callback runs on the main run loop; hop to the main actor).
        appState.hotkeyService.onHotkeyEvent = { [weak self] event in
            Task { @MainActor in
                self?.handleHotkeyEvent(event)
            }
        }
        appState.onMenuBarStatusChange = { [weak self] status in
            self?.menuBarStatusController.update(to: status)
        }
        appState.hotkeyService.start()

        // Listen for popover dismiss requests (from auto-paste)
        NotificationCenter.default.addObserver(
            self,
            selector: #selector(handleDismissPopover),
            name: .dismissPopover,
            object: nil
        )

        DispatchQueue.main.async { [weak self] in
            self?.showOnboardingIfNeeded()
        }
    }

    func applicationDidBecomeActive(_ notification: Notification) {
        // Re-attempt creating the event tap; it only succeeds once Accessibility is granted.
        appState.hotkeyService.start()
        appState.refreshAccessibilityPermission()
    }

    @objc private func handleDismissPopover() {
        appState.isPopoverShown = false
        popover.performClose(nil)
    }

    private func handleHotkeyEvent(_ event: HotkeyEvent) {
        switch event {
        case .toggle(let type):
            handleHotkeyToggle(type)
        case .cancel:
            handleHotkeyCancel()
        }
    }

    /// Press a hotkey once to start the workflow, press again to stop.
    /// Runs in the background and pastes into the app you were using.
    private func handleHotkeyToggle(_ type: WorkflowType) {
        guard appState.isConfigured else { return }

        // Already running this workflow? Second press stops recording and processes.
        if let active = appState.activeWorkflow,
           active.type == type,
           active.phase.isActive {
            if case .running = active.phase, active.isRecording {
                active.stop()
            }
            return
        }

        appState.startWorkflow(type, source: .hotkeyBackground)
    }

    private func handleHotkeyCancel() {
        guard let active = appState.activeWorkflow, active.isRecording else { return }
        active.reset()
    }

    @objc private func togglePopover() {
        if popover.isShown {
            popover.performClose(nil)
            appState.isPopoverShown = false
        } else {
            appState.prepareForPopoverPresentation()
            showPopover()
        }
    }

    private func showOnboardingIfNeeded() {
        guard appState.shouldShowOnboarding else { return }
        appState.prepareForPopoverPresentation()
        showPopover()
    }

    private func showPopover() {
        guard let button = statusItem.button else { return }
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        appState.isPopoverShown = true
        NSApp.activate(ignoringOtherApps: true)
    }

    nonisolated func popoverDidClose(_ notification: Notification) {
        Task { @MainActor in
            appState.isPopoverShown = false
            switch appState.currentPhase {
            case .done, .error:
                appState.resetCurrentWorkflow()
            default:
                appState.page = .main
            }
        }
    }
}
