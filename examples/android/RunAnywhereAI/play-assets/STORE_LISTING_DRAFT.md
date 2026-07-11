# Google Play listing draft

## App identity

- App name: `RunAnywhere`
- Default language: `English (United States)`
- Category: `Productivity`
- Support email candidate: `founders@runanywhere.ai` (confirm before submission)
- Website: confirm the production HTTPS URL before submission
- Privacy policy: blocked until the final policy is published at a stable HTTPS URL

## Short description

Run chat, vision, voice, and document models directly on your Android device.

Character count: 77 of 80.

## Full description

RunAnywhere lets you run capable models directly on supported Android devices.

Chat with downloaded language models, analyze photos and live camera input, ask questions across documents with cited source chunks, and use speech-to-text and text-to-speech from one app.

Features include:

• Local chat with device-aware model recommendations
• Image and chart understanding
• Live camera analysis
• Document question answering with cited sources
• Hands-free voice conversations
• Speech transcription and voice generation
• Built-in tools for tasks such as calculations
• Optional web search with visible tool traces and source URLs
• Qualcomm Hexagon NPU acceleration on supported devices
• Model download and storage controls

Core inference runs on your device after the required model files are downloaded. Network access is required for model downloads. Optional connected features can use network services when enabled. Feature availability and performance depend on the selected model and device hardware.

## Release notes

Initial Android release with on-device chat, vision, voice, document search, tools, web search, and device-aware NPU model selection.

## Screenshot order and accessibility copy

1. `01-home.png` — RunAnywhere home screen with Qwen3.5 0.8B loaded and NPU ready for local prompts.
2. `06-qhexrt-v81.png` — Real Qwen3.5 `QHEXRT_OK` generation on a Hexagon v81 NPU with visible latency and throughput metrics.
3. `02-documents-rag.png` — Documents screen answering a Project Aurora question with one cited source.
4. `07-web-search.png` — Qwen invoking `search_web` and citing the official Qualcomm AI Hub URL while Web & tools is enabled.
5. `03-tools-calculate.png` — Local Qwen model using the calculator tool to answer 45 multiplied by 12.
6. `04-vision-chart.png` — InternVL reading exact quarterly values and trend from a bar chart on-device.
7. `05-talk-ready.png` — Talk Mode with speech, language, voice, and turn-taking models ready.

## Submission notes

- Do not claim that every feature is offline: model downloads and optional connected features use the network.
- Do not submit until the privacy policy, Data Safety form, AI-content reporting requirement, model redistribution review, production search proxy, and Play Console declarations are resolved.
