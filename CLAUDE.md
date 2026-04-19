# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Build & Test Commands

The Xcode project is **generated from `project.yml`** — it is gitignored and must be regenerated after any structural change.

```bash
make setup          # Install xcodegen + generate .xcodeproj (first time)
make generate       # Re-generate after editing project.yml
make check          # Verify whisper-cli, ffmpeg, tmux, xcodegen are installed

make build          # Release build (no signing)
make build-debug    # Debug build
make run            # Release build + open the app
make test           # Run all unit tests
make test-verbose   # Same without xcpretty

make lint           # SwiftLint (optional; skipped if not installed)
make clean          # Remove .build/ and .xcodeproj
make clean-all      # Also clears Xcode DerivedData
```

**Run a single test class:**
```bash
xcodebuild -scheme VoiceToMarkdown -configuration Debug -derivedDataPath .build \
  -destination 'platform=macOS' \
  -only-testing:VoiceToMarkdownTests/TranscriptBufferTests \
  CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO CODE_SIGNING_ALLOWED=NO test
```

**Run a single test method** — append `/testMethodName` to `-only-testing`.

## Architecture

### Project generation

`project.yml` (xcodegen) → `VoiceToMarkdown.xcodeproj`. Targets: `VoiceToMarkdown` (macOS app, deployment 13.0, Swift 5.9 language mode with `-strict-concurrency=minimal`) and `VoiceToMarkdownTests`. Entitlements: non-sandboxed, microphone, Apple Events (Accessibility).

### Entry point and UI ownership

`VoiceToMarkdownApp.swift` is `@main` but its `body` only exposes an empty `Settings` scene. All real setup is in `AppDelegate`: sets `NSApp.activationPolicy(.accessory)`, creates the status bar item, owns the `SessionCoordinator` and `GlobalDictationManager` instances, and creates windows on demand. Spawning a new UI component means wiring it through `AppDelegate`.

### Flow 1 — Global Dictation

`GlobalDictationManager` → `HotkeyMonitor` (Carbon `RegisterEventHotKey`, default `Cmd+Opt+]`) → `AudioCaptureService` (AVAudioEngine, 16 kHz mono) → `AudioConverter.writePCMBuffersToWAV` → `WhisperService.transcribe` → `KeystrokeInjector.typeText` (CGEvent, requires Accessibility). No tmux, no HookServer involved.

### Flow 2 — Agent Orchestration

`SessionCoordinator` (`@MainActor ObservableObject`) is the single coordinator. It owns:
- `TranscriptBuffer` actor — two-buffer accumulation (`accumulated` + `pending`)
- `HookServer` — local HTTP server on port 7070 (default)
- `HookHandlers` — closure-based route dispatch
- `AudioCaptureService` + `WhisperService` — same audio pipeline as Flow 1
- `FileWatcher` — `DispatchSourceFileSystemObject` watching `{session}.md`
- `TmuxSession` — wraps `tmux` process calls (spawn, paste-buffer, send-keys, kill)

`HUDViewModel` and `MarkdownEditorViewModel` both hold a reference to the **same** `SessionCoordinator` instance injected from `AppDelegate`.

### TranscriptBuffer actor — two-buffer design

```
add(text) → accumulated     (when agent free, returns true if ≥30 words)
add(text) → pending         (when agentBusy)
flush()   → joined string, sets agentBusy=true, clears accumulated
agentDone() → promotes pending→accumulated, returns true if new flush needed
flushAll()  → drains both buffers (used on silence/stop)
```

`[BLANK_AUDIO]` from whisper triggers `flushAll()` immediately regardless of word count.

### HookServer

Hand-rolled HTTP/1.1 over `NWListener` (Network framework) — no third-party dependencies. Parses `\r\n\r\n` to split headers from body, strips query string before routing. `HookHandlers.handle(method:path:body:)` is synchronous and returns `(Int, [String: Any])`; callbacks (`onInit`, `onResponse`, `onNotification`) are dispatched on `DispatchQueue.main`. Tests call `handle()` directly without starting the listener.

### Provider system

`ProviderRegistry.detect(from:override:)` extracts the **last path component of the first word** in the command string (handles absolute paths and flags). Falls back to `ClaudeCodeProvider`. `writeJSON(to:object:)` is a global free function in `Provider.swift` used by all provider `setupVoice` implementations — it creates intermediate directories automatically.

| Provider | Voice | Hook file |
|---|---|---|
| `claude` / `claude-code` | ✅ | `{workDir}/.claude/settings.json` — HTTP Notification |
| `gemini` | ✅ | `{workDir}/.gemini/settings.json` — AfterAgent shell command (must `printf '{}'`) |
| `opencode` | ❌ | `{workDir}/.opencode/plugins/tasksquad.ts` — TS event plugin |
| `codex` | ❌ | `~/.codex/config.toml` (global, line-replace) |

### VTMDFileManager

Singleton (`VTMDFileManager.shared`). `bootstrap()` must be called at launch — creates `~/.vtmd/` directories and installs the agent command file to `.claude/commands/`, `.agents/commands/`, `.opencode/commands/`. Agent command is read from `~/.vtmd/config.toml` (`command = "..."` line), defaulting to `"claude --dangerously-skip-permissions"`.

### Key constants (in source, not configurable at runtime)

| Constant | Location | Value |
|---|---|---|
| `minWordsToFlush` | `TranscriptBuffer` | 30 words |
| `hooksPort` | `SessionCoordinator` | 7070 |
| `agentInitTimeout` | `SessionCoordinator.waitForInit` | 90 s |
| silence flush delay | `AudioCaptureService` | 5 s |
| default hotkey | `GlobalDictationManager` | keyCode 0x23, `cmdKey|optionKey` |

## Test Layout

9 test files in `Tests/VoiceToMarkdownTests/`. All tests are pure logic — no network or audio hardware required. Provider hook tests write to a temp dir and verify JSON on disk. `HookHandlersTests` uses `XCTestExpectation` to wait for `DispatchQueue.main.async` callback delivery from `HookHandlers`.

## Concurrency Convention

Swift 5.9 language mode with `-strict-concurrency=minimal`. Pattern throughout: `@MainActor` classes expose `nonisolated` protocol conformances (e.g., `AudioCaptureDelegate`) that dispatch back via `Task { @MainActor in ... }`. Don't switch to Swift 6 strict mode without auditing all `nonisolated` + cross-actor accesses in `SessionCoordinator` and `GlobalDictationManager`.
