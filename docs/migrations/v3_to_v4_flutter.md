# Flutter SDK v3.x → v4.0 Migration Guide

_v4.0.0 is a BREAKING API change to the Flutter SDK (`runanywhere`
package only). The 2,621 LOC `runanywhere.dart` god-class is **gone**.
In its place: a singleton + capability instance methods, matching the
canonical Dart pattern used by `supabase-dart`, `firebase_core`, etc._

> **The static `RunAnywhere` class is DELETED in v4.0.** There is no
> deprecation window, no forwarding shim, no `@Deprecated` stub. Every
> v3 call site must be rewritten as `RunAnywhereSDK.instance.<cap>.<method>()`
> before the package will build.

> **Affected packages**: ONLY `runanywhere` (Flutter). The other 6
> packages (Swift / Kotlin / RN / Web + 3 backend plugins) are
> unaffected and stay on v3.x. The backend plugins
> (`runanywhere_llamacpp`, `runanywhere_onnx`, `runanywhere_genie`)
> ship v4-compatible updates alongside the main package.

## 1:1 replacement table (48 symbols)

Exactly one instance call replaces every old static call. No new
capabilities, no reshaped semantics — just the new call site.

### Lifecycle (7)

| v3.x (static) | v4.0 (instance) |
|--------------------------------------------------------|---------------------------------------------------|
| `await RunAnywhere.initialize(...)`                    | `await RunAnywhereSDK.instance.initialize(...)`      |
| `RunAnywhere.isSDKInitialized`                         | `RunAnywhereSDK.instance.isInitialized`              |
| `RunAnywhere.isActive`                                 | `RunAnywhereSDK.instance.isActive`                   |
| `RunAnywhere.environment` / `getCurrentEnvironment()`  | `RunAnywhereSDK.instance.environment`                |
| `RunAnywhere.version`                                  | `RunAnywhereSDK.instance.version`                    |
| `RunAnywhere.events`                                   | `RunAnywhereSDK.instance.events`                     |
| `await RunAnywhere.reset()`                            | `await RunAnywhereSDK.instance.reset()`              |

### LLM (9)

| v3.x | v4.0 |
|---|---|
| `await RunAnywhere.loadModel(id)`                 | `await RunAnywhereSDK.instance.llm.load(id)`             |
| `await RunAnywhere.unloadModel()`                 | `await RunAnywhereSDK.instance.llm.unload()`             |
| `RunAnywhere.isModelLoaded`                       | `RunAnywhereSDK.instance.llm.isLoaded`                   |
| `RunAnywhere.currentModelId`                      | `RunAnywhereSDK.instance.llm.currentModelId`             |
| `await RunAnywhere.currentLLMModel()`             | `await RunAnywhereSDK.instance.llm.currentModel()`       |
| `await RunAnywhere.chat(prompt)`                  | `await RunAnywhereSDK.instance.llm.chat(prompt)`         |
| `await RunAnywhere.generate(prompt, options)`     | `await RunAnywhereSDK.instance.llm.generate(prompt, options)` |
| `await RunAnywhere.generateStream(prompt, ...)`   | `await RunAnywhereSDK.instance.llm.generateStream(prompt, ...)` |
| `await RunAnywhere.cancelGeneration()`            | `await RunAnywhereSDK.instance.llm.cancel()`             |

### STT (7)

| v3.x | v4.0 |
|---|---|
| `await RunAnywhere.loadSTTModel(id)`          | `await RunAnywhereSDK.instance.stt.load(id)`         |
| `await RunAnywhere.unloadSTTModel()`          | `await RunAnywhereSDK.instance.stt.unload()`         |
| `RunAnywhere.isSTTModelLoaded`                | `RunAnywhereSDK.instance.stt.isLoaded`               |
| `RunAnywhere.currentSTTModelId`               | `RunAnywhereSDK.instance.stt.currentModelId`         |
| `await RunAnywhere.currentSTTModel()`         | `await RunAnywhereSDK.instance.stt.currentModel()`   |
| `await RunAnywhere.transcribe(audio)`         | `await RunAnywhereSDK.instance.stt.transcribe(audio)` |
| `await RunAnywhere.transcribeWithResult(...)` | `await RunAnywhereSDK.instance.stt.transcribeWithResult(...)` |

