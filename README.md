# Voice-to-Markdown (VTMD)

A local, macOS-native tool for offline Speech-to-Text and AI-powered Markdown generation. Two modes: global keyboard dictation into any window, and an interactive split-UI agent orchestrator.

| Model Selection | STT → Agent → Markdown |
|---|---|
| <img src="demo/model-selection.png" alt="Model selection UI" width="250"/> | <img src="demo/vtmd-chat.png" alt="VTMD chat UI" width="250"/> |

---

## Requirements

| Dependency | Purpose | Install |
|---|---|---|
| Xcode 15+ | Build toolchain | Mac App Store |
| xcodegen | Project generation | `brew install xcodegen` |
| whisper-cli | Local STT engine | `brew install whisper-cpp` |
| ffmpeg | Audio format conversion | `brew install ffmpeg` |
| tmux | CLI agent process management | `brew install tmux` |

Optional: `brew install swiftlint` and `gem install xcpretty` for linting and formatted build output.

---

## Quick Start

```bash
# 1. Clone
git clone https://github.com/xajik/voice-to-md.git
cd voice-to-md

# 2. Install deps and generate Xcode project
make setup

# 3. Open in Xcode
make open
# — or build and launch directly —
make run
```

### First launch

1. Grant **Microphone** access when prompted.
2. Grant **Accessibility** access in *System Settings → Privacy & Security → Accessibility* (required for keystroke injection in Flow 1).
3. Open the **Model Settings** panel from the status bar menu and download a Whisper model (Base recommended to start).

---

## Development Commands

```bash
make check          # Verify all dependencies are installed
make setup          # Install xcodegen + generate VoiceToMarkdown.xcodeproj
make generate       # Re-generate project after editing project.yml
make open           # Open in Xcode

make build          # Release build (no code signing)
make build-debug    # Debug build
make run            # Build release + launch the app

make test           # Run all unit tests
make test-verbose   # Run tests without xcpretty (raw xcodebuild output)

make lint           # Run SwiftLint
make lint-fix       # Run SwiftLint with auto-fix

make clean          # Remove .build/ and .xcodeproj
make clean-all      # Also clears Xcode DerivedData for this project

make dmg            # Print release instructions (DMG built via CI)
```

---

## Modes

### Flow 1 — Global Dictation (invisible)

`Cmd+Opt+]` → captures mic → whisper.cpp transcribes → CGEvent injects text into the active window.

No UI shown. Works in any app (Terminal, browser, editor). Stops on 5 s silence or second hotkey press.

### Flow 2 — Agent Orchestration (visual)

Click the menu bar mic icon → **Start Agent Mode**.

- **HUD bubble** (bottom-right, draggable) shows live STT feed and agent state.
- **Main canvas** is a full-window editable Markdown editor that syncs with the agent's output file.
- Agent runs in a detached tmux session at `~/.vtmd/`; the app communicates via filesystem IPC and a local HTTP hook server.

---

## File System Layout

```
~/.vtmd/
├── config.toml                          # agent command (default: claude --dangerously-skip-permissions)
├── models/tts/ggml-{size}.bin           # Whisper models
├── voice-to-markdown/{timestamp}/
│   ├── {timestamp}.txt                  # raw STT transcript (append-only)
│   └── {timestamp}.md                  # agent's structured output (replace on each update)
├── .claude/commands/tsq-voice-to-md.md  # auto-installed agent prompt
├── .agents/commands/tsq-voice-to-md.md
└── .opencode/commands/tsq-voice-to-md.md
```

Set the CLI agent command in `~/.vtmd/config.toml`:

```toml
command = "claude --dangerously-skip-permissions"
```

Supported agents: `claude`, `claude-code`, `gemini`, `opencode`, `codex`.

---

## Supported Agents

| Agent | Voice Hooks | Hook Mechanism |
|---|---|---|
| Claude Code | ✅ | HTTP Notification hook |
| Gemini | ✅ | AfterAgent shell command |
| OpenCode | ❌ | Event-based TS plugin |
| Codex | ❌ | Global config notify |

---

## Project Structure

```
VoiceToMarkdown/
├── App/                    # @main entry point, AppDelegate, status bar
├── Models/                 # VTMDSession, SessionState, ModelSize, DownloadProgress
├── Services/
│   ├── Audio/             # AVAudioEngine capture + ffmpeg WAV conversion
│   ├── FileSystem/        # VTMDFileManager + DispatchSource file watcher
│   ├── HookServer/        # NWListener HTTP server + route handlers
│   ├── Providers/         # Provider protocol + Claude/Gemini/OpenCode/Codex
│   ├── STT/               # WhisperService + TranscriptBuffer actor
│   └── Tmux/              # TmuxSession (spawn, paste, send-keys, kill)
├── Features/
│   ├── GlobalDictation/   # HotkeyMonitor (Carbon) + KeystrokeInjector (CGEvent)
│   ├── AgentOrchestration/ # SessionCoordinator (full Flow 2 lifecycle)
│   └── ModelManagement/   # URLSession streaming model downloader
└── UI/
    ├── HUD/               # Draggable frosted-glass bubble
    ├── Editor/            # NSTextView Markdown editor with two-way file sync
    ├── ModelSelector/     # Download or pick local .bin
    └── Settings/          # Prerequisite checker
```

---

## Testing

```bash
make test
```

9 test files covering: `TranscriptBuffer` (buffer lifecycle, full cycle), `HookHandlers` (routing, JSON parsing, callbacks), `SessionState` (all computed properties), `ModelSize` (URLs, paths), `VTMDSession` (id format, path construction), `ProviderHookOutput` (Claude/Gemini JSON schema, OpenCode TS plugin), `DownloadProgress` (fraction/percentage math), `VTMDFileManager` (file I/O), `ProviderRegistry` (detection logic).

---

## Releasing

Push a version tag to trigger the release workflow:

```bash
git tag v1.0.0
git push origin v1.0.0
```

GitHub Actions will: build → sign → notarize → package `.dmg` → publish GitHub Release with `appcast.xml` for Sparkle auto-updates.

Required repository secrets: `DEVELOPER_ID_CERT_BASE64`, `DEVELOPER_ID_CERT_PASSWORD`, `KEYCHAIN_PASSWORD`, `APPLE_ID`, `APPLE_APP_PASSWORD`, `APPLE_TEAM_ID`.

---

## Distribution

- **Format:** Notarized `.dmg` (Apple Developer ID signed)
- **Updates:** Sparkle 2 — automatic OTA via GitHub Releases appcast
- **App Store:** Ineligible (non-sandboxed, requires Accessibility)
- **Homebrew:** `brew install --cask vtmd` *(after Cask PR is merged)*
