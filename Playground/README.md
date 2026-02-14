# Playground

Interactive demo projects showcasing what you can build with RunAnywhere.

| Project | Description | Platform |
|---------|-------------|----------|
| [swift-starter-app](swift-starter-app/) | Privacy-first AI demo — LLM Chat, Speech-to-Text, Text-to-Speech, and Voice Pipeline with VAD | iOS (Swift/SwiftUI) |
| [on-device-browser-agent](on-device-browser-agent/) | On-device AI browser automation using WebLLM — no cloud, no API keys, fully private | Chrome Extension (TypeScript/React) |
| [android-use-agent](android-use-agent/) | Autonomous Android agent — navigates phone UI via accessibility + GPT-4o Vision + on-device LLM fallback | Android (Kotlin/Jetpack Compose) |
| [openclaw-hybrid-assistant](openclaw-hybrid-assistant/) | Hybrid voice assistant — on-device Wake Word, VAD, STT, and TTS with cloud LLM via OpenClaw WebSocket | Linux (C++/ALSA) |

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

An autonomous Android agent that navigates your phone's UI to accomplish tasks:

- **Autonomous UI Navigation** — Taps, types, swipes, and navigates apps to complete goals
- **GPT-4o Vision** — Screenshots sent to GPT-4o for visual screen understanding
- **Unified Tool Calling** — All UI actions registered as OpenAI function calling tools
- **On-Device Fallback** — Falls back to local LLM via RunAnywhere SDK when offline
- **Voice Mode** — Speak goals via on-device Whisper STT, hear progress via TTS

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

**Requirements:** Linux (ALSA), x86_64 or ARM64, CMake 3.16+, C++17
