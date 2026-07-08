<p align="center">
  <img src="demo/icon.png" alt="Voice-to-Markdown icon" width="128"/>
</p>

<h1 align="center">🎙️ Voice-to-Markdown</h1>

<p align="center"><b>Talk. Get clean markdown. 100% local.</b></p>

A macOS menu-bar app that turns your voice into structured markdown using [whisper.cpp](https://github.com/ggerganov/whisper.cpp) for speech-to-text and any local LLM for formatting. No cloud. No API keys. Nothing leaves your Mac.

<img src="demo/agent-mode.jpg" alt="Agent Mode: spoken words become a structured spec, live" width="100%"/>

*↑ This entire product spec was dictated by voice — a local LLM structured it in real time.*

## ✨ Two modes

- **⌨️ Global Dictation — `⌘⌥]` anywhere.** Speak, and the transcript is typed straight into whatever field has focus. Terminal, browser, Slack — anything. A Spotlight-style pill shows what's happening:

  <img src="demo/input-into-focus-view.jpg" alt="Global dictation typing into a focused editor" width="520"/>

- **📝 Agent Mode — live markdown editor.** Speak freely; a local LLM streams your words into a clean, structured markdown document in real time. Raw transcript stays one click away. Start it from the menu bar:

  <img src="demo/status-bar.jpg" alt="Menu bar" width="420"/>

## 🚀 Quick Start

```bash
brew install xcodegen whisper-cpp ffmpeg   # dependencies
git clone https://github.com/xajik/voice-to-md.git && cd voice-to-md
make setup && make run
```

First launch: grant **Microphone** + **Accessibility** access, then download a Whisper model from **Settings…** in the menu bar (Base is a great start).

## 🧠 Local LLM Setup (Agent Mode)

Agent Mode talks to any **OpenAI-compatible** server. Point VTMD at it in **Settings…** (default: `http://127.0.0.1:8000/v1`, model auto-picked). The Whisper STT model is picked there too:

<img src="demo/settings.jpg" alt="Settings: local LLM endpoint, model picker, Whisper model" width="520"/>

Pick your server:

### omlx (Apple Silicon, MLX — fastest on Mac)

Serve any MLX model on port 8000 — VTMD's default, zero config needed:

```bash
brew install omlx
omlx serve Qwen3.5-27B-Claude-4.6-Opus-Distilled-MLX-4bit
```

### Ollama

```bash
brew install ollama
ollama pull qwen3.5        # or: ollama pull gemma3
ollama serve
```

Base URL: `http://127.0.0.1:11434/v1`

### LM Studio

Download from [lmstudio.ai](https://lmstudio.ai), grab a model, start the local server.
Base URL: `http://127.0.0.1:1234/v1`

### llama.cpp

```bash
brew install llama.cpp
llama-server -m your-model.gguf --port 8080
```

Base URL: `http://127.0.0.1:8080/v1`

### 🏆 Recommended models

| Model | Why |
|---|---|
| **Qwen3.5 27B** (4-bit) | Best formatting quality; the default pick |
| **Gemma 26B** (8-bit) | Fast, great instruction following |

Anything that follows instructions well works — VTMD streams tokens as they arrive, so even bigger models *feel* instant.

## 🛠️ Development

```bash
make check     # verify dependencies
make build     # release build
make test      # unit tests
make generate  # regen .xcodeproj after editing project.yml
```

Everything runs on-device: AVAudioEngine → whisper.cpp → local LLM → your screen. That's the whole pipeline.
