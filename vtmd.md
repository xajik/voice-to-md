# Voice-to-Markdown Specification

This document provides detailed technical specifications for the voice-to-markdown (VTMD) feature, covering model management, agent lifecycle, audio processing, and file storage. Required for reimplementing the tool in Swift with native macOS UI.

## Overview

1. User select STT model 
2. User select cli agent (claude, gemini, codex, opencode, etc.)
3. We start recording process, reading chunks of STT to file and showing on UI. Non blocking operation
4. In background, agent receives chunks of the raw input and updates .md file. When done with chunk, mode to next unprocessed chunk. Nonn blocking operation. 
5. User see live updates of the raw from STT and update to .md 
6. User can change .md file, which is given to Agent
7. Agent has acces to both files
8. Agent is run in ~/.vtmd folder

## 1. Model Download

### Storage Location

```
~/.vtmd/models/tts/ggml-{size}.bin
```

Allow user to download a model or pick path to existing model

### Available Models

| Size  | Filename              | Approx Size | HuggingFace URL |
|-------|---------------------|------------|--------------|
| tiny  | ggml-tiny.bin        | ~75 MB    | `.../ggml-tiny.bin` |
| base  | ggml-base.bin       | ~150 MB   | `.../ggml-base.bin` |
| small | ggml-small.bin     | ~500 MB   | `.../ggml-small.bin` |
| medium| ggml-medium.bin   | ~1.5 GB   | `.../ggml-medium.bin` |
| large | ggml-large-v3.bin| ~3.2 GB   | `.../ggml-large-v3.bin` |

### Download Process

**Swift Implementation:**

```swift
struct DownloadProgress {
    let size: ModelSize
    let bytesDone: Int64
    let bytesTotal: Int64
    let done: Bool
    let error: Error?
}

// URL construction
func huggingFaceURL(for size: ModelSize) -> String {
    let models = [
        .tiny: "ggml-tiny.bin",
        .base: "ggml-base.bin",
        .small: "ggml-small.bin",
        .medium: "ggml-medium.bin",
        .large: "ggml-large-v3.bin"
    ]
    let modelName = models[size] ?? "ggml-base.bin"
    return "https://huggingface.co/datasets/ggerganov/whisper.cpp/resolve/main/\(modelName)"
}

// Download with progress
func downloadModel(_ size: ModelSize) -> AsyncStream<DownloadProgress> {
    AsyncStream { continuation in
        // 1. Create temp file at ~/.vtmd/models/tts/ggml-{size}.bin.tmp
        // 2. HTTP GET with streaming
        // 3. Write to temp file, emit progress
        // 4. Rename to final name on completion
    }
}
```

### Prerequisites Check

**Required binaries:**
- `whisper-cli` or `whisper-cpp` (from whisper.cpp)
- `ffmpeg` (for audio format conversion)

**Check command:**
```bash
# via shell
which whisper-cli || which whisper-cpp
which ffmpeg
```

Show on the UI to the user if dependencies are missing.

## 2. Agent Working Directory & CLI

### Directory Structure

```
~/.vtmd/voice-to-markdown/{timestamp}/
├── {timestamp}.txt          # raw transcript (append-only)
└── {timestamp}.md       # processed markdown (rewritten)
```

### Agent Configuration

The voice agent is resolved from the daemon config at `~/.vtmd/config.toml`:
```
command = "claude --dangerously-skip-permissions"
```

User input command manually in the UI. Provided command is default.

### CLI Command Injection

Command files are auto-installed to harness directories:

```
# Local (project-relative)
~/.vtmd/.<harnes>/commands/tsq-voice-to-md.md
~/.vtmd/.<harnes>/agents/tsq-voice-to-md.md
```

Supported <harnes> folders: .claude, .agents, .opencode. Copy content to all suported folders Text is hardcoded in the binary.

## 3. Session Lifecycle

### Session States

```
StateIdle          -> no session
StateInitializing  -> tmux spawning, agent loading, stt loading
StateReady       -> agent ready, record button enabled
StateRecording   -> actively recording audio
StateProcessing -> agent processing transcript chunk
StatePaused     -> recording paused, agent alive
StateStopped    -> session ended
```

### Session Initialization

**Flow:**
```
1. Create session directory: ~/.vtmd/notes/{timestamp}/
2. Generate notes filename: note.md
4. Spawn tmux session with agent CLI, wait 15 sec;
5. Install hooks to work directory (.claude/settings.json)
6. Send init prompt with "/vtmd $NOTES_PATH" with tmux. WHere NOTES_PATH is .md file
7. Wait 1 sec and send C-n with tmux
8. Wait for init hook (90s timeout)
9. Write raw STT to same folder note.txt file
```

### Swift Session Object

```swift
struct VTMDRecordingSession {
    let id: String                           // Unix timestamp millis
    let timestamp: String
    let dirPath: String                     // ~/.vtmd/voice-to-markdown/{id}/
    let txtPath: String                     // {dirPath}/{id}.txt
    let mdPath: String                     // {dirPath}/{id}.md
    var state: SessionState
    let agentName: String
    let modelSize: String
}
```

## 4. Agent Initialization (Tmux)

### Tmux Session Creation

```bash
# Session name prefix
vtmd_{timestamp}

# Spawn command
tmux new-session -d -s {sessionName} -c {workDir} -- {command}

workdir will be ~/.vtmd

# Environment
TSQ_HOOKS_PORT={hooksPort}

# Wait for CLI ready (same timing as agent/lifecycle.go)
```

### Init Prompt Format

The init prompt is sent via `tmux paste-buffer`: "/vtmd {NOTES_PATH}"

Where, /vtmd is a command in `commands` folder: 

```
---
description: voice-to-markdown transcription assistant
agent: vtmd
---

In the conversational session with a user, read STT session logs and convert them into the structured document.\
Based on the content, infer purpose and format content accordingly. For example, user asking to
 - work on product requirements --> format document as a product requirements
 - do technical design  --> format document as a technical architecture requirements

**Initialization**
Signal readiness to the daemon immediately by running this bash command:
```bash
curl -s -X POST http://localhost:${TSQ_HOOKS_PORT:-7070}/hooks/voice-to-md/init \
  -H 'Content-Type: application/json' \
  -d '{"status":"ready"}'
```

**Processing chunks**
Yopu are provided notes path file path as an input. 

For each user message you receive (a JSON object with "current_markdown" and "new_transcript"):

1. Clean the transcript, make a sharp content, remove fillers
2. Preserve core content and idea, help with structure and coherense
3. Integrate the cleaned text into current_markdown
4. Rewrite content, fix typo and grammar
5. Write the complete updated markdown to the notes file path shown above (create or overwrite).
6. Post the result to the daemon:
```bash
cat << 'EOF' | jq -Rs '{markdown:.}' | curl -s -X POST http://localhost:${TSQ_HOOKS_PORT:-7070}/hooks/voice-to-md/response -H 'Content-Type: application/json' -d @-
<your updated markdown here>
EOF
```

Remain in this mode for the entire session, processing one chunk at a time.
```

### Swift Tmux Wrapper

```swift
struct TmuxSession {
    let name: String
    
    // Create new session
    func spawn(command: String, workDir: String, env: [String: String]) async throws
    
    // Wait for CLI ready
    func waitForReady(_ timeout: TimeInterval = 30)
    
    // Paste content to session
    func paste(_ content: String, bufferName: String) async throws
    
    // Kill session
    func kill() async throws
}
```

## 5. Input from STT (Speech-to-Text)

### Audio Upload Endpoint

```
POST /api/voice-to-md/upload?model={size}
Content-Type: audio/webm (or audio/ogg)

Body: raw audio bytes from MediaRecorder API
```

### Audio Processing Pipeline

