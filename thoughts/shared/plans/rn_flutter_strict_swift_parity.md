# Strict Swift Parity For RN + Flutter Examples

## Summary

- Goal: make React Native and Flutter examples follow the iOS example as source of truth, deleting app-local legacy paths instead of preserving compatibility.
- No mock implementations and no unit tests. Verification uses existing typecheck/analyze/smoke/build gates only.
- Keep Android-only Genie backend registration as a platform-specific exception.

## Implementation Checklist

- [ ] Use Swift's primary app shape in both examples: Chat, Vision, Voice, More, Settings.
- [ ] Move STT, TTS/Speak, RAG, VAD, Storage, and Solutions into a More stack/hub.
- [ ] Delete RN Validation tab/screen and validation-only LoRA fixture UI.
- [ ] Delete Flutter Tools tab and Structured Output entry/surface from example UI.
- [ ] Register backends before SDK initialization where each platform allows it.
- [ ] Initialize SDK once, complete services once, register catalogs after services, then refresh the model registry.
- [ ] Factor large inline catalogs into app-local ModelCatalogBootstrap modules mirroring iOS naming and flow.
- [ ] Align Qwen 0.5B URL with iOS, set supportsLora, and seed the iOS LoRA adapter catalog entry via SDK LoRA APIs.
- [ ] Delete fabricated system-tts model entries from RN and Flutter example registries.
- [ ] Route chat through generateWithTools when tool calling is enabled and tools are registered.
- [ ] Wire thinking mode, thinkingContent, disableThinking, and analytics wasThinkingMode.
- [ ] Fix lower request builders so canonical LLMGenerationOptions/disableThinking reaches LLMGenerateRequest.
- [ ] Fix RN error handling to update the existing assistant placeholder.
- [ ] Wire stop/cancel for streaming and tool generation.
- [ ] Remove app-side preferredFramework generation hints and default-framework fallbacks.
- [ ] Ensure RN voice stop/unmount/error paths call cleanupVoiceAgent().
- [ ] Replace RN 3-second batch live STT loop with RunAnywhere.transcribeStream over microphone PCM chunks.
- [ ] Add real VAD demo screens in both apps using SDK streamVAD/detectVoiceActivity.
- [ ] Align voice event handling with iOS for wakeword, VAD stopped, session stopped/error, and recoverable errors.
- [ ] Move storage management out of Settings into a Storage screen.
- [ ] Align settings defaults and keys with iOS names; no legacy key aliases or migrations.
- [ ] Make tool toggle auto-register demo tools when enabled and clear them when disabled.
- [ ] Delete app-side system TTS fabrication, VLM hardcoded generation defaults, redundant loaded flags, and EOS stripping.
- [ ] Remove stale comments/docs that claim Swift parity after the surface changes.

## Verification

- React Native example: `yarn typecheck`, then `./scripts/smoke.sh`.
- React Native SDK if touched: `cd sdk/runanywhere-react-native && yarn typecheck`.
- Flutter example: `flutter analyze`, then `./scripts/verify.sh`.
- Flutter SDK if touched: `cd sdk/runanywhere-flutter && melos run analyze`.
- Heavy builds remain sequential; native/Gradle builds use `-j 2` or `--max-workers=2`.

## Change Log

- 2026-06-10: Plan written from approved strict Swift parity proposal. Implementation starting with RN/Flutter example cleanup and shared LLM request-builder fixes.
