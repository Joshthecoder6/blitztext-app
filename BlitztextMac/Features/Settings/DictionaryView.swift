import SwiftUI

/// Standalone dictionary editor (its own page), Wispr-Flow style.
struct DictionaryView: View {
    @Bindable var appState: AppState

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                Text("Eigennamen, Fachbegriffe und Ersetzungen. \u{201E}Geschrieben\u{201C} leer lassen = nur die korrekte Schreibweise erzwingen. Ausgef\u{00FC}llt = ersetzen (gesprochen \u{2192} geschrieben).")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                HStack(spacing: 6) {
                    Text("Gesprochen")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Text("Geschrieben (optional)")
                        .font(.system(size: 10, weight: .medium))
                        .foregroundStyle(.tertiary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                    Color.clear.frame(width: 22)
                }

                if appState.dictionarySettings.entries.isEmpty {
                    Text("Noch keine Eintr\u{00E4}ge. F\u{00FC}ge unten welche hinzu.")
                        .font(.system(size: 11))
                        .foregroundStyle(.tertiary)
                        .padding(.vertical, 4)
                }

                ForEach($appState.dictionarySettings.entries) { $entry in
                    HStack(spacing: 6) {
                        TextField("z.B. gpt", text: $entry.spoken)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .frame(maxWidth: .infinity)

                        Image(systemName: "arrow.right")
                            .font(.system(size: 9))
                            .foregroundStyle(.tertiary)

                        TextField("z.B. GPT", text: $entry.written)
                            .textFieldStyle(.roundedBorder)
                            .font(.system(size: 11.5))
                            .frame(maxWidth: .infinity)

                        Button {
                            let id = entry.id
                            withAnimation(.easeOut(duration: 0.15)) {
                                appState.dictionarySettings.entries.removeAll { $0.id == id }
                            }
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .font(.system(size: 14))
                                .foregroundStyle(.tertiary)
                        }
                        .buttonStyle(SubtleButtonStyle())
                    }
                }

                Button {
                    withAnimation(.easeOut(duration: 0.15)) {
                        appState.dictionarySettings.entries.append(DictionaryEntry())
                    }
                } label: {
                    HStack(spacing: 4) {
                        Image(systemName: "plus.circle.fill")
                            .font(.system(size: 14))
                            .foregroundStyle(.blue.opacity(0.7))
                        Text("Eintrag hinzuf\u{00FC}gen")
                            .font(.system(size: 12, weight: .medium))
                    }
                }
                .buttonStyle(SubtleButtonStyle())
                .padding(.top, 2)

                Text("Gilt f\u{00FC}r Diktat und Blitztext+ \u{2013} egal welcher Anbieter. Im lokalen Modus dienen die Begriffe als Aussprache-Hinweis f\u{00FC}r Whisper.")
                    .font(.system(size: 10))
                    .foregroundStyle(.tertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, 4)
            }
            .padding(16)
        }
    }
}
