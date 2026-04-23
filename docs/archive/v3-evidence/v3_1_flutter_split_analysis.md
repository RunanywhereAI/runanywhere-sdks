# v3.1 Phase 7 — Flutter runanywhere.dart split analysis

_Status: deferred to post-v3.1. Dart language constraints prevent the
Swift-style extension-based split without breaking the public API._

## Goal (original plan)

Split the 2,605-LOC `runanywhere.dart` god-class into:
- Core shell (≤500 LOC): class definition + `initialize()` + env/version getters
- 10 per-capability extension files (~200-400 LOC each) mirroring
  Swift's `RunAnywhere+LLM.swift`, `RunAnywhere+STT.swift`, etc.

## Why the Swift pattern doesn't port to Dart

Swift's `extension RunAnywhere { static func loadSTT(...) {...} }` adds
methods to the original class. Callers use `RunAnywhere.loadSTT(...)` —
the API shape is identical to when `loadSTT` lives inside the main
class body.

Dart has two analogous mechanisms, neither of which preserves the
`ClassName.staticMethod()` call syntax:

### Option A: `extension X on Type { static method() {...} }`

Dart requires callers to write `X.method()`, NOT `Type.method()`. The
extension name becomes the call-site namespace. So:

```dart
// main.dart
class RunAnywhere {}

// runanywhere_llm.dart
extension RunAnywhereLLM on RunAnywhere {
  static Future<void> loadLLM(String id) async {...}
}

// Call site:
RunAnywhereLLM.loadLLM('foo');   // MUST use extension name
// NOT: RunAnywhere.loadLLM('foo'); — compile error
```

Every consumer (sample apps, third-party integrators) would need to
rewrite every call site. Breaking API change.

### Option B: `part` / `part of`

Dart's `part` mechanism splits LIBRARY contents across files but a
single CLASS body must live in ONE file. You can't have the class
opener `{` in `main.dart` with some members, then close `}` after a
`part` file's members merge in. The parser sees the class as
self-contained per-file.

### Option C: Top-level functions + facade

Move `loadLLM`, `transcribe`, etc. to top-level library functions
(no class membership). Keep `class RunAnywhere` as a thin facade with
one-line forwards:

```dart
// runanywhere_llm_impl.dart
Future<void> loadLLMImpl(String id) async {...}

// runanywhere.dart
class RunAnywhere {
  static Future<void> loadLLM(String id) => loadLLMImpl(id);
}
```

This PRESERVES the public API but adds ~100 LOC of thin forwards for
all 80+ methods. Net LOC reduction modest; structural complexity
increases (two hops per call).

### Option D: Instance methods on a singleton + extensions

Refactor to `RunAnywhere.instance.loadLLM(...)` and use instance-method
extensions. BREAKING API CHANGE; every caller migrates.

## Recommended path (post-v3.1)

The 2,605-LOC concentration is real technical debt, but solving it
requires a deliberate API-shape decision. Options for future major
version (v4.x):

1. **Breaking API migration to instance methods** (Option D). The
   canonical Dart idiom for multi-capability SDKs (e.g. `supabase`
   client uses `client.auth.signIn()`, `client.storage.upload()`).
   Cleanest long-term; breaking.

2. **Facade with private helpers** (Option C). Non-breaking; ~15%
   LOC reduction from splitting private impl details but the class
   body stays large because of forward boilerplate.

3. **Accept the size** and enforce modularity via lint rules
   (`analyze_directives`) + directory-based logical grouping within
   the single file. Pragmatic for Dart.

## v3.1 deliverable

This document + the existing `runanywhere.dart` structurally
annotated with `// MARK: - Capability Name` section headers (already
present). No code changes to `runanywhere.dart` beyond the Phase 4
voice-session deletions (which removed ~95 LOC from the file).

Post-v3.1 backlog item:
- [ ] Decide on Dart API shape (instance method pattern vs facade)
- [ ] Execute chosen split across 10 files
- [ ] Migrate Flutter sample + 3rd-party docs

## Metrics

| Metric | Before Phase 4 | After Phase 4 | v3.1 target | Delta |
|---|---|---|---|---|
| `runanywhere.dart` LOC | 2,688 | 2,607 | ≤500 | Not met |
| Dart language blocker | n/a | present | present | n/a |

The file shrank ~80 LOC via Phase 4 voice-session cleanup. The
target `≤500` is blocked on the API-shape decision above.