### TTS (6)

| v3.x | v4.0 |
|---|---|
| `await RunAnywhere.loadTTSVoice(id)`       | `await RunAnywhereSDK.instance.tts.loadVoice(id)`    |
| `await RunAnywhere.unloadTTSVoice()`       | `await RunAnywhereSDK.instance.tts.unloadVoice()`    |
| `RunAnywhere.isTTSVoiceLoaded`             | `RunAnywhereSDK.instance.tts.isLoaded`               |
| `RunAnywhere.currentTTSVoiceId`            | `RunAnywhereSDK.instance.tts.currentVoiceId`         |
| `await RunAnywhere.currentTTSVoice()`      | `await RunAnywhereSDK.instance.tts.currentVoice()`   |
| `await RunAnywhere.synthesize(text, ...)`  | `await RunAnywhereSDK.instance.tts.synthesize(text, ...)` |

### VLM (10)

| v3.x | v4.0 |
|---|---|
| `await RunAnywhere.loadVLMModel(id)`              | `await RunAnywhereSDK.instance.vlm.load(id)`             |
| `await RunAnywhere.loadVLMModelById(id)`          | `await RunAnywhereSDK.instance.vlm.loadById(id)`         |
| `await RunAnywhere.loadVLMModelWithPath(...)`     | `await RunAnywhereSDK.instance.vlm.loadWithPath(...)`    |
| `await RunAnywhere.unloadVLMModel()`              | `await RunAnywhereSDK.instance.vlm.unload()`             |
| `RunAnywhere.isVLMModelLoaded`                    | `RunAnywhereSDK.instance.vlm.isLoaded`                   |
| `RunAnywhere.currentVLMModelId`                   | `RunAnywhereSDK.instance.vlm.currentModelId`             |
| `await RunAnywhere.processImage(image, ...)`      | `await RunAnywhereSDK.instance.vlm.processImage(image, ...)` |
| `await RunAnywhere.processImageStream(image, ..)` | `await RunAnywhereSDK.instance.vlm.processImageStream(image, ...)` |
| `await RunAnywhere.describeImage(image, ...)`     | `await RunAnywhereSDK.instance.vlm.describe(image, ...)` |
| `await RunAnywhere.askAboutImage(q, ...)`         | `await RunAnywhereSDK.instance.vlm.askAbout(q, ...)`     |
| `await RunAnywhere.cancelVLMGeneration()`         | `await RunAnywhereSDK.instance.vlm.cancel()`             |

### Voice Agent (4)

| v3.x | v4.0 |
|---|---|
| `RunAnywhere.isVoiceAgentReady`                            | `RunAnywhereSDK.instance.voice.isReady`                          |
| `RunAnywhere.getVoiceAgentComponentStates()`               | `RunAnywhereSDK.instance.voice.componentStates()`                |
| `await RunAnywhere.initializeVoiceAgentWithLoadedModels()` | `await RunAnywhereSDK.instance.voice.initializeWithLoadedModels()` |
| `RunAnywhere.cleanupVoiceAgent()`                          | `RunAnywhereSDK.instance.voice.cleanup()`                        |

`VoiceAgentStreamAdapter` is unchanged.

### Models (6)

| v3.x | v4.0 |
|---|---|
| `await RunAnywhere.availableModels()`             | `await RunAnywhereSDK.instance.models.available()`       |
| `await RunAnywhere.refreshDiscoveredModels()`     | `await RunAnywhereSDK.instance.models.refresh()`         |
| `RunAnywhere.registerModel(...)`                  | `RunAnywhereSDK.instance.models.register(...)`           |
| `RunAnywhere.registerMultiFileModel(...)`         | `RunAnywhereSDK.instance.models.registerMultiFile(...)`  |
| `await RunAnywhere.updateModelDownloadStatus(id, path)` | `await RunAnywhereSDK.instance.models.updateDownloadStatus(id, path)` |
| `await RunAnywhere.removeModel(id)`               | `await RunAnywhereSDK.instance.models.remove(id)`        |

