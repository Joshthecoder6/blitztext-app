import SwiftUI
import AppKit

struct SettingsContentView: View {
    @Bindable var appState: AppState
    @State private var selectedTab = 0

    var body: some View {
        VStack(spacing: 0) {
            // Two-tab segmented picker
            Picker("", selection: $selectedTab) {
                Text("Anpassen").tag(0)
                Text("Zugang").tag(1)
            }
            .pickerStyle(.segmented)
            .padding(.horizontal, 16)
            .padding(.vertical, 10)

            ScrollView {
                if selectedTab == 0 {
                    CustomizeSettingsView(appState: appState)
                } else {
                    AccessSettingsView(appState: appState)
                }
            }
        }
        .onAppear {
            appState.refreshAccessibilityPermission()
            selectedTab = defaultTabSelection
        }
    }

    private var defaultTabSelection: Int {
        if !appState.accessibilityPermissionGranted {
            return 1
        }
        if appState.isConfigured && !BlitztextInstallLocationService.shouldOfferMoveToApplications {
            return 0
        }
        return 1
    }
}

// MARK: - Section Label (quiet style)

private struct SectionLabel: View {
    let text: String

    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.secondary)
    }
}

// MARK: - Provider Configuration (provider + key + models, all in one place)

struct ProviderConfigView: View {
    @Bindable var appState: AppState
    @State private var apiKeyInput = ""
    @State private var editingKey = false
    @State private var keyError: String?
    @State private var keySaved = false

    private var provider: AIProvider { appState.providerSettings.provider }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            SectionLabel(text: "Konfiguration")

            // Provider switch
            VStack(alignment: .leading, spacing: 6) {
                Text("Anbieter")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Picker("", selection: Binding(
                    get: { appState.providerSettings.provider },
                    set: { newValue in
                        appState.providerSettings.provider = newValue
                        editingKey = false
                        apiKeyInput = ""
                        keyError = nil
                        appState.modelCatalogError = nil
                    }
                )) {
                    ForEach(AIProvider.allCases) { p in
                        Text(p.displayName).tag(p)
                    }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }

            keySection
            modelSection

            Toggle("Smarte Formatierung (Llama)", isOn: $appState.appSettings.smartFormattingEnabled)
                .toggleStyle(.switch)
                .font(.system(size: 11.5))

            Text("Erkennt Aufzählungen, wendet gesprochene Korrekturen an, entfernt Füllwörter. Der System-Prompt (unten unter Anpassen) wird immer angewandt.")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var keySection: some View {
        let hasKey = KeychainService.hasKey(provider.keychainKey)
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text("\(provider.displayName) API Key")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if hasKey && !editingKey {
                    Button("Ändern") { editingKey = true; apiKeyInput = "" }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
            }

            if hasKey && !editingKey {
                HStack(spacing: 6) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9))
                        .foregroundStyle(.green.opacity(0.8))
                    Text(appState.apiKeyDisplayValue(for: provider.keychainKey))
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(RoundedRectangle(cornerRadius: 6).fill(Color(nsColor: .controlBackgroundColor)))
            } else {
                HStack(spacing: 8) {
                    SecureField(provider.keyPlaceholder, text: $apiKeyInput)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11.5))
                        .onSubmit { saveKey() }
                    Button("Speichern") { saveKey() }
                        .buttonStyle(SubtleButtonStyle())
                        .foregroundStyle(.blue)
                        .disabled(apiKeyInput.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            if let keyError {
                Text(keyError).font(.system(size: 10.5)).foregroundStyle(.red)
            } else if keySaved {
                Text("Gespeichert.").font(.system(size: 10.5)).foregroundStyle(.green)
            }

            Text("Bleibt lokal im Keychain. Key erstellen unter \(provider.keyConsoleURL).")
                .font(.system(size: 10))
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    @ViewBuilder
    private var modelSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Modelle")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                Spacer()
                if appState.isLoadingModelCatalog {
                    ProgressView().controlSize(.small)
                } else {
                    Button("Modelle laden") { appState.loadModelCatalog() }
                        .font(.system(size: 10, weight: .medium))
                        .buttonStyle(.plain)
                        .foregroundStyle(.blue)
                }
            }

            modelPicker(
                title: "Transkription",
                options: appState.transcriptionModelOptions(),
                selection: Binding(
                    get: { appState.providerSettings.currentTranscriptionModel },
                    set: { appState.providerSettings.setTranscriptionModel($0, for: provider) }
                )
            )