**Step 1: Format Conversion**
| Input | Output |
|-------|-------|
| WebM/OGG | WAV (16 kHz, mono, PCM-16) |

**Command:**
```bash
ffmpeg -y -i {input} -ar 16000 -ac 1 -c:a pcm_s16le {output}
```

**Step 2: Transcription**
```bash
whisper-cli -m {modelPath} -f {wavFile} -nt --output-txt
```

**Output:** Plain text transcript (timestamps stripped)

### Swift STT Service

```swift
class WhisperSTT {
    let modelSize: ModelSize
    let modelPath: String
    
    // Transcribe audio bytes
    func transcribe(_ audioData: Data) async throws -> String
    
    // Convert WebM/OGG to WAV
    static func convertToWAV(input: URL, output: URL) async throws
    
    // Run whisper CLI
    static func runWhisper(modelPath: String, wavPath: String) async throws -> String
}
```

### Special Markers

- `[BLANK_AUDIO]` — signal from whisper when audio is silent; triggers buffer flush

## 6. Send to Agent

### Buffer Logic

**Word threshold:** 30 words to trigger flush

**Two-buffer system:**
```
accumulated: chunks added while agent is free
pending:    chunks added while agent is busy (promoted when agent done)
```

**Silence flush:** 5-second timer after last speech

### Chunk Payload Format

```json
{
  "current_markdown": "{existing file content}",
  "new_transcript": "{cleaned transcript text}"
}
```

### Sending Mechanism

```bash
# Write payload to temp file
# Paste to tmux buffer
tmux set-buffer -b {bufferName} -- {jsonPayload}
# Send paste command to tmux session
tmux paste-buffer -t {sessionName} -b {bufferName}
# Delete buffer
tmux delete-buffer -b {bufferName}
```

### Swift Buffer Implementation

```swift
class TranscriptBuffer {
    var accumulated: [String]
    var pending: [String]
    var agentBusy: Bool
    
    let minWordsToFlush = 30
    
    // Add transcript segment
    func add(_ text: String) -> Bool  // returns true if should flush
    
    // Flush accumulated text
    func flush() -> String
    
    // Mark agent done, promote pending
    func agentDone() -> Bool
}
```

## 7. Update from Agent

### Hook Endpoints

| Endpoint | Method | Trigger |
|----------|--------|--------|
| `/hooks/voice-to-md/init` | POST | Agent signals ready (after loading) |
| `/hooks/voice-to-md/response` | POST | Agent posts processed markdown |
| `/hooks/voice-to-md/notification` | POST | Claude Notification hook fires |

### Response Payload

```json
{
  "markdown": "{processed markdown content}"
}
```

### Agent Response Flow

```swift
// Agent writes to file
// Then posts to daemon
curl -X POST http://localhost:{PORT}/hooks/voice-to-md/response \
  -H 'Content-Type: application/json' \
  -d '{"markdown": "..."}'
```

### Swift Hook Handler

```swift
class VoiceToMDHandlers {
    // POST /hooks/voice-to-md/init
    func handleInit()
    
    // POST /hooks/voice-to-md/response
    func handleResponse(markdown: String) {
        // Write to mdPath
        // Broadcast via SSE
        // Flush buffer if waiting
    }
    
    // POST /hooks/voice-to-md/notification
    func handleNotification(transcriptPath: String) {
        // Fallback: read from transcript if agent busy
    }
}
```

### SSE Events

| Event | Payload |
|-------|---------|
| `transcript` | Raw transcript text |
| `markdown` | Processed markdown |
| `state` | Session state string |
| `error` | Error message |
| `progress` | Download progress 0-100 |

## 8. File Storage

### Directory Structure

```
~/.vtmd/
├── config.toml                    # daemon config
├── device-id
├── voice-to-markdown/
│   └── {timestamp}/
│       ├── {timestamp}.txt     # raw transcript
│       └── {timestamp}.md     # processed markdown
├── notes/
│   └── {YYYYMMDD}/
│       └── {HHMMSS}.md       # per-session notes (symlink/copy)
└── models/tts/
    └── ggml-{size}.bin        # whisper models
```

