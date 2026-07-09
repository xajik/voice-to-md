# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

The Xcode project is **generated from `project.yml`** — it is gitignored and must be regenerated after any structural change.

```bash
make setup          # Install xcodegen + generate .xcodeproj (first time)
make generate       # Re-generate after editing project.yml
make check          # Verify whisper-cli, ffmpeg, xcodegen are installed

make build          # Release build + sign (auto-detected identity, see below)
make build-debug    # Debug build + sign
make run            # Release build + open the app
make test           # Run all unit tests
make lint           # SwiftLint (optional; skipped if not installed)
make clean          # Remove .build/ and .xcodeproj
make install        # deps + build + copy to /Applications (install.sh delegates here)
```

**Run a single test class:**
```bash
xcodebuild -scheme VoiceToMarkdown -configuration Debug -derivedDataPath .build \
  -destination 'platform=macOS' \
  -only-testing:VoiceToMarkdownTests/TranscriptBufferTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

**Signing:** ad-hoc signatures change every build and silently invalidate macOS TCC grants (microphone, Accessibility). `make build` therefore auto-detects the first "Apple Development" identity in the keychain and signs with it (hardened runtime + entitlements); ad-hoc (`-s -`) is only the fallback when no identity exists. Override with `make build SIGN_IDENTITY="…"` or force ad-hoc with `SIGN_IDENTITY=-`.

## What the app does

Menu-bar macOS app, two flows, both local-only (no cloud services):

1. **Global dictation** — hotkey **⌘⌥]** anywhere: record → whisper.cpp transcription → text typed at the cursor via CGEvent. A Spotlight-style floating panel (`DictationHUDView` in a non-activating `NSPanel`) shows listening/transcribing state.
2. **Agent mode** — window with a markdown editor: record → whisper → 30-word buffer → streaming chat-completions call to a **local OpenAI-compatible LLM server** (omlx/llama.cpp/LM Studio, default `http://127.0.0.1:8000/v1`) that formats the transcript into a live-updating document. Output format is selectable in the HUD control panel: **md** (default), **txt**, or **html** (`OutputFormat` enum; each case carries prompt expectations + a worked example).

## Architecture

### Entry point and UI ownership

`VoiceToMarkdownApp.swift` is `@main` but its `body` only exposes an empty `Settings` scene. All real setup is in `AppDelegate`: status bar item, `SessionCoordinator`, `GlobalDictationManager`, the dictation `NSPanel`, and windows created on demand. **Any window created here must set `isReleasedWhenClosed = false` and be retained in a property** — otherwise AppKit + ARC double-release it on close and crash in the close animation.

### Agent mode pipeline

`SessionCoordinator` (`@MainActor ObservableObject`) owns everything:
- `AudioCaptureService` (AVAudioEngine 16 kHz mono) → PCM buffers are **accumulated into ~4 s chunks** (`transcribeChunkSeconds`) and transcribed **serially** via a FIFO task chain (`enqueueAfterTranscription`). Never transcribe per tap buffer — whisper-cli reloads the model per invocation.
- `WhisperService` (whisper-cli subprocess). `isNoiseOnly()` filters annotation-only chunks like `(wind blowing)` before they reach the buffer.
- `TranscriptBuffer` actor — two-buffer accumulation (30-word flush threshold; pending queue while the LLM is busy).
- `LocalLLMService` — `listModels()` + streaming `formatTranscript()`/`editDocument()`/`appendTranscript()` (SSE); `cleanOutput()` strips `<think>` blocks and code fences. Partial output streams straight into `coordinator.markdown`. System prompts are per-mode **functions** taking an `OutputFormat` — each appends the format's `promptExpectations` (rules + example) and ends with `/no_think`. Payload key is `current_document` (format-neutral).
- `OutputFormat` (Models/) — txt/md/html; drives the system prompt, the HUD dropdown, and the session file extension. Persisted in `BackendSettings` (`vtmd.outputFormat`); snapshotted per flush alongside `mode` so mid-stream changes can't corrupt an in-flight request. Changing it mid-session renames the document file and restarts the `FileWatcher` (`migrateSessionDocument()`).
- `BackendSettings` — UserDefaults-backed base URL + model name (empty = auto-pick first model from `/v1/models`) + output format.
- Session files: `~/.vtmd/voice-to-markdown/{unix_ms}/{id}.txt` (append-only raw) and `{id}.{txt|md|html}` (rewritten; extension follows the output format — `VTMDSession.docPath`).
- HUD control panel (`HUDBubbleView`): send, mic, status | mode switcher + format dropdown | preview (opens `docPath` via `NSWorkspace`, e.g. browser for html) | clear session.

`HUDViewModel` and `MarkdownEditorViewModel` hold the **same** `SessionCoordinator` instance; both subscribe via Combine (`objectWillChange` forwarding / `$markdown` sink) — computed properties alone do not re-render.

### Global dictation

`GlobalDictationManager` → `HotkeyMonitor` (Carbon `RegisterEventHotKey`, keycode `0x1E` = `]`) → `AudioCaptureService` → `WhisperService` → `KeystrokeInjector`. Injection **waits for hotkey modifiers to be released and clears event flags** — synthetic events inherit physically-held modifiers and turn into shortcuts otherwise. Requires Accessibility permission; `AXIsProcessTrusted()` only updates after app restart.

### Key constants

| Constant | Location | Value |
|---|---|---|
| `minWordsToFlush` | `TranscriptBuffer` | 30 words |
| `transcribeChunkSeconds` | `SessionCoordinator` | 4 s |
| silence flush delay | `AudioCaptureService` | 5 s (timer scheduled on main queue — tap thread has no run loop) |
| default LLM URL | `BackendSettings` | `http://127.0.0.1:8000/v1` |
| default output format | `BackendSettings` / `OutputFormat` | `md` (persisted, `vtmd.outputFormat`) |
| default hotkey | `GlobalDictationManager` | `⌘⌥]` (0x1E, cmdKey\|optionKey) |

## Test Layout

Test files in `Tests/VoiceToMarkdownTests/` are pure logic — no network, audio hardware, or LLM server required. `LocalLLMServiceTests` covers request building (per mode × output format), SSE parsing, and output cleaning via the service's static helpers; `OutputFormatTests` covers the format enum and its prompt expectations.

## Concurrency Convention

Swift 5.9 language mode with `-strict-concurrency=minimal`. Pattern throughout: `@MainActor` classes expose `nonisolated` protocol conformances (e.g., `AudioCaptureDelegate`) that dispatch back via `Task { @MainActor in ... }`. Don't switch to Swift 6 strict mode without auditing all `nonisolated` + cross-actor accesses in `SessionCoordinator` and `GlobalDictationManager`.
