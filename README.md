# Blitztext App

Blitztext App is an experimental open-source macOS menubar app for turning speech into text.

It is intentionally small and unfinished. The goal is to make a real workflow visible and hackable: press a hotkey, speak, get clean text back, and paste it into the app you were using.

This is a learning and experimentation project, not a polished product.

> Preview status: bring your own OpenRouter API key, no hosted backend, no warranty, no support guarantee.

## What It Does

Press **fn + Leertaste (Space)** once to start dictating and again to stop. Blitztext then:

1. Transcribes your speech with an **OpenRouter-hosted Whisper model** (`openai/whisper-large-v3-turbo`).
2. Cleans the rough transcript with a **Llama** model — Wispr-Flow style: it applies spoken corrections ("no, scratch that"), detects and formats lists, turns spoken formatting commands ("new paragraph") into real formatting, and removes filler words.
3. Pastes the finished text into the app you were using.

The menu bar also keeps a few manual workflows (all on OpenRouter/Llama):

- **Blitztext**: smart dictation (transcribe + clean formatting). This is the fn + Leertaste hotkey.
- **Blitztext+**: transcribe, then turn the rough draft into cleaner writing.
- **Blitztext $%&!**: turn frustrated speech into a calmer message.
- **Blitztext :)**: add fitting emojis to dictated text.

Enabling **Sicherer Lokaler Modus** switches the main hotkey to fully local transcription via WhisperKit (no server, no Llama formatting).

## Important Preview Notes

- macOS only.
- Bring your own OpenRouter API key (create one at https://openrouter.ai/keys).
- No hosted Blitztext backend is included or provided.
- In online mode, audio and text are sent directly from the app to the OpenRouter API.
- Optional local transcription via WhisperKit/CoreML if you install a compatible model locally.
- `./build.sh` creates a locally ad-hoc-signed development app. No notarized release binary is provided.
- Not production ready.
- No warranty and no support guarantee.

You are welcome to use, fork, adapt, and share this project under the license terms.

The intent is not to ship a one-click finished app. The intent is to make a real AI workflow understandable: clone it, build it, read the code, change it, break it, fix it, and suggest improvements. If you only want to download something and never look inside, this preview will probably feel rough. If you want to learn how a small native macOS AI app is put together, you are in the right place.

## Screenshots

<table>
  <tr>
    <td><img src="docs/screenshots/online-mode.png" alt="Blitztext online transcription mode" width="420"></td>
    <td><img src="docs/screenshots/local-mode.png" alt="Blitztext secure local transcription mode" width="420"></td>
  </tr>
  <tr>
    <td><img src="docs/screenshots/local-model-picker.png" alt="Blitztext local model picker" width="420"></td>
    <td><img src="docs/screenshots/settings-customize.png" alt="Blitztext settings and customization view" width="420"></td>
  </tr>
</table>

## Requirements

- macOS 14 or newer
- Xcode 16 or newer (Swift 5.10), with Command Line Tools installed and selected for `xcodebuild`
- [XcodeGen](https://github.com/yonaskolb/XcodeGen) to generate the Xcode project
- For online transcription and rewriting: an OpenRouter API key (https://openrouter.ai/keys). The defaults are:
  - `openai/whisper-large-v3-turbo` for transcription
  - `meta-llama/llama-3.3-70b-instruct` for smart formatting / rewriting
  - Both model IDs are editable in the app under Settings → Anpassen → Modelle.
- For local-only transcription: a WhisperKit CoreML model in:
  `~/Library/Application Support/Blitztext/models/whisperkit/`

The build also pulls one Swift Package dependency automatically:

- [`argmax-oss-swift`](https://github.com/argmaxinc/argmax-oss-swift) (WhisperKit) — used for local on-device transcription.

Install XcodeGen if needed:

```bash
brew install xcodegen
```

## Build And Run

```bash
git clone https://github.com/Joshthecoder6/blitztext-openrouter.git
cd blitztext-openrouter
./build.sh --run
```

For a local install into `/Applications`:

```bash
./build.sh --install --run
```

The generated `.app` is ad-hoc signed for local development only. Do not treat it as a trusted redistributable binary. A public binary release would need Developer ID signing and notarization.

On first launch, either paste your own OpenRouter API key for online workflows or install a WhisperKit CoreML model for local transcription. Smart formatting and the rewriting workflows require OpenRouter (Llama).

For fully local transcription, install a WhisperKit CoreML model and enable **Sicherer Lokaler Modus** in the app.

For a slower, more explicit walkthrough, see [docs/setup.md](docs/setup.md).

## Permissions

Blitztext asks for:

- **Microphone**: to record your voice.
- **Accessibility**: to paste the result back into the app you were using **and** to run the global **fn + Leertaste** hotkey (it uses a `CGEventTap`, which needs Accessibility). The hotkey consumes the Space press so it is not typed into your document.

If you do not grant Accessibility permission, the global hotkey will not work; you can still start workflows from the menu and copy results manually.

Full Disk Access is not required. If auto-paste does not work even though transcription succeeds, open **System Settings -> Privacy & Security -> Accessibility**, enable Blitztext there, restart Blitztext, and try again with the cursor focused in a text field. If macOS shows multiple Blitztext entries, remove or disable the old ones and grant the permission to the app you just built or installed.

## Data Flow

The preview has no custom backend.

```text
Online transcription: Your Mac -> OpenRouter Audio Transcriptions API (Whisper)
Smart formatting:      Your Mac -> OpenRouter Chat Completions API (Llama)
Local transcription:   Your Mac -> WhisperKit/CoreML on device
```

The app stores your OpenRouter API key in the user's macOS Keychain.

Read [docs/privacy.md](docs/privacy.md) before using the preview with sensitive content.

## Project Structure

```text
BlitztextMac/
  App/          App lifecycle and paste handling
  Features/     Workflows, menu bar UI, settings
  Services/     Recording, OpenAI calls, hotkeys, local storage
  Views/        Shared SwiftUI views
build.sh        Local build script
docs/           Setup, privacy, roadmap, preflight, landing page notes
```

## Local Models

Local transcription is available as an experimental WhisperKit/CoreML path. The app does not bundle a model; choose one in the app, click install, and then switch on **Sicherer Lokaler Modus** from the menu bar or settings.

See [docs/local-models.md](docs/local-models.md).

## Contributing

Contributions are welcome, especially if they make the preview easier to build, understand, or fork.

Please read [CONTRIBUTING.md](CONTRIBUTING.md) first.

## Support And Roadmap

This preview has no formal support promise. See [SUPPORT.md](SUPPORT.md) for how to ask for help without sharing secrets.

The current direction is documented in [ROADMAP.md](ROADMAP.md). Maintainer-facing release checks live in [docs/open-source-preflight.md](docs/open-source-preflight.md).

## License

Code is released under the MIT License. See [LICENSE](LICENSE).

Project names, logos, and app icons are not automatically granted as trademarks or brand assets. See [TRADEMARKS.md](TRADEMARKS.md).

## Legal / Impressum & Datenschutz

This is an experimental, non-commercial open-source project, provided as-is under the MIT License without warranty or support. Nothing is sold here and no installation or operation is performed on your behalf.

The companion website (blitztext.de) is operated by Blackboat Internet GmbH:

- Impressum: https://www.blackboat.com/impressum
- Datenschutz / Privacy: https://www.blackboat.com/datenschutz