            modelPicker(
                title: "Sprachmodell (LLM)",
                options: appState.formattingModelOptions(),
                selection: Binding(
                    get: { appState.providerSettings.currentFormattingModel },
                    set: { appState.providerSettings.setFormattingModel($0, for: provider) }
                )
            )

            if let err = appState.modelCatalogError {
                Text(err).font(.system(size: 10.5)).foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            } else if appState.currentCatalog == nil {
                Text("Tipp: \u{201E}Modelle laden\u{201C} holt die aktuelle Liste von \(provider.displayName).")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
            }
        }
    }

    private func modelPicker(title: String, options: [String], selection: Binding<String>) -> some View {
        HStack(spacing: 8) {
            Text(title)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .frame(width: 120, alignment: .leading)
            Picker("", selection: selection) {
                ForEach(options, id: \.self) { model in
                    Text(model).tag(model)
                }
            }
            .labelsHidden()
            .controlSize(.small)
            .frame(maxWidth: .infinity)
        }
    }

    private func saveKey() {
        let trimmed = apiKeyInput.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else {
            keyError = "Bitte trage deinen \(provider.displayName) API Key ein."
            return
        }
        KeychainService.invalidateCache()
        do {
            try KeychainService.save(key: provider.keychainKey, value: trimmed)
            apiKeyInput = ""
            editingKey = false
            keyError = nil
            keySaved = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 2) { keySaved = false }
        } catch {
            keyError = "\(provider.displayName) API Key konnte nicht gespeichert werden."
        }
    }
}

// MARK: - Access Settings (Tab 1: Zugang)

struct AccessSettingsView: View {
    @Bindable var appState: AppState