### File Operations

| File | Mode | Description |
|------|------|-------------|
| `*.txt` | APPEND | New transcript segments |
| `*.md` | REPLACE | Full markdown on each update |

### Swift FileManager Usage

```swift
// Append transcript
func appendTranscript(_ text: String) throws {
    let handle = try FileHandle(forWritingTo: txtURL)
    defer { try? handle.close() }
    try handle.seekToEnd()
    try handle.write(contentsOf: (text + "\n").data(using: .utf8)!)
}

// Write markdown (replace)
func writeMarkdown(_ content: String) throws {
    try content.write(toFile: mdPath, atomically: true, encoding: .utf8)
}

// Read markdown
func readMarkdown() -> String {
    try? String(contentsOfFile: mdPath, encoding: .utf8) ?? ""
}
```

## API Routes Summary

### Daemon Routes

| Method | Path | Handler |
|--------|------|--------|
| POST | `/api/voice-to-md/session/start` | StartSession |
| POST | `/api/voice-to-md/recording/start` | StartRecording |
| POST | `/api/voice-to-md/recording/pause` | PauseRecording |
| POST | `/api/voice-to-md/session/stop` | StopSession |
| POST | `/api/voice-to-md/upload?model=` | ReceiveAudioChunk |
| GET | `/api/voice-to-md/status` | Status |
| GET | `/api/voice-to-md/content` | Markdown |
| GET | `/api/voice-to-md/transcript` | Transcript |
| GET | `/api/voice-to-md/stream` | SSE |
| GET | `/api/voice-to-md/models` | ListModels |
| GET | `/api/voice-to-md/prereqs` | CheckPrereqs |
| POST | `/api/voice-to-md/models/download` | DownloadModel |
| GET | `/api/voice-to-md/agents` | ListAgents |
| GET | `/api/voice-to-md/sessions` | ListSessions |

### Hook Routes

| Method | Path | Handler |
|--------|------|--------|
| POST | `/hooks/voice-to-md/init` | AgentInit |
| POST | `/hooks/voice-to-md/response` | AgentResponse |
| POST | `/hooks/voice-to-md/notification` | AgentNotification |

## Key Timing Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `silenceFlushDelay` | 5s | Auto-flush after silence |
| `agentInitTimeout` | 90s | Init hook timeout |
| `minWordsToFlush` | 30 | Buffer flush threshold |
| `tmuxReadyWait` | 30s (variable) | CLI initialization wait |

## Native macOS Integration

### Recommended Approach

1. **Audio Capture:** AVAudioEngine with AVAudioInputNode
   - Configure for 16kHz mono PCM recording
   - Buffer audio in memory, send chunks on silence or threshold

2. **File Monitoring:** DispatchSource for .md file changes
   - Read on change for live preview

3. **Process Management:** Process (Foundation) for tmux
   - Alternative: SwiftNIO for SSE streaming

4. **Storage:** FileManager + atomic writes
   - Optionally use SQLite.swift for session metadata

5. **Network:** URLSession for HTTP hooks to daemon
   - Or connect directly to agent if running locally

### UI Components

- **Record Button:** NSButton with audio level meter
- **Preview:** NSTextView with live markdown preview
- **Session List:** NSTableView
- **Model Selector:** NSPopUpButton

## 9. Provider Hook Implementations

Each AI provider uses different mechanisms for hooks. The VTMD feature requires `SetupVoice()` to be implemented for each provider to receive Notification/AfterAgent callbacks.

### Provider Interface

```swift
protocol Provider {
    func name() -> String
    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws
    func setupVoice(workDir: String, hooksPort: Int) throws  // VTMD-specific
    func usesHooks() -> Bool
    func env(hooksPort: Int) -> [String]
    func stdin(_ prompt: String) -> String
    func extraArgs() -> [String]
}
```

