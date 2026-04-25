# API Parity Matrix

Generated during T5 native bridge/API parity work on 2026-04-24.

| Surface | Swift | Kotlin | Flutter | React Native | Web |
| --- | --- | --- | --- | --- | --- |
| `refreshModelRegistry(includeRemoteCatalog,rescanLocal,pruneOrphans)` | `RunAnywhere.refreshModelRegistry(includeRemoteCatalog:rescanLocal:pruneOrphans:)` | `RunAnywhere.refreshModelRegistry(includeRemoteCatalog,rescanLocal,pruneOrphans)` | `RunAnywhereSDK.instance.models.refresh(includeRemoteCatalog,rescanLocal,pruneOrphans)` | `RunAnywhere.refreshModelRegistry({ includeRemoteCatalog, rescanLocal, pruneOrphans })` | `RunAnywhere.refreshModelRegistry({ includeRemoteCatalog, rescanLocal, pruneOrphans })` |
| `deleteAllModels` | `RunAnywhere.deleteAllModels()` | `RunAnywhere.deleteAllModels()` | `RunAnywhereSDK.instance.downloads.deleteAllModels()` | `RunAnywhere.deleteAllModels()` | `RunAnywhere.deleteAllModels()` |
| `cancelDownload(modelId)` | `RunAnywhere.cancelDownload(_:)` | `RunAnywhere.cancelDownload(modelId)` | `RunAnywhereSDK.instance.downloads.cancelDownload(modelId)` | `RunAnywhere.cancelDownload(modelId)` | `RunAnywhere.cancelDownload(modelId)` |
| `generateStream` | `RunAnywhere.generateStream(_:options:) -> AsyncStream<RALLMStreamEvent>` | `RunAnywhere.generateStream(prompt, config) -> Flow<LLMStreamEvent>` | `RunAnywhereSDK.instance.llm.generateStream(prompt, options) -> Stream<LLMStreamEvent>` | `RunAnywhere.generateStream(prompt, options) -> LLMStreamingResult` backed by `LLMStreamAdapter` | backend text capability `generateStream(prompt, opts)` backed by `LLMStreamAdapter` |
| `voice.eventStream` | `VoiceAgentStreamAdapter(handle:).stream()` | `VoiceAgentStreamAdapter(handle).stream()` | `RunAnywhereSDK.instance.voice.eventStream()` | `VoiceAgentStreamAdapter(handle).stream()` | `VoiceAgentStreamAdapter(handle).stream()` |
| `solutions.run(config|bytes|yaml)` | `RunAnywhere.solutions.run(config:)`, `run(configBytes:)`, `run(yaml:)` | `RunAnywhere.solutions.run(config)`, `run(configBytes)`, `runYaml(yaml)` | `RunAnywhereSDK.instance.solutions.run(config|configBytes|yaml)` | `RunAnywhere.solutions.run({ config | configBytes | yaml })` | `RunAnywhere.solutions.run({ config | configBytes | yaml })` |

## Notes

- Kotlin `refreshModelRegistry` now accepts the same three flags as the other SDKs and forwards them to `rac_model_registry_refresh`.
- Kotlin `deleteAllModels` deletes downloaded files and clears registry/storage download state instead of no-oping.
- Kotlin `cancelDownload(modelId)` now cancels the tracked active native download ID where available before clearing download state.
- Swift and Dart LLM/Voice stream adapters now match Kotlin/Web by installing one native callback per handle and fanning out decoded events to multiple collectors.
- React Native now autolinks both `LLM` and `VoiceAgent` Nitro HybridObjects and implements `RunAnywhereCore.getLLMHandle()`.
