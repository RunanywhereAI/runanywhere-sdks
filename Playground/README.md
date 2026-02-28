# Playground

Interactive demo projects showcasing what you can build with RunAnywhere.

| Project | Description | Platform |
|---------|-------------|----------|
| [YapRun](YapRun/) | On-device voice dictation — custom keyboard, multiple Whisper backends, Live Activity, offline-ready — [Website](https://runanywhere.ai/yaprun) · [TestFlight](https://testflight.apple.com/join/6N7nBeG8) | iOS & macOS (Swift/SwiftUI) |
| [swift-starter-app](swift-starter-app/) | Privacy-first AI demo — LLM Chat, Speech-to-Text, Text-to-Speech, and Voice Pipeline with VAD | iOS (Swift/SwiftUI) |
| [on-device-browser-agent](on-device-browser-agent/) | On-device AI browser automation using WebLLM — no cloud, no API keys, fully private | Chrome Extension (TypeScript/React) |
| [android-use-agent](android-use-agent/) | Fully on-device autonomous Android agent — navigates phone UI via accessibility + on-device LLM (Qwen3-4B). See [benchmarks](android-use-agent/ASSESSMENT.md) | Android (Kotlin/Jetpack Compose) |
| [linux-voice-assistant](linux-voice-assistant/) | Fully on-device voice assistant — Wake Word, VAD, STT, LLM, and TTS with zero cloud dependency | Linux (C++/ALSA) |
| [openclaw-hybrid-assistant](openclaw-hybrid-assistant/) | Hybrid voice assistant — on-device Wake Word, VAD, STT, and TTS with cloud LLM via OpenClaw WebSocket | Linux (C++/ALSA) |

## YapRun

On-device voice dictation for iOS and macOS. All speech recognition runs locally — your voice never leaves your device.

<p align="center">
  <img src="YapRun/screenshots/01_welcome.png" width="160" />
  <img src="YapRun/screenshots/03_home.png" width="160" />
  <img src="YapRun/screenshots/04_keyboard.png" width="160" />
  <img src="YapRun/screenshots/05_playground.png" width="160" />
  <img src="YapRun/screenshots/06_notepad.png" width="160" />
</p>

- **Custom Keyboard** — Tap "Yap" from any text field in any app to dictate
- **Multiple Whisper Backends** — WhisperKit (Neural Engine) and ONNX (CPU) with one-tap model switching
- **Live Activity** — Real-time transcription status on the Lock Screen and Dynamic Island
- **ASR Playground** — Record and transcribe in-app to test speed and accuracy
- **macOS Agent** — Menu bar icon, global hotkey dictation, floating flow bar
- **Offline-Ready** — Download once, run without a network connection

**[runanywhere.ai/yaprun](https://runanywhere.ai/yaprun)** | [TestFlight Beta](https://testflight.apple.com/join/6N7nBeG8) | Free on the App Store — iOS 16.0+ / macOS 14.0+, Xcode 15.0+

## linux-voice-assistant

A complete on-device voice AI pipeline for Linux (Raspberry Pi 5, x86_64, ARM64). All inference runs locally — no cloud, no API keys:

- **Wake Word Detection** — "Hey Jarvis" activation using openWakeWord (ONNX)
- **Voice Activity Detection** — Silero VAD with silence timeout
- **Speech-to-Text** — Whisper Tiny EN via Sherpa-ONNX
- **Large Language Model** — Qwen2.5 0.5B Q4 via llama.cpp (fully local)
- **Text-to-Speech** — Piper Lessac Medium neural TTS

**Requirements:** Linux (ALSA), x86_64 or ARM64, CMake 3.16+, C++20

## swift-starter-app

A full-featured iOS app demonstrating the RunAnywhere SDK's core capabilities:

- **LLM Chat** — On-device conversation with local language models
- **Speech-to-Text** — Whisper-powered transcription
- **Text-to-Speech** — Neural voice synthesis
- **Voice Pipeline** — Integrated STT → LLM → TTS with Voice Activity Detection

**Requirements:** iOS 17.0+, Xcode 15.0+

## on-device-browser-agent

A Chrome extension that automates browser tasks entirely on-device using WebLLM and WebGPU:

- **Two-agent architecture** — Planner + Navigator for intelligent task execution
- **DOM and Vision modes** — Text-based or screenshot-based page understanding
- **Site-specific handling** — Optimized workflows for Amazon, YouTube, and more
- **Fully offline** — All AI inference runs locally on GPU after initial model download

**Requirements:** Chrome 124+ (WebGPU support)

## android-use-agent

A fully on-device autonomous Android agent that navigates your phone's UI to accomplish tasks. All LLM inference runs locally via RunAnywhere SDK with llama.cpp -- no cloud dependency required.

- **Fully On-Device AI** — LLM inference via RunAnywhere SDK + llama.cpp (Qwen3-4B recommended)
- **Accessibility-Based Screen Parsing** — Reads UI tree via Android Accessibility API, no root required
- **Tool Calling** — LLM outputs structured tool calls (`<tool_call>` XML or `ui_tap(index=5)` function-call style)
- **Samsung Foreground Boost** — 15x inference speedup by bringing agent to foreground during inference
- **Smart Pre-Launch** — Opens target apps via Android intents before the agent loop
- **Optional Cloud Fallback** — GPT-4o with vision and function calling when an API key is configured
- **Voice Mode** — Speak goals via on-device Whisper STT, hear progress via TTS

See [android-use-agent/ASSESSMENT.md](android-use-agent/ASSESSMENT.md) for detailed model benchmarks across Qwen3-4B, LFM2.5-1.2B, LFM2-8B-A1B MoE, and DS-R1-Qwen3-8B on Samsung Galaxy S24.

**Requirements:** Android 8.0+ (API 26), arm64-v8a device, Accessibility service permission

## openclaw-hybrid-assistant

A hybrid voice assistant that combines on-device AI inference with cloud LLM reasoning via OpenClaw:

- **Wake Word Detection** — "Hey Jarvis" activation using openWakeWord (ONNX)
- **Voice Activity Detection** — Silero VAD with noise-robust debouncing and burst filtering
- **Speech-to-Text** — Parakeet TDT-CTC 110M (NeMo CTC) for fast on-device transcription
- **Text-to-Speech** — Piper neural TTS with streaming sentence-level pre-synthesis
- **OpenClaw Integration** — Raw WebSocket client sends transcriptions to cloud LLM, receives responses
- **Barge-in Support** — Wake word during TTS playback cancels speech and re-listens
- **Waiting Chime** — Earcon feedback while waiting for cloud response

**Requirements:** Linux (ALSA), x86_64 or ARM64, CMake 3.16+, C++20