Error returned when provider doesn't support voice hooks:

```swift
let ErrNotSupported = NSError(domain: "Provider", code: 1, userInfo: [
    NSLocalizedDescriptionKey: "provider does not support this feature"
])
```

---

### 9.1 Claude Code (Anthropic)

**Hook file:** `{workDir}/.claude/settings.json`

**SetupVoice Implementation:**

```swift
func setupVoice(workDir: String, hooksPort: Int) throws {
    let settingsPath = "\(workDir)/.claude/settings.json"
    let hooks: [String: Any] = [
        "Notification": [[
            "matcher": "*",
            "hooks": [[
                "type": "http",
                "url": "http://localhost:\(hooksPort)/hooks/voice-to-md/notification"
            ]]
        ]]
    ]
    try writeJSON(to: settingsPath, object: hooks)
}
```

**Generated settings.json:**

```json
{
  "Notification": [
    {
      "matcher": "*",
      "hooks": [
        {
          "type": "http",
          "url": "http://localhost:8484/hooks/voice-to-md/notification"
        }
      ]
    }
  ]
}
```

**Swift implementation:**

```swift
import Foundation

class ClaudeCodeProvider: Provider {
    let name: String = "claude-code"
    
    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
        let settingsPath = "\(workDir)/.claude/settings.json"
        let hooks: [String: Any] = [
            "Stop": [[
                "matcher": "*",
                "hooks": [[
                    "type": "http",
                    "url": "http://localhost:\(hooksPort)/hooks/stop?agent=\(agentID)&task_id=\(taskID)"
                ]]
            ]],
            "StopFailure": [[
                "hooks": [[
                    "type": "http",
                    "url": "http://localhost:\(hooksPort)/hooks/stop?agent=\(agentID)&task_id=\(taskID)&failure=true"
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }
    
    func setupVoice(workDir: String, hooksPort: Int) throws {
        let settingsPath = "\(workDir)/.claude/settings.json"
        let hooks: [String: Any] = [
            "Notification": [[
                "matcher": "*",
                "hooks": [[
                    "type": "http",
                    "url": "http://localhost:\(hooksPort)/hooks/voice-to-md/notification"
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }
}
```

---

### 9.2 Gemini (Google)

**Hook file:** `{workDir}/.gemini/settings.json`

**SetupVoice Implementation:**

```swift
func setupVoice(workDir: String, hooksPort: Int) throws {
    let settingsPath = "\(workDir)/.gemini/settings.json"
    let hookCmd = "curl -sS -X POST \"http://localhost:\(hooksPort)/hooks/voice-to-md/notification\" -H \"Content-Type: application/json\" -d @- > /dev/null 2>&1; printf '{}'"
    let hooks: [String: Any] = [
        "AfterAgent": [[
            "matcher": "*",
            "hooks": [[
                "name": "tasksquad-voice",
                "type": "command",
                "command": hookCmd,
                "timeout": 5000
            ]]
        ]]
    ]
    try writeJSON(to: settingsPath, object: hooks)
}
```

**Generated settings.json:**

```json
{
  "AfterAgent": [
    {
      "matcher": "*",
      "hooks": [
        {
          "name": "tasksquad-voice",
          "type": "command",
          "command": "curl -sS -X POST \"http://localhost:8484/hooks/voice-to-md/notification\" -H \"Content-Type: application/json\" -d @- > /dev/null 2>&1; printf '{}'",
          "timeout": 5000
        }
      ]
    }
  ]
}
```

**Command hook details:**
- Runs shell command after each agent turn
- Must output valid JSON `{}` to stdout (required by Gemini)
- Uses curl with `-sS` (quiet but show errors)

**Platform-specific:**

```swift
func geminiHookCmd(url: String) -> String {
    if os == "windows" {
        return `curl -sS -X POST "\(url)" -H "Content-Type: application/json" -d @- > NUL 2>&1 & echo {}`
    }
    return `curl -sS -X POST "\(url)" -H "Content-Type: application/json" -d @- > /dev/null 2>&1; printf '{}'`
}
```

**Swift implementation:**

```swift
class GeminiProvider: Provider {
    let name: String = "gemini"
    
    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
        let settingsPath = "\(workDir)/.gemini/settings.json"
        let stopURL = "http://localhost:\(hooksPort)/hooks/stop?agent=\(agentID)&task_id=\(taskID)&provider=gemini"
        let hookCmd = geminiHookCmd(url: stopURL)
        let hooks: [String: Any] = [
            "AfterAgent": [[
                "matcher": "*",
                "hooks": [[
                    "name": "tasksquad-stop",
                    "type": "command",
                    "command": hookCmd,
                    "timeout": 5000
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }
    
    func setupVoice(workDir: String, hooksPort: Int) throws {
        let settingsPath = "\(workDir)/.gemini/settings.json"
        let hookCmd = geminiHookCmd(url: "http://localhost:\(hooksPort)/hooks/voice-to-md/notification")
        let hooks: [String: Any] = [
            "AfterAgent": [[
                "matcher": "*",
                "hooks": [[
                    "name": "tasksquad-voice",
                    "type": "command",
                    "command": hookCmd,
                    "timeout": 5000
                ]]
            ]]
        ]
        try writeJSON(to: settingsPath, object: hooks)
    }
    
    func env(_ hooksPort: Int) -> [String] {
        return ["GEMINI_TRUST_WORKSPACE=1"]
    }
}
```

---

### 9.3 OpenCode (sst)

**Hook mechanism:** TypeScript plugin at `{workDir}/.opencode/plugins/tasksquad.ts`

**SetupVoice Implementation:** Returns `ErrNotSupported`

```swift
func setupVoice(_ workDir: String, _ hooksPort: Int) throws {
    throw ErrNotSupported  // OpenCode doesn't support voice hooks
}
```

**Note:** OpenCode uses event-based plugins. The plugin listens for session events and POSTs to hooks. Voice notification is not currently supported.

**Plugin Template:**

```typescript
// .opencode/plugins/tasksquad.ts
export const TaskSquadPlugin = async ({ client }) => {
  await client.app.log({ body: { service: "tasksquad", level: "info", message: "Plugin initialized" } })

  const post = async (path, body) => {
    try {
      await fetch("http://localhost:" + hooksPort + path, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(body)
      })
    } catch (e) {
      await client.app.log({ body: { service: "tasksquad", level: "error", message: "hook error: " + e.message } })
    }
  }

  return {
    "event": async (input) => {
      const { event } = input

      // Handle message.part.updated
      if (event.type === "message.part.updated" && event.properties?.part) {
        // Cache text parts
      }

      // Handle message.updated (assistant turn complete)
      if (event.type === "message.updated" && event.properties?.info) {
        // Mark complete
      }

      // Handle session.idle (all tools done)
      if (event.type === "session.idle") {
        // POST /hooks/stop with accumulated message
      }

      // Handle session.error
      if (event.type === "session.error") {
        // POST /hooks/stop with error
      }
    },
  }
}
```

**Swift implementation:**

