# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project State

This is a **specification-only repository** for a macOS-native Swift rewrite of the Voice-to-Markdown (VTMD) tool. No source code exists yet. The full technical spec lives in `vtmd.md` and `README.md`.

## What We're Building

A non-sandboxed macOS app (Swift 5.9+, SwiftUI) that:
1. **Global Dictation Mode** — hotkey-triggered, captures mic via AVAudioEngine → whisper.cpp → CGEvent keystroke injection into any active window.
2. **Agent Orchestration Mode** — split TUI: floating HUD bubble (live STT feed) over full-window editable Markdown editor, with a tmux-managed CLI agent backend.

Requirements: Microphone + Accessibility (System Events) entitlements. Distributed as a notarized `.dmg` (not App Store eligible). Sparkle 2 for OTA updates.

## Architecture: File System as IPC Bus

The filesystem at `~/.vtmd/` is the message bus between the Swift orchestrator and the CLI agent running in tmux:

```
~/.vtmd/
├── config.toml                        # agent command (e.g. "claude --dangerously-skip-permissions")
├── models/tts/ggml-{size}.bin         # whisper models from HuggingFace
├── voice-to-markdown/{timestamp}/
│   ├── {timestamp}.txt               # raw STT transcript (APPEND-only)
│   └── {timestamp}.md               # agent's structured output (REPLACE on each update)
└── notes/{YYYYMMDD}/{HHMMSS}.md
```

**Command files** auto-installed at startup to all supported harness dirs:
- `~/.vtmd/.claude/commands/tsq-voice-to-md.md`
- `~/.vtmd/.agents/commands/tsq-voice-to-md.md`
- `~/.vtmd/.opencode/commands/tsq-voice-to-md.md`

## Session Lifecycle

States: `Idle → Initializing → Ready → Recording → Processing → Paused → Stopped`

Init flow:
1. Create `~/.vtmd/voice-to-markdown/{timestamp}/`
2. Spawn tmux session: `tmux new-session -d -s vtmd_{timestamp} -c ~/.vtmd -- {command}` with `TSQ_HOOKS_PORT` env
3. Install provider hook files (see Provider Hooks below)
4. Send `/vtmd {NOTES_PATH}` via `tmux paste-buffer`, wait 1s, send `C-n`
5. Wait for `POST /hooks/voice-to-md/init` (90s timeout)

Key struct:
```swift
struct VTMDRecordingSession {
    let id: String          // Unix timestamp millis
    let dirPath: String     // ~/.vtmd/voice-to-markdown/{id}/
    let txtPath: String     // raw STT transcript
    let mdPath: String      // processed markdown
    var state: SessionState
    let agentName: String
    let modelSize: String
}
```

## Concurrency Model

- **`TranscriptBuffer` actor**: thread-safe, two-buffer system (`accumulated` + `pending`). Flushes at 30-word threshold or 5s silence.
- **Chunk payload** sent to agent via tmux paste: `{"current_markdown": "...", "new_transcript": "..."}`
- **File watching**: `DispatchSourceFileSystemObject` for `.md` updates → live Markdown preview.
- **Hook server**: local HTTP server on `TSQ_HOOKS_PORT` (default 7070) receives agent signals.

## Provider Hooks

Each CLI agent uses a different hook mechanism. Only Claude Code and Gemini support voice hooks.

| Provider | Hook File | Voice | Mechanism |
|----------|-----------|-------|-----------|
| `claude` / `claude-code` | `{workDir}/.claude/settings.json` | ✅ | HTTP Notification hook |
| `gemini` | `{workDir}/.gemini/settings.json` | ✅ | Shell command AfterAgent hook |
| `opencode` | `{workDir}/.opencode/plugins/tasksquad.ts` | ❌ | Event-based TS plugin |
| `codex` | `~/.codex/config.toml` (global) | ❌ | Shell notify command |

Provider is auto-detected from the binary name in the configured command, defaulting to `ClaudeCodeProvider`.

Hook endpoints the app exposes:
- `POST /hooks/voice-to-md/init` — agent ready
- `POST /hooks/voice-to-md/response` — agent posts `{"markdown": "..."}` after each chunk
- `POST /hooks/voice-to-md/notification` — Claude/Gemini AfterAgent callback

## Audio Pipeline

1. `AVAudioEngine` → PCM buffer capture (16kHz mono)
2. `ffmpeg -y -i {input} -ar 16000 -ac 1 -c:a pcm_s16le {output}` (WebM/OGG → WAV)
3. `whisper-cli -m {modelPath} -f {wavFile} -nt --output-txt`
4. `[BLANK_AUDIO]` marker from whisper triggers immediate buffer flush

Prerequisites checked at startup (shown in UI if missing): `whisper-cli` (or `whisper-cpp`) and `ffmpeg`.

## UI Structure

- **Window**: borderless, `.windowStyle(.hiddenTitleBar)`, non-sandboxed
- **Main canvas**: full-window editable Markdown editor (NSTextView / Runestone), two-way file sync with `{timestamp}.md`
- **HUD bubble**: draggable ZStack overlay with frosted glass (`.regularMaterial`), rounded corners
  - Top row: mic toggle, agent state indicator, copy buttons, expand toggle
  - Bottom row (expandable): live `stt.txt` feed
- **Model selector**: download from HuggingFace or pick local `.bin` path

## Key Constants

| Constant | Value |
|----------|-------|
| `silenceFlushDelay` | 5s |
| `agentInitTimeout` | 90s |
| `minWordsToFlush` | 30 words |
| `tmuxReadyWait` | 30s |