    @State private var launchAtLoginService = LaunchAtLoginService()
    @State private var currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
    @State private var installActionErrorText: String?
    @State private var showCleanupOptions = false
    @State private var deleteLocalDataOnCleanup = true
    @State private var cleanupStatusText: String?
    @State private var cleanupErrorText: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Berechtigungen")

                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: appState.accessibilityPermissionGranted ? "checkmark.circle.fill" : "exclamationmark.triangle.fill")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(appState.accessibilityPermissionGranted ? .green : .orange)
                        .frame(width: 18, height: 18)

                    VStack(alignment: .leading, spacing: 3) {
                        Text(appState.accessibilityPermissionGranted ? "Direktes Einfügen ist freigegeben." : "Direktes Einfügen ist noch nicht freigegeben.")
                            .font(.system(size: 11.5, weight: .semibold))
                            .foregroundStyle(.primary)

                        Text("Öffne Bedienungshilfen und aktiviere Blitztext. Falls Blitztext schon aktiv ist, einmal aus- und wieder einschalten.")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    Button("Bedienungshilfen öffnen") {
                        appState.requestAccessibilityPermission()
                    }
                    .buttonStyle(SubtleButtonStyle())

                    Button("Erneut prüfen") {
                        appState.refreshAccessibilityPermission()
                    }
                    .buttonStyle(SubtleButtonStyle())
                }
            }

            ProviderConfigView(appState: appState)

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Installation")

                Text(installationHeadline)
                    .font(.system(size: 11.5, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(installationDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(BlitztextInstallLocationService.bundleURL.path)
                    .font(.system(size: 10.5, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .textSelection(.enabled)

                if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                    Text("Weitere Blitztext-Kopien auf diesem Mac können doppelte Login-Items auslösen.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                }

                HStack(spacing: 8) {
                    if BlitztextInstallLocationService.shouldOfferMoveToApplications {
                        Button("Nach /Applications bewegen") {
                            moveToApplications()
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }

                    Button("Im Finder zeigen") {
                        revealInFinder(urls: [BlitztextInstallLocationService.bundleURL])
                    }
                    .buttonStyle(SubtleButtonStyle())

                    if !BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                        Button("Weitere Kopien zeigen") {
                            revealInFinder(urls: BlitztextInstallLocationService.otherInstalledBundleURLs)
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }
                }

                if let installActionErrorText {
                    Text(installActionErrorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Updates")

                Text("Diese Preview hat keinen oeffentlichen Update-Feed. Baue neue Versionen selbst aus dem Repo.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !currentInstallLocation.isCanonicalInstall {
                    Text("Hotkeys und Login-Start laufen am stabilsten, wenn Blitztext aus /Applications gestartet wird.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.orange)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    Text("Updates sind in dieser Preview manuell: pull, build, starten.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                }
            }

            // Launch at Login
            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Beim Anmelden")

                Toggle("Blitztext automatisch starten", isOn: Binding(
                    get: { launchAtLoginService.isEnabled },
                    set: { launchAtLoginService.setEnabled($0) }
                ))
                .toggleStyle(.switch)

                Text(launchAtLoginService.errorText ?? launchAtLoginService.helperText)
                    .font(.system(size: 10.5))
                    .foregroundStyle(
                        launchAtLoginService.errorText == nil
                            ? AnyShapeStyle(.secondary)
                            : AnyShapeStyle(.red)
                    )
                    .fixedSize(horizontal: false, vertical: true)
            }

            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Hinweis")

                Text("Fuer direktes Einfuegen: Blitztext einmal nach /Applications legen und danach Mikrofon sowie Bedienungshilfen erlauben.")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        RoundedRectangle(cornerRadius: 8)
                            .fill(Color.primary.opacity(0.03))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: 8)
                            .strokeBorder(Color.primary.opacity(0.05), lineWidth: 0.5)
                    )
            }

            VStack(alignment: .leading, spacing: 8) {
                SectionLabel(text: "Sauber Entfernen")

                Text("Vor dem Löschen Blitztext erst auf diesem Mac bereinigen. So verschwinden Anmeldestart und lokale Daten sauber aus dem Weg.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                if showCleanupOptions {
                    Toggle("Zugangsdaten und Einstellungen dieses Macs löschen", isOn: $deleteLocalDataOnCleanup)
                        .toggleStyle(.switch)

                    Text("Danach Blitztext beenden und die App aus /Applications löschen. Bereits verwaiste alte Login-Items können in den Systemeinstellungen einmalig manuell entfernt werden.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)

                    HStack(spacing: 8) {
                        Button("Abbrechen") {
                            showCleanupOptions = false
                        }
                        .buttonStyle(SubtleButtonStyle())

                        Button("Jetzt bereinigen") {
                            runCleanup()
                        }
                        .buttonStyle(SubtleButtonStyle())
                        .foregroundStyle(.red)
                    }
                } else {
                    Button("Entfernung vorbereiten") {
                        showCleanupOptions = true
                    }
                    .buttonStyle(SubtleButtonStyle())
                }

                if let cleanupStatusText {
                    Text(cleanupStatusText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.green)
                        .fixedSize(horizontal: false, vertical: true)
                }

                if let cleanupErrorText {
                    Text(cleanupErrorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

        }
        .padding(16)
        .onAppear {
            launchAtLoginService.refresh()
            refreshInstallState()
        }
    }

    private var installationHeadline: String {
        switch currentInstallLocation {
        case .applications:
            return "Blitztext liegt am richtigen Ort."
        case .userApplications:
            return "Blitztext liegt noch in ~/Applications."
        case .outsideApplications:
            return "Blitztext liegt noch nicht in /Applications."
        case .unknown:
            return "Der Installationsort konnte nicht sicher erkannt werden."
        }
    }

    private var installationDetail: String {
        switch currentInstallLocation {
        case .applications:
            if BlitztextInstallLocationService.otherInstalledBundleURLs.isEmpty {
                return "Für stabile Login-Items und Updates nur diese Kopie weiterverwenden."
            }
            return "Diese Kopie ist korrekt. Zusätzliche Kopien solltest du später entfernen."
        case .userApplications:
            return "Fuer stabile Hotkeys und Login-Items sollte Blitztext nur aus /Applications laufen."
        case .outsideApplications:
            return "Verschiebe Blitztext einmal nach /Applications, damit Anmeldestart und Hotkeys sauber bleiben."
        case .unknown:
            return "Öffne Blitztext möglichst direkt aus /Applications."
        }
    }

    private func refreshInstallState() {
        currentInstallLocation = BlitztextInstallLocationService.currentInstallLocation
        installActionErrorText = nil
    }

    private func moveToApplications() {
        installActionErrorText = nil

        do {
            try BlitztextInstallLocationService.moveToApplicationsAndRelaunch()
        } catch {
            installActionErrorText = error.localizedDescription
        }
    }

    private func runCleanup() {
        cleanupStatusText = nil
        cleanupErrorText = nil

        let report = deleteLocalDataOnCleanup
            ? BlitztextCleanupService.cleanupUserData()
            : BlitztextCleanupService.removeLaunchAtLoginRegistration()

        KeychainService.invalidateCache()
        launchAtLoginService.refresh()
        refreshInstallState()

        if report.failedItems.isEmpty {
            cleanupStatusText = deleteLocalDataOnCleanup
                ? "Anmeldestart und lokale Daten wurden bereinigt. Jetzt Blitztext beenden und aus /Applications löschen."
                : "Anmeldestart wurde deaktiviert. Jetzt Blitztext beenden und aus /Applications löschen."
            showCleanupOptions = false

            let urlsToReveal = report.knownInstallBundleURLs.isEmpty
                ? [BlitztextInstallLocationService.bundleURL]
                : report.knownInstallBundleURLs
            revealInFinder(urls: urlsToReveal)
            return
        }

        let failureSummary = report.failedItems
            .map { "\($0.url.lastPathComponent): \($0.errorDescription)" }
            .joined(separator: "\n")
        cleanupErrorText = "Nicht alles konnte bereinigt werden:\n\(failureSummary)"
    }

    private func revealInFinder(urls: [URL]) {
        guard !urls.isEmpty else { return }
        NSWorkspace.shared.activateFileViewerSelecting(urls)
    }
}

// MARK: - Customize Settings (Tab 2: Anpassen)

struct CustomizeSettingsView: View {
    @Bindable var appState: AppState

    private var installedLocalModels: [LocalTranscriptionModel] {
        LocalTranscriptionService.installedModels()
    }

    private var localModelOptions: [LocalTranscriptionModel] {
        LocalTranscriptionService.modelOptions()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 20) {

            // MARK: Lokaler Modus
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Sicherer Lokaler Modus")

                Toggle("Sicherer Lokaler Modus", isOn: $appState.appSettings.secureLocalModeEnabled)
                    .toggleStyle(.switch)
                    .onChange(of: appState.appSettings.secureLocalModeEnabled) { _, newValue in
                        if newValue && !appState.selectedLocalModelIsInstalled {
                            appState.installSelectedLocalModel()
                        }
                    }

                HStack(spacing: 6) {
                    Image(systemName: appState.selectedLocalModelIsInstalled ? "checkmark.circle.fill" : "arrow.down.circle.fill")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(appState.selectedLocalModelIsInstalled ? .green : .blue)
                    Text(appState.selectedLocalModelIsInstalled ? "\(installedLocalModels.count) lokales WhisperKit-Modell installiert." : "Das ausgewählte Modell wird beim Installieren lokal gespeichert.")
                        .font(.system(size: 10.5))
                        .foregroundStyle(.secondary)
                    Spacer()
                }

                HStack(spacing: 8) {
                    Text("Lokales Modell")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: Binding(
                        get: { appState.selectedLocalModelName },
                        set: { appState.appSettings.selectedLocalTranscriptionModelName = $0 }
                    )) {
                        ForEach(localModelOptions) { model in
                            Text("\(model.displayName) · \(model.installStateLabel)").tag(model.id)
                        }
                    }
                    .labelsHidden()
                    .controlSize(.small)
                    .disabled(appState.isDownloadingLocalModel)
                }

                if let progress = appState.localModelDownloadProgress {
                    VStack(alignment: .leading, spacing: 4) {
                        ProgressView(value: progress)
                        Text(appState.localModelDownloadStatusText ?? "Modell wird geladen...")
                            .font(.system(size: 10.5))
                            .foregroundStyle(.secondary)
                    }
                } else {
                    HStack(spacing: 10) {
                        Button(appState.localModelDownloadButtonTitle) {
                            appState.installSelectedLocalModel()
                        }
                        .controlSize(.small)
                        .disabled(appState.selectedLocalModelIsInstalled)

                        Link("Modellseite", destination: LocalTranscriptionService.modelPageURL(for: appState.selectedLocalModelName))
                            .font(.system(size: 10.5, weight: .medium))
                    }
                }

                if let errorText = appState.localModelDownloadErrorText {
                    Text(errorText)
                        .font(.system(size: 10.5))
                        .foregroundStyle(.red)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Divider().padding(.vertical, 2)

                Toggle("Auch lokal formatieren (über Cloud-LLM)", isOn: $appState.providerSettings.formatLocalTranscription)
                    .toggleStyle(.switch)
                    .font(.system(size: 11.5))

                Text("Standard aus = bleibt komplett offline (nur Whisper auf dem Gerät). An = der lokale Text wird zur Formatierung an den gewählten Anbieter geschickt (verlässt das Gerät). Wörterbuch-Begriffe gibt Blitztext Whisper ohnehin als lokalen Aussprache-Hinweis mit.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Tastenkuerzel
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Tastenk\u{00FC}rzel")

                VStack(spacing: 6) {
                    ForEach(WorkflowType.allCases) { type in
                        HStack {
                            Text(type.hotkeyLabel)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .frame(width: 124, alignment: .leading)
                            Text(appState.displayName(for: type))
                                .font(.system(size: 11.5, weight: .medium))
                            Spacer()
                        }
                    }
                }

                Text("Jedes Kürzel ist ein Umschalter: einmal drücken zum Starten, nochmal drücken (oder Escape) zum Beenden. Der Text wird direkt eingefügt.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Anbieter & Modelle (Hinweis – konfiguriert unter „Zugang")
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "Anbieter & Modelle")
                Text("Anbieter (OpenRouter / Groq), API-Key und Modelle wählst du oben unter \u{201E}Zugang \u{2192} Konfiguration\u{201C}.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            // MARK: Blitztext+
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Blitztext+")

                // Tone
                VStack(alignment: .leading, spacing: 8) {
                    Text("Schreibstil")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.textImprovementSettings.tone) {
                        ForEach(TextImprovementSettings.TextTone.allCases) { tone in
                            Text(tone.displayName).tag(tone)
                        }
                    }
                    .pickerStyle(.segmented)
                }

                // System Prompt
                VStack(alignment: .leading, spacing: 8) {
                    Text("Eigene Anweisung")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $appState.textImprovementSettings.systemPrompt)
                        .font(.system(size: 11))
                        .frame(height: 64)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                        .overlay(alignment: .topLeading) {
                            if appState.textImprovementSettings.systemPrompt.isEmpty {
                                Text("z.B. \"Schreibe pr\u{00E4}gnant und ohne F\u{00FC}llw\u{00F6}rter.\"")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.quaternary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                }

                // Context
                VStack(alignment: .leading, spacing: 8) {
                    Text("Kontext")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextField("z.B. \"E-Mails im Bereich Unternehmensberatung\"", text: $appState.textImprovementSettings.context)
                        .textFieldStyle(.roundedBorder)
                        .font(.system(size: 11))
                }
            }

            // MARK: Blitztext $%&!
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Blitztext $%&!")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Eigene Anweisung")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    TextEditor(text: $appState.dampfAblassenSettings.systemPrompt)
                        .font(.system(size: 11))
                        .frame(height: 80)
                        .scrollContentBackground(.hidden)
                        .padding(8)
                        .background(Color.primary.opacity(0.03), in: RoundedRectangle(cornerRadius: 6))
                        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(Color.primary.opacity(0.06), lineWidth: 0.5))
                        .overlay(alignment: .topLeading) {
                            if appState.dampfAblassenSettings.systemPrompt.isEmpty {
                                Text("z.B. \"Formuliere den Text sachlich und freundlich um.\"")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.quaternary)
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 12)
                                    .allowsHitTesting(false)
                            }
                        }
                }
            }

            // MARK: Blitztext :)
            VStack(alignment: .leading, spacing: 10) {
                SectionLabel(text: "Blitztext :)")

                VStack(alignment: .leading, spacing: 8) {
                    Text("Emoji-Dichte")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)

                    Picker("", selection: $appState.emojiTextSettings.emojiDensity) {
                        ForEach(EmojiTextSettings.EmojiDensity.allCases) { density in
                            Text(density.displayName).tag(density)
                        }
                    }
                    .pickerStyle(.segmented)
                }
            }

            // MARK: Wörterbuch (eigener Punkt – Hinweis)
            VStack(alignment: .leading, spacing: 6) {
                SectionLabel(text: "W\u{00F6}rterbuch")
                Text("Das W\u{00F6}rterbuch ist ein eigener Punkt: Buch-Symbol oben in der Men\u{00FC}leiste \u{2192} \u{201E}W\u{00F6}rterbuch\u{201C}.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

        }
        .padding(16)
    }
}

// MARK: - Flow Layout (for term tags)

struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        return result.size
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        let result = arrangeSubviews(proposal: proposal, subviews: subviews)
        for (index, position) in result.positions.enumerated() {
            subviews[index].place(at: CGPoint(x: bounds.minX + position.x, y: bounds.minY + position.y), proposal: .unspecified)
        }
    }

    private func arrangeSubviews(proposal: ProposedViewSize, subviews: Subviews) -> (positions: [CGPoint], size: CGSize) {
        let maxWidth = proposal.width ?? .infinity
        var positions: [CGPoint] = []
        var x: CGFloat = 0
        var y: CGFloat = 0
        var rowHeight: CGFloat = 0
        var maxX: CGFloat = 0

        for subview in subviews {
            let size = subview.sizeThatFits(.unspecified)
            if x + size.width > maxWidth && x > 0 {
                x = 0
                y += rowHeight + spacing
                rowHeight = 0
            }
            positions.append(CGPoint(x: x, y: y))
            rowHeight = max(rowHeight, size.height)
            x += size.width + spacing
            maxX = max(maxX, x)
        }

        return (positions, CGSize(width: maxX, height: y + rowHeight))
    }
}