```swift
class OpenCodeProvider: Provider {
    let name: String = "opencode"
    
    func setup(workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
        let pluginDir = "\(workDir)/.opencode/plugins"
        try FileManager.default.createDirectory(at: pluginDir, withIntermediateDirectories: true)
        
        let plugin = """
        // Auto-generated by TaskSquad — do not edit

        export const TaskSquadPlugin = async ({ client }) => {
          await client.app.log({ body: { service: "tasksquad", level: "info", message: "Plugin initialized" } })

          const post = async (path, body) => {
            try {
              await fetch("http://localhost:\(hooksPort)" + path, {
                method: "POST",
                headers: { "Content-Type": "application/json" },
                body: JSON.stringify(body)
              })
            } catch (e) {
              await client.app.log({ body: { service: "tasksquad", level: "error", message: "hook error: " + e.message } })
            }
          }

          const messageCache = new Map()
          let pendingToolCount = 0
          let sessionIdleSent = false

          return {
            "event": async (input) => {
              const { event } = input

              if (event.type === "message.part.updated" && event.properties?.part) {
                const part = event.properties.part
                if (part.type === "text" && part.messageID) {
                  if (!messageCache.has(part.messageID)) {
                    messageCache.set(part.messageID, { sessionID: part.sessionID, textParts: [], completed: false })
                  }
                  const cached = messageCache.get(part.messageID)
                  const existing = cached.textParts.find(p => p.id === part.id)
                  if (existing) {
                    existing.text = part.text || ""
                  } else {
                    cached.textParts.push({ id: part.id, text: part.text || "" })
                  }
                }
              }

              if (event.type === "message.updated" && event.properties?.info) {
                const info = event.properties.info
                if (info.role === "assistant" && info.time?.completed && messageCache.has(info.id)) {
                  messageCache.get(info.id).completed = true
                }
              }

              if (event.type === "tool.execute.before") {
                pendingToolCount++
              }

              if (event.type === "tool.execute.after") {
                pendingToolCount = Math.max(0, pendingToolCount - 1)
                if (pendingToolCount === 0 && !sessionIdleSent) {
                  let lastCompleted = null
                  for (const [, cached] of messageCache.entries()) {
                    if (cached.completed) lastCompleted = cached
                  }
                  const message = lastCompleted ? lastCompleted.textParts.map(p => p.text).join("") : ""
                  await post("/hooks/stop?agent=\(agentID)&task_id=\(taskID)&provider=opencode", { stop_reason: "idle", message })
                  sessionIdleSent = true
                }
              }

              if (event.type === "session.idle") {
                if (pendingToolCount === 0 && !sessionIdleSent) {
                  let lastCompleted = null
                  for (const [, cached] of messageCache.entries()) {
                    if (cached.completed) lastCompleted = cached
                  }
                  const message = lastCompleted ? lastCompleted.textParts.map(p => p.text).join("") : ""
                  await post("/hooks/stop?agent=\(agentID)&task_id=\(taskID)&provider=opencode", { stop_reason: "idle", message })
                  sessionIdleSent = true
                }
              }

              if (event.type === "session.error") {
                await post("/hooks/stop?agent=\(agentID)&task_id=\(taskID)&provider=opencode", { stop_reason: "error", message: event.properties?.error?.message || "Unknown error" })
              }

              if (event.type === "session.updated" && event.properties?.info?.role === "user") {
                sessionIdleSent = false
                messageCache.clear()
                pendingToolCount = 0
              }
            },
          }
        }
        """
        
        try plugin.write(toFile: "\(pluginDir)/tasksquad.ts", atomically: true, encoding: .utf8)
    }
    
    func setupVoice(_ workDir: String, _ hooksPort: Int) throws {
        throw ErrNotSupported
    }
    
    func extraArgs() -> [String] {
        return ["--print-logs"]
    }
}
```

---

### 9.4 Codex (OpenAI)

**Hook mechanism:** Global config at `~/.codex/config.toml`

**SetupVoice Implementation:** Returns `ErrNotSupported`

```swift
func setupVoice(_ workDir: String, _ hooksPort: Int) throws {
    throw ErrNotSupported  // Codex doesn't support voice hooks
}
```

**Config location:** `~/.codex/config.toml` (global, affects all Codex instances)

**Setup Implementation:**

