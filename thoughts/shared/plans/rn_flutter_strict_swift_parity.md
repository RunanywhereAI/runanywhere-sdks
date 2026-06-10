# Strict Swift Parity For RN + Flutter Examples

## Summary

- Goal: make React Native and Flutter examples follow the iOS example as source of truth, deleting app-local legacy paths instead of preserving compatibility.
- No mock implementations and no unit tests. Verification uses existing typecheck/analyze/smoke/build gates only.
- Keep Android-only Genie backend registration as a platform-specific exception.

## Implementation Checklist

- [x] Use Swift's primary app shape in both examples: Chat, Vision, Voice, More, Settings.
- [x] Move STT, TTS/Speak, RAG, VAD, Storage, and Solutions into a More stack/hub.
- [x] Delete RN Validation tab/screen and validation-only LoRA fixture UI.
- [x] Delete Flutter Tools tab and Structured Output entry/surface from example UI.
- [x] Register backends before SDK initialization where each platform allows it.
- [x] Initialize SDK once, complete services once, register catalogs after services, then refresh the model registry.
- [ ] Factor large inline catalogs into app-local ModelCatalogBootstrap modules mirroring iOS naming and flow.
- [ ] Align Qwen 0.5B URL with iOS, set supportsLora, and seed the iOS LoRA adapter catalog entry via SDK LoRA APIs.
- [x] Delete fabricated system-tts model entries from RN and Flutter example registries.
- [x] Route chat through generateWithTools when tool calling is enabled and tools are registered.
- [x] Wire thinking mode, thinkingContent, disableThinking, and analytics wasThinkingMode.
- [x] Fix lower request builders so canonical LLMGenerationOptions/disableThinking reaches LLMGenerateRequest.
- [x] Fix RN error handling to update the existing assistant placeholder.
- [ ] Wire stop/cancel for streaming and tool generation.
- [x] Remove app-side preferredFramework generation hints and default-framework fallbacks.
- [x] Ensure RN voice stop/unmount/error paths call cleanupVoiceAgent().
- [x] Replace RN 3-second batch live STT loop with RunAnywhere.transcribeStream over microphone PCM chunks.
- [x] Add real VAD demo screens in both apps using SDK streamVAD/detectVoiceActivity.
- [ ] Align voice event handling with iOS for wakeword, VAD stopped, session stopped/error, and recoverable errors.
- [x] Move storage management out of Settings into a Storage screen.
- [x] Align settings defaults and keys with iOS names; no legacy key aliases or migrations.
- [x] Make tool toggle auto-register demo tools when enabled and clear them when disabled.
- [x] Delete app-side system TTS fabrication, VLM hardcoded generation defaults, redundant loaded flags, and EOS stripping.
- [x] Remove stale comments/docs that claim Swift parity after the surface changes.

## Verification

- React Native example: `yarn typecheck`, then `./scripts/smoke.sh`.
- React Native SDK if touched: `cd sdk/runanywhere-react-native && yarn typecheck`.
- Flutter example: `flutter analyze`, then `./scripts/verify.sh`.
- Flutter SDK if touched: `cd sdk/runanywhere-flutter && melos run analyze`.
- Heavy builds remain sequential; native/Gradle builds use `-j 2` or `--max-workers=2`.

## Change Log

- 2026-06-10: Plan written from approved strict Swift parity proposal. Implementation starting with RN/Flutter example cleanup and shared LLM request-builder fixes.
- 2026-06-10: Pushed pre-existing SDK-layer/audio parity work as `1e115b011 feat(sdk): move audio and parity helpers into SDK`.
- 2026-06-10: RN example aligned to iOS 5-tab shell with More stack; deleted Validation Harness and LoRA fixture; added VAD and Storage screens; moved backend registration before `initialize`; refreshed model registry after catalog registration; aligned Qwen 0.5B URL/supportsLora; routed Chat through `generateWithTools`; wired thinking mode, cancel, placeholder error updates, RN STT live streaming through `transcribeStream`, voice-agent cleanup, and VLM layering cleanup. RN README updated for the deleted legacy surface.
- 2026-06-10: RN SDK LLM request builder now carries canonical `LLMGenerationOptions`, including `disableThinking`, into `LLMGenerateRequest`.
- 2026-06-10: Flutter example aligned to iOS 5-tab shell with More hub; deleted Tools and Structured Output screens; added VAD and Storage screens; moved Storage out of Settings; added init gate/retry; moved backend registration before `initialize`; removed duplicate services completion; refreshed model registry after catalog registration; aligned Qwen 0.5B URL/supportsLora; registered STT/TTS archive models with archive structure metadata; removed app-side `system-tts` registration/shortcut; wired thinking settings through Chat and RAG; aligned preference/keychain keys and tool toggle side effects.
- 2026-06-10: Flutter SDK storage extension gained typed `deleteStorage(StorageDeleteRequest)` plus flat `RunAnywhere.deleteStorage`/`cleanTempFiles` forwarding so the example can use Swift-style storage request flags without native bridge access.
- 2026-06-10: Verification passed: RN example `yarn typecheck`, RN SDK `yarn typecheck`, RN example `./scripts/smoke.sh`, Flutter example `flutter analyze`, Flutter SDK package `dart analyze`. Full Flutter/RN native builds were not run because the machine has about 1 GiB free disk.
