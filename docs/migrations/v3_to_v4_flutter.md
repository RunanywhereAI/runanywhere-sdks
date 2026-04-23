# Flutter SDK v3.x → v4.0 Migration Guide

_v4.0.0 introduces a BREAKING API change to the Flutter SDK
(`runanywhere` package only). The 2,607 LOC `runanywhere.dart`
god-class is split into a singleton + capability instance methods,
matching the canonical Dart pattern used by `supabase-dart`,
`firebase_core`, etc._

> **Affected packages**: ONLY `runanywhere` (Flutter). The other 6
> packages (Swift / Kotlin / RN / Web + 3 backend plugins) are
> unaffected and stay on v3.x.

## Why this change

Per the Phase 7 analysis ([HISTORY.md#flutter-split-analysis](../HISTORY.md#flutter-split-analysis)),
Dart language constraints prevent the Swift-style extension split
without breaking the API. Four options were evaluated:

1. `extension X on T { static method() }` — caller syntax becomes
   `X.method()` (breaks every consumer)
2. `part`/`part of` — Dart parser sees one class body per file
3. Top-level functions + thin facade — adds ~100 LOC of forwarding
   boilerplate, modest LOC reduction
4. **Instance methods on a singleton** — canonical Dart pattern;
   matches supabase-dart / firebase_core; THIS IS WHAT v4.0 SHIPS.

## API mapping table

### Lifecycle

| v3.x (static)                                          | v4.0 (instance)                                   |
|--------------------------------------------------------|---------------------------------------------------|
| `await RunAnywhere.initialize(...)`                    | `await RunAnywhere.instance.initialize(...)`      |
| `RunAnywhere.isSDKInitialized`                         | `RunAnywhere.instance.isInitialized`              |
| `RunAnywhere.environment`                              | `RunAnywhere.instance.environment`                |
| `RunAnywhere.version`                                  | `RunAnywhere.instance.version`                    |
| `RunAnywhere.events`                                   | `RunAnywhere.instance.events`                     |
| `await RunAnywhere.reset()`                            | `await RunAnywhere.instance.reset()`              |

### LLM (Text Generation)

| v3.x                                              | v4.0                                                  |
|---------------------------------------------------|-------------------------------------------------------|
| `await RunAnywhere.loadModel(id)`                 | `await RunAnywhere.instance.llm.load(id)`             |
| `await RunAnywhere.unloadModel()`                 | `await RunAnywhere.instance.llm.unload()`             |
| `RunAnywhere.isModelLoaded`                       | `RunAnywhere.instance.llm.isLoaded`                   |
| `await RunAnywhere.currentLLMModel()`             | `await RunAnywhere.instance.llm.currentModel()`       |
| `await RunAnywhere.chat(prompt)`                  | `await RunAnywhere.instance.llm.chat(prompt)`         |
| `await RunAnywhere.generate(prompt, options)`     | `await RunAnywhere.instance.llm.generate(prompt, options)` |
| `await RunAnywhere.generateStream(prompt, ...)`   | `await RunAnywhere.instance.llm.generateStream(prompt, ...)` |
| `await RunAnywhere.cancelGeneration()`            | `await RunAnywhere.instance.llm.cancel()`             |

### STT (Speech-to-Text)

| v3.x                                          | v4.0                                              |
|-----------------------------------------------|---------------------------------------------------|
| `await RunAnywhere.loadSTTModel(id)`          | `await RunAnywhere.instance.stt.load(id)`         |
| `await RunAnywhere.unloadSTTModel()`          | `await RunAnywhere.instance.stt.unload()`         |
| `RunAnywhere.isSTTModelLoaded`                | `RunAnywhere.instance.stt.isLoaded`               |
| `await RunAnywhere.transcribe(audio)`         | `await RunAnywhere.instance.stt.transcribe(audio)` |
| `await RunAnywhere.transcribeWithResult(...)` | `await RunAnywhere.instance.stt.transcribeWithResult(...)` |

### TTS (Text-to-Speech)

| v3.x                                       | v4.0                                              |
|--------------------------------------------|---------------------------------------------------|
| `await RunAnywhere.loadTTSVoice(id)`       | `await RunAnywhere.instance.tts.loadVoice(id)`    |
| `await RunAnywhere.unloadTTSVoice()`       | `await RunAnywhere.instance.tts.unloadVoice()`    |
| `RunAnywhere.isTTSVoiceLoaded`             | `RunAnywhere.instance.tts.isLoaded`               |
| `await RunAnywhere.synthesize(text, ...)`  | `await RunAnywhere.instance.tts.synthesize(text, ...)` |

### VLM (Vision-Language)

| v3.x                                              | v4.0                                                  |
|---------------------------------------------------|-------------------------------------------------------|
| `await RunAnywhere.loadVLMModel(id)`              | `await RunAnywhere.instance.vlm.load(id)`             |
| `await RunAnywhere.unloadVLMModel()`              | `await RunAnywhere.instance.vlm.unload()`             |
| `RunAnywhere.isVLMModelLoaded`                    | `RunAnywhere.instance.vlm.isLoaded`                   |
| `await RunAnywhere.processImage(image, ...)`      | `await RunAnywhere.instance.vlm.processImage(image, ...)` |
| `await RunAnywhere.processImageStream(image, ..)` | `await RunAnywhere.instance.vlm.processImageStream(image, ...)` |
| `await RunAnywhere.describeImage(image, ...)`     | `await RunAnywhere.instance.vlm.describe(image, ...)` |
| `await RunAnywhere.askAboutImage(q, ...)`         | `await RunAnywhere.instance.vlm.askAbout(q, ...)`     |
| `await RunAnywhere.cancelVLMGeneration()`         | `await RunAnywhere.instance.vlm.cancel()`             |

### Voice Agent

| v3.x                                                  | v4.0                                                          |
|-------------------------------------------------------|---------------------------------------------------------------|
| `RunAnywhere.isVoiceAgentReady`                       | `RunAnywhere.instance.voice.isReady`                          |
| `await RunAnywhere.initializeVoiceAgentWithLoadedModels()` | `await RunAnywhere.instance.voice.initializeWithLoadedModels()` |
| `RunAnywhere.cleanupVoiceAgent()`                     | `RunAnywhere.instance.voice.cleanup()`                        |

VoiceAgentStreamAdapter unchanged.

### Models

| v3.x                                              | v4.0                                                  |
|---------------------------------------------------|-------------------------------------------------------|
| `await RunAnywhere.availableModels()`             | `await RunAnywhere.instance.models.available()`       |
| `await RunAnywhere.refreshDiscoveredModels()`     | `await RunAnywhere.instance.models.refresh()`         |

### Downloads

| v3.x                                                  | v4.0                                                      |
|-------------------------------------------------------|-----------------------------------------------------------|
| `RunAnywhere.downloadModel(id)`                       | `RunAnywhere.instance.downloads.start(id)`                |
| `await RunAnywhere.deleteStoredModel(id)`             | `await RunAnywhere.instance.downloads.delete(id)`         |
| `await RunAnywhere.getStorageInfo()`                  | `await RunAnywhere.instance.downloads.getStorageInfo()`   |
| `await RunAnywhere.getDownloadedModelsWithInfo()`     | `await RunAnywhere.instance.downloads.list()`             |

## Migration recipe

### Step 1: Update the dependency

```yaml
dependencies:
  runanywhere: ^4.0.0
```

### Step 2: Add the `.instance` accessor

The simplest mechanical migration: replace `RunAnywhere.X` with
`RunAnywhere.instance.<capability>.<method>`.

**Find/replace patterns** (use sparingly — context matters):

```
RunAnywhere\.loadModel\(  →  RunAnywhere.instance.llm.load(
RunAnywhere\.chat\(        →  RunAnywhere.instance.llm.chat(
RunAnywhere\.generate\(    →  RunAnywhere.instance.llm.generate(
RunAnywhere\.transcribe\(  →  RunAnywhere.instance.stt.transcribe(
RunAnywhere\.synthesize\(  →  RunAnywhere.instance.tts.synthesize(
... etc.
```

### Step 3: Use the deprecation shim during transition

v4.0.0 ships the OLD static API as `@Deprecated` forwarders to the
new instance API for ONE minor version cycle (v4.0.x). v4.1 deletes
the static surface. This gives you a buffer to migrate at your own
pace.

```dart
// Both work in v4.0:
await RunAnywhere.loadModel('llama-3-8b');           // @Deprecated, prints warning
await RunAnywhere.instance.llm.load('llama-3-8b');   // Canonical

// Only the canonical form works in v4.1+
```

### Step 4: Update sample apps

The official `examples/flutter/RunAnywhereAI/` sample is migrated
in v4.0.0 — use it as the reference for migrating your own app.

## Why this is the right shape

The instance pattern enables:

- **Lazy capability initialization**: each capability getter only
  spins up when first accessed.
- **Per-capability mocking** for tests.
- **Cleaner namespacing**: 80+ static methods → 9 grouped instance APIs.
- **File-scope splitting**: each capability lives in its own file
  (lib/public/capabilities/*.dart), reducing the god-class problem
  from 2,607 LOC to ~150 LOC core + 9 ~150-300 LOC files.
- **Discoverability**: IDE autocomplete on `instance.` shows you
  exactly which capabilities exist, not 80+ methods on the class.

## Frequently asked

**Q: Will the deprecated static API still work in v4.0?**
A: Yes — every static method is a one-line forwarder marked
`@Deprecated` with a `ReplaceWith` hint. Your app compiles + runs
unchanged on v4.0; you'll get analyzer warnings.

**Q: When does the static API get deleted?**
A: v4.1.0. That gives you at least one minor cycle to migrate.

**Q: Are there other breaking changes besides the API shape?**
A: No. The semantics of every method are unchanged — only the
call site changes from `RunAnywhere.X` to `RunAnywhere.instance.cap.X`.

**Q: What about the proto types (VoiceEvent, etc.)?**
A: Unchanged. Generated from `idl/voice_events.proto`; consumers
import them the same way as v3.x.

**Q: What about the C ABI (`RAC_PLUGIN_API_VERSION`)?**
A: Unchanged at `3u`. v4.0.0 is a Flutter SDK API-shape change
only; the underlying native commons stays on the v3.x ABI.
