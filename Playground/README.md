# Playground

Interactive demo projects showcasing what you can build with RunAnywhere.

| Project | Description | Platform |
|---------|-------------|----------|
| [swift-starter-app](swift-starter-app/) | Privacy-first AI demo — LLM Chat, Speech-to-Text, Text-to-Speech, and Voice Pipeline with VAD | iOS (Swift/SwiftUI) |
| [on-device-browser-agent](on-device-browser-agent/) | On-device AI browser automation using WebLLM — no cloud, no API keys, fully private | Chrome Extension (TypeScript/React) |

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