### Downloads (4)

| v3.x | v4.0 |
|---|---|
| `RunAnywhere.downloadModel(id)`                       | `RunAnywhereSDK.instance.downloads.start(id)`                |
| `await RunAnywhere.deleteStoredModel(id)`             | `await RunAnywhereSDK.instance.downloads.delete(id)`         |
| `await RunAnywhere.getStorageInfo()`                  | `await RunAnywhereSDK.instance.downloads.getStorageInfo()`   |
| `await RunAnywhere.getDownloadedModelsWithInfo()`     | `await RunAnywhereSDK.instance.downloads.list()`             |

### Tools (LLM function calling) — 7

The old `RunAnywhereTools` convenience class and `RunAnywhereToolCalling`
extension are deleted. Use `RunAnywhereSDK.instance.tools` instead.

| v3.x | v4.0 |
|---|---|
| `RunAnywhereTools.registerTool(def, exec)`            | `RunAnywhereSDK.instance.tools.register(def, exec)`      |
| `RunAnywhereTools.unregisterTool(name)`               | `RunAnywhereSDK.instance.tools.unregister(name)`         |
| `RunAnywhereTools.getRegisteredTools()`               | `RunAnywhereSDK.instance.tools.registeredTools()`        |
| `RunAnywhereTools.clearTools()`                       | `RunAnywhereSDK.instance.tools.clear()`                  |
| `RunAnywhereTools.executeTool(call)`                  | `RunAnywhereSDK.instance.tools.execute(call)`            |
| `await RunAnywhereTools.generateWithTools(p, options)` | `await RunAnywhereSDK.instance.tools.generateWithTools(p, options)` |
| `await RunAnywhereTools.continueWithToolResult(...)`  | `await RunAnywhereSDK.instance.tools.continueWithToolResult(...)` |

### RAG (Retrieval-Augmented Generation) — 6

The old `RunAnywhereRAG` extension and its `rag*` prefix are deleted.
Use `RunAnywhereSDK.instance.rag` instead — note the drop of the
`rag`-prefix on method names.

| v3.x | v4.0 |
|---|---|
| `await RunAnywhereRAG.ragCreatePipeline(cfg)`     | `await RunAnywhereSDK.instance.rag.createPipeline(cfg)`      |
| `await RunAnywhereRAG.ragDestroyPipeline()`       | `await RunAnywhereSDK.instance.rag.destroyPipeline()`        |
| `await RunAnywhereRAG.ragIngest(text)`            | `await RunAnywhereSDK.instance.rag.ingest(text)`             |
| `await RunAnywhereRAG.ragAddDocumentsBatch(docs)` | `await RunAnywhereSDK.instance.rag.addDocumentsBatch(docs)`  |
| `await RunAnywhereRAG.ragQuery(q, options)`       | `await RunAnywhereSDK.instance.rag.query(q, options)`        |
| `await RunAnywhereRAG.ragDocumentCount()`         | `await RunAnywhereSDK.instance.rag.documentCount()`          |
| `await RunAnywhereRAG.ragGetStatistics()`         | `await RunAnywhereSDK.instance.rag.getStatistics()`          |

### Unaffected helpers

These classes kept their `static`-method shape (they were never
on the god-class, just used `extension on RunAnywhere` as a
namespace trick). v4.0 makes them plain classes — call sites
unchanged:

- `RunAnywhereDevice.getChip()`
- `RunAnywhereFrameworks.getRegisteredFrameworks()`, `getFrameworks(cap)`, `isFrameworkAvailable`, `modelsForFramework`, `downloadedModelsForFramework`
- `RunAnywhereLogging.configureLogging(cfg)`, `setLogLevel(lvl)`, `setDebugMode(bool)`, `flushLogs()`
- `RunAnywhereLoRA.loadLoraAdapter(cfg)`, `removeLoraAdapter(path)`, `clearLoraAdapters()`, `getLoadedLoraAdapters()`, `checkLoraCompatibility(path)`, `registerLoraAdapter(entry)`, `loraAdaptersForModel(id)`, `allRegisteredLoraAdapters()`
- `RunAnywhereStorage.checkStorageAvailable`, `getStorageValue(k)`, `setStorageValue(k, v)`, `deleteStorageValue(k)`, `storageKeyExists(k)`, `clearStorage()`, `getBaseDirectoryPath()`, `downloadModel(id)`
- `RAGModule.register()`, `unregister()`, `isRegistered`

## Migration recipe

### Step 1 — Update the dependency

```yaml
dependencies:
  runanywhere: ^4.0.0
  runanywhere_llamacpp: ^4.0.0  # if used
  runanywhere_onnx: ^4.0.0      # if used
  runanywhere_genie: ^4.0.0     # if used
```

### Step 2 — Run analyzer, fix every `undefined_identifier: RunAnywhere`

Since the static class is deleted, `flutter analyze` reports every
v3 call site as an error. Walk the list from top to bottom, applying
the 1:1 mapping in the table above.

### Step 3 — Drop old imports

```dart
// DELETE these imports:
import 'package:runanywhere/public/runanywhere.dart';
import 'package:runanywhere/public/runanywhere_tool_calling.dart';
import 'package:runanywhere/public/extensions/runanywhere_rag.dart';

// These are still exported from the umbrella barrel:
import 'package:runanywhere/runanywhere.dart';
// ...and give you RunAnywhereSDK + every capability class.
```

### Step 4 — Update sample apps

The official `examples/flutter/RunAnywhereAI/` sample is migrated
as part of v4.0 — use it as the reference for your own migration.

## Why this is the right shape

Moving every implementation off the god-class and onto the
capabilities enables:

- **Lazy capability initialization**: each capability getter only
  spins up when first accessed.
- **Per-capability mocking** for tests — each capability is an
  independent singleton class.
- **Cleaner namespacing**: ~80 static methods collapse to 9 grouped
  instance APIs.
- **File-scope splitting**: each capability lives in
  `lib/public/capabilities/runanywhere_<cap>.dart`. The 2,621 LOC
  god-class is replaced by ~210 LOC of `runanywhere_v4.dart` (pure
  lifecycle) plus ~200 LOC of internal state helpers plus the
  capability classes.
- **Discoverability**: IDE autocomplete on `instance.` shows exactly
  which capabilities exist, instead of 80+ methods on one class.

## Frequently asked

**Q: Is there a deprecation window?**
A: No. The static `RunAnywhere` class is deleted in v4.0 — there is
no `@Deprecated` stub, no one-minor-version grace period, no
forwarder. Every call site must migrate before you can build against
v4.0.

**Q: Are there other breaking changes besides the API shape?**
A: No. The semantics of every method are unchanged — only the call
site changes from `RunAnywhere.X` to `RunAnywhereSDK.instance.<cap>.X`.

**Q: What about the proto types (VoiceEvent, etc.)?**
A: Unchanged. Generated from `idl/voice_events.proto`; consumers
import them the same way as v3.x.

**Q: What about the C ABI (`RAC_PLUGIN_API_VERSION`)?**
A: Unchanged. v4.0 is a Flutter SDK API-shape change only; the
underlying native commons stays on the v3 ABI.

**Q: The backend plugins (llamacpp / onnx / genie) — do they change?**
A: Only internally. `LlamaCpp.addModel(...)` now calls
`RunAnywhereSDK.instance.models.register(...)` under the hood instead
of `RunAnywhere.registerModel(...)`; the public API of each plugin is
unchanged for callers.
