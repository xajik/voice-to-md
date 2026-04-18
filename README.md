# Voice-to-Markdown (VTMD)

## Product Overview
Description: A local, macOS-native developer tool that provides zero-latency, offline Speech-to-Text (STT) and intelligent Markdown generation. It operates via two primary modes: global keyboard dictation into any OS window, and an interactive, split-UI TUI agent orchestrator for structured document generation.
Target Audience: Advanced developers and power users who utilize CLI agents, tmux, and local AI workflows.

## Core User Flows & Requirements

### Flow 1: Global Dictation (Invisible Mode)

Trigger: Global keyboard hotkey.

Action: Captures microphone audio, processes it via local whisper.cpp, and injects output as real-time keystrokes into the active macOS application window.

Requirement: Must bypass macOS Accessibility blocking via direct CGEvent synthesis.

### Flow 2: Agent Orchestration & UI (Visual Mode)

Trigger: Distinct global hotkey.

Initialization: * App verifies/downloads Whisper model to ~/.vtmd/models/. Provide UI for user to select model file or downalod from huggingface.

App prompts user to select a TUI Agent (e.g., Gemini, Claude, Opencode).

App spawns background tmux session, launches CLI agent, and waits for a 15-second initialization timeout.

App injects /vtmd command via tmux send-keys and waits for CLI hook.

Execution: * User speaks; raw STT streams continuously to disk.

App chunks input non-blockingly and feeds it to the agent via tmux.

Agent outputs structured Markdown.

UI Interaction: User can view raw STT, watch live Markdown generation, manually edit the Markdown, and one-click copy either stream.

## UI/UX Requirements

Window Style: Borderless, hidden title bar (.windowStyle(.hiddenTitleBar)).

Main Canvas (Background): A full-window, editable Markdown editor with syntax highlighting (via wrapped NSTextView or native package like Runestone). Two-way file sync ensures manual edits overwrite the agent's output file.

HUD Bubble (Foreground): An expandable, draggable ZStack overlay floating on top of the editor.

Aesthetics: Frosted glass (.regularMaterial), rounded corners.

Top Row (Static): Mic toggle, Agent State indicator (Initializing, Listening, Processing), Copy buttons, Expand toggle.

Controlls: pause, start or stop.

Bottom Row (Expandable): Animated dropdown showing the live stt.txt raw feed.

## Technical Specification: macOS App (Orchestrator)

Language & UI: Swift 5.9+, SwiftUI.

Permissions: Non-sandboxed. Requires Microphone and Accessibility (System Events) entitlements.

Audio & ML: AVAudioEngine for non-blocking PCM buffer capture. whisper.cpp linked natively via C++ interop, utilizing Metal/CoreML for Apple Silicon acceleration.

Tmux IPC: Foundation Process API to execute tmux new-session and tmux send-keys. Must inherit standard $PATH in .environment dictionary.

## Concurrency & State:

Queue Actor: Thread-safe Swift Actor handling continuous STT appends.

Worker Task: Asynchronously pulls chunks from the Actor, monitors agent busy-state, and sends keys.

File Watching: DispatchSourceFileSystemObject to establish high-performance, native file-system hooks for UI updates and agent state changes.

## Technical Specification: TUI Agent (Backend)

Environment: Runs entirely within a detached tmux session (vtmd_agent) managed by the Swift app.

Mode: TUI/CLI mode (not standard REST API).

Input Handling: Must accept text chunks routed through standard input via tmux send-keys.

Output Handling: Must continuously write/append structured Markdown responses to the designated session directory.

Hook Triggering: Must touch/update a specific "ready" file upon completing initialization and upon finishing the processing of a chunk, signaling the Swift app to release the next chunk.

## File System & IPC Contract (~/.vtmd/)

The file system acts as the message bus between the Swift Orchestrator and the CLI Agent.

~/.vtmd/models/: Storage for whisper.cpp .bin files.

~/.vtmd/.claude/commands/vtmd.md & ./agents/.commands/vtmd.md: Hardcoded initialization prompts injected at session start.

~/.vtmd/memo/[timestamp]/: Ephemeral session directory.

stt.txt: Continuous append log of raw Whisper output. Watched by the HUD Bubble.

structured.md: The agent's formatted output. Watched by the Main Canvas (and written to if the user manually edits the UI).

agent.ready: A 0-byte hook file. The agent touches this file when ready for a new chunk. The Swift app watches this file to trigger the Queue Actor.

## Distribution & Packaging

App Store: Ineligible due to disabled App Sandbox and Accessibility requirements.

Format: Notarized macOS Disk Image (.dmg) built and signed via Apple Developer ID certificate.

Updates: Integrated Sparkle 2 framework for automatic, in-app OTA updates via GitHub Releases XML appcast.

Channels: Hosted on GitHub Releases; distributed via Homebrew Cask (brew install --cask vtmd).