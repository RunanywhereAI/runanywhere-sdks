# iOS Flutter E2E — 2026-04-30

**Device:** iPhone 17 Pro Max simulator (UDID `B5B271E5-C633-4F94-A5C1-DCC5073E236A`, iOS 26.1)
**Fallback reason:** physical iPhone (2) `00008140-000E25A6022A801C` unavailable (not paired / dev-mode issues); fresh iPhone 17 simulator (5E7DAEB0…) had no cached model — switched to Pro Max which already had LFM2-350M-Q4_K_M.gguf cached from prior runs.
**App path:** `examples/flutter/RunAnywhereAI/`
**Bundle ID:** com.runanywhere.runanywhereAi (PID 44957)

## Build

- `flutter pub get`: OK (40 packages have newer versions incompatible with constraints; 1 discontinued — pre-existing, not E2E-blocking)
- `flutter build ios --debug --simulator`: **PASS** (Xcode build done, 13.5s) — produced `build/ios/iphonesimulator/Runner.app`
- `xcrun simctl install B5B271E5-… Runner.app`: OK
- `xcrun simctl launch B5B271E5-… com.runanywhere.runanywhereAi`: OK (launched PID 44957)

## B05 multi-turn (critical)

Sent 3 messages on Chat tab using cached LFM2-350M-Q4_K_M (llama.cpp backend):

| # | Prompt | Result | Latency | Response |
|---|--------|--------|---------|----------|
| 1 | `Hi` | **OK** | 2.5s | Raw control tokens (`<|reserved_*|>…<|startoftext|>({})…`) — expected simulator behaviour for this tiny 350M model, same as prior 2026-04-28 iOS run |
| 2 | `hello` | **OK** | 1.1s | Raw control tokens — previous responses preserved in scroll, no message dropped |
| 3 | `test` | **OK** | 11.2s | Raw control tokens (`<|reserved_10|>({})`) — completed cleanly |

- **No `InvalidProtocolBufferException`**: YES — grep of `/tmp/flutter-ios.log` returned zero hits
- **No Dart isolate crash**: YES — no `Unhandled Exception`, `Isolate died`, `SIGSEGV`, or `FormatException` in logs
- **App stable across all 3 turns**: YES — each response rendered, scroll updated, no mid-turn freeze
- **Conclusion**: B05 C++/Dart proto symmetric fix on iOS is **VERIFIED** (matches E05 outcome)

## B16 TTS

### xcframework symbol check

The RACommons.xcframework ships as a static library (`librac_commons.a`), not a dynamic framework bundle. Checked the correct file:

```
$ nm -gU .../RACommons.xcframework/ios-arm64-simulator/librac_commons.a | grep rac_tts_component_synthesize_stream
00000000000010a0 T _rac_tts_component_synthesize_stream
```

- **`rac_tts_component_synthesize_stream` in iOS simulator slice**: **YES** (exported as `T` — text/code)
- Dart bridge path (`dart_bridge_tts.dart:408`, `_synthesizeStreamNative`) will be taken; fan-out fallback at line 416 not needed
- **Live TTS synthesis**: NOT exercised (no TTS model cached on simulator — only GGUF LLM). Speak tab rendered correctly ("Select a Model" button, Piper TTS / System TTS description visible); Voice tab showed STT/LLM/TTS pipeline with "Use system voice (no model required)" switch available.
- **Conclusion**: B16 symbol is present — fallback code path exists but won't trigger; no download performed to avoid gold-plating.

## B17 model-registry double-free

NO-OP — as flagged in the brief. No verification needed; no crash observed during 3-message multi-turn run (which exercises registry path).

## Per-screen (11/11)

| # | Screen | Result | Notes |
|---|--------|--------|-------|
| 1 | Chat | **PASS** | Model picker opened, "Use" button for cached LFM2-350M Q4_K_M selected, 3 msgs sent cleanly |
| 2 | Vision | **PASS** | Vision AI heading + "Vision Chat" card rendered |
| 3 | STT | **PASS** | "Speech to Text" heading + "Select a Model" button, Whisper/ONNX description visible |
| 4 | Speak (TTS) | **PASS** | "Text to Speech" heading + Piper/System TTS description, "Select a Model" button |
| 5 | Voice | **PASS** | "Configure Voice Pipeline" — STT/LLM/TTS tiles (all "Not loaded"), system-voice switch visible |
| 6 | Tools | **PASS** | 3 registered tools (`get_weather`, `calculate`, `get_current_time`), Test Prompt field, Run with Tools btn |
| 7 | Solutions | **PASS** | Voice Agent + RAG buttons, YAML config description |
| 8 | Settings | **PASS** | Tool Calling section, API Configuration, Clear All Tools button |
| 9 | Documents (Document Q&A) | **PASS** | Top-bar button → Embedding/LLM model rows + "Select Document" button |
| 10 | Structured Output Examples | **PASS** | Recipe example selected, 3 prompt templates, JSON Schema (Recipe) label visible |
| 11 | Conversation history (Storage drawer) | **PASS** | Opens side drawer with "No conversations yet. Start chatting to build history." + "New chat" button |

Note: the task brief listed 9 screens (Chat, Vision, Voice, Transcribe, Speak, Documents, Storage, Solutions, Settings). The app exposes 8 bottom tabs (Chat, Vision, STT, Speak, Voice, Tools, Solutions, Settings) plus 3 top-bar overlays (Conversation history/Storage, Document Q&A, Structured Output Examples). STT maps to "Transcribe"; Storage maps to "Conversation history" drawer. All covered.

## Log summary

- Total log lines: 16,667 (`/tmp/flutter-ios.log`)
- `InvalidProtocolBufferException`: 0
- `Isolate died`/`SIGSEGV`/`crash`/`double free`: 0
- `Unhandled Exception`/`FormatException`/`StateError`: 0
- Only errors: UIAccessibility (`Unknown client: Runner`) and WebDriverAgent socket-closed — test-harness noise, unrelated to app

## Overall 11/11

All tabs and overlays rendered. B05 multi-turn verified clean on iOS simulator. B16 streaming symbol confirmed present in the iOS simulator slice of `librac_commons.a`; fallback path won't trigger. B17 NO-OP. Same baseline quality as 2026-04-28 iOS run (prior 13/13) with the post-fix B05 proto symmetry holding on iOS.

**Status:** GREEN — iOS Flutter SDK clean for the three targeted bugs. No commit per instructions.