```swift
func setup(_ workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
    let home = FileManager.default.homeDirectoryForCurrentUser.path
    let codexDir = "\(home)/.codex"
    try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
    
    let configPath = "\(codexDir)/config.toml"
    let stopURL = "http://localhost:\(hooksPort)/hooks/codex?agent=\(agentID)&task_id=\(taskID)"
    let notifyLine = "notify = \"curl -sS -X POST '\(stopURL)' -H 'Content-Type: application/json' -d @- > /dev/null 2>&1\""
    
    // Read existing, replace/append notify line
    var lines: [String] = []
    if let existing = try? String(contentsOfFile: configPath, encoding: .utf8) {
        lines = existing.components(separatedBy: "\n")
    }
    
    var replaced = false
    for i in 0..<lines.count {
        if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("notify") {
            lines[i] = notifyLine
            replaced = true
            break
        }
    }
    if !replaced {
        lines.append(notifyLine)
    }
    
    try lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
}
```

**Config.toml format:**

```toml
notify = "curl -sS -X POST 'http://localhost:8484/hooks/codex?agent=...&task_id=...' -H 'Content-Type: application/json' -d @- > /dev/null 2>&1"
```

**Platform-specific:**

```swift
func codexNotifyCmd(url: String) -> String {
    if os == "windows" {
        return "curl -sS -X POST \"\(url)\" -H \"Content-Type: application/json\" -d @- > NUL 2>&1"
    }
    return "curl -sS -X POST '\(url)' -H 'Content-Type: application/json' -d @- > /dev/null 2>&1"
}
```

**Swift implementation:**

```swift
class CodexProvider: Provider {
    let name: String = "codex"
    
    func setup(_ workDir: String, hooksPort: Int, agentID: String, taskID: String) throws {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let codexDir = "\(home)/.codex"
        try FileManager.default.createDirectory(at: codexDir, withIntermediateDirectories: true)
        
        let configPath = "\(codexDir)/config.toml"
        let stopURL = "http://localhost:\(hooksPort)/hooks/codex?agent=\(agentID)&task_id=\(taskID)"
        let notifyLine = "notify = \"\(codexNotifyCmd(url: stopURL))\""
        
        var lines: [String] = []
        if let existing = try? String(contentsOfFile: configPath, encoding: .utf8) {
            lines = existing.components(separatedBy: "\n")
        }
        
        var replaced = false
        for i in 0..<lines.count {
            if lines[i].trimmingCharacters(in: .whitespaces).hasPrefix("notify") {
                lines[i] = notifyLine
                replaced = true
                break
            }
        }
        if !replaced {
            lines.append(notifyLine)
        }
        
        try lines.joined(separator: "\n").write(toFile: configPath, atomically: true, encoding: .utf8)
    }
    
    func setupVoice(_ workDir: String, _ hooksPort: Int) throws {
        throw ErrNotSupported
    }
}
```

---

### 9.5 Provider Registry

```swift
class ProviderRegistry {
    static let shared = ProviderRegistry()
    
    private init() {
        providers = [
            "claude-code": { ClaudeCodeProvider() },
            "claude":      { ClaudeCodeProvider() },
            "gemini":      { GeminiProvider() },
            "opencode":    { OpenCodeProvider() },
            "codex":      { CodexProvider() },
            "stdout":     { StdoutProvider() }
        ]
    }
    
    func detect(command: String, override: String? = nil) -> Provider {
        if let override = override, let factory = providers[override.lowercased()] {
            return factory()
        }
        
        // Auto-detect from command binary name
        let binary = command.components(separatedBy: " ").first ?? command
        let name = URL(fileURLWithPath: binary).lastPathComponent
        if let factory = providers[name.lowercased()] {
            return factory()
        }
        
        // Default to Claude Code
        return ClaudeCodeProvider()
    }
}
```

---

### 9.6 Summary Table

| Provider | Hook File | Voice Support | Hook Type |
|----------|-----------|---------------|-----------|
| Claude Code | `.claude/settings.json` | ✅ Yes | HTTP |
| Gemini | `.gemini/settings.json` | ✅ Yes | Command |
| OpenCode | `.opencode/plugins/*.ts` | ❌ No | Event-based |
| Codex | `~/.codex/config.toml` | ❌ No | Command |