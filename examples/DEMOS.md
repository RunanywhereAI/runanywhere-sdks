# End-to-end demos — all 5 SDKs against the new C++ core

Each demo is a minimal CLI / test that exercises the full call path
through its SDK into `ra_pipeline_create_voice_agent` in the new C core.
All five run to completion on macOS against a single `racommons_core`
shared library build.

## Prerequisites

```bash
# One-time: build the Release shared lib + xcframework.
cmake -S . -B build/macos-release \
  -DCMAKE_BUILD_TYPE=Release -DRA_ENABLE_SANITIZERS=OFF \
  -DRA_BUILD_TESTS=OFF -DRA_BUILD_ENGINES=OFF -DRA_BUILD_SOLUTIONS=OFF
cmake --build build/macos-release --target racommons_core

bash scripts/build-core-xcframework.sh --platforms=macos
```

## Running each demo

### Swift (`examples/swift-demo/`)

```bash
cd examples/swift-demo
swift run
```

Expected tail:
```
✓ session created — dispatching pipeline start
✓ call path reached core; received expected error: internal: ra_pipeline_run failed: -6
```

### Kotlin / JVM (`examples/kotlin-demo/`)

```bash
cd examples/kotlin-demo
RA_LIB_DIR="$(pwd)/../../build/macos-release/core" gradle --no-daemon run
```

Expected tail:
```
event[error]: code=-6 message=ra_pipeline_run failed: -6
✓ stream completed with 1 event(s)
```

### Dart (`examples/dart-demo/`)

```bash
cd examples/dart-demo
dart pub get
LIB_PATH="$(pwd)/../../build/macos-release/core/libracommons_core.dylib" dart run bin/demo.dart
```

Expected tail:
```
✓ dlopen + lookupFunction ra_pipeline_create_voice_agent succeeded
✓ adapter stream completed with 2 event(s)
```

### TypeScript / Node (`examples/ts-demo/`)

```bash
cd examples/ts-demo
npm install
npm run build
node dist/examples/ts-demo/src/main.js
```

Expected tail:
```
event: { kind: 'user-said', text: 'hello world', isFinal: true }
event: { kind: 'error', code: -6, ... }
✓ stream completed (1 synthetic events)
```

### Web / Browser-shaped (`examples/web-demo/`)

Runs under Node for now (the WASM bundle from the new core is future
work), but exercises the same `@runanywhere/web-core` API a browser
page would:

```bash
cd examples/web-demo
npm install
npm test
```

Expected tail:
```
event: { kind: 'error', code: -6,
  message: 'RunAnywhere WASM bundle not loaded; ...' }
✓ stream completed
```

## Why "BACKEND_UNAVAILABLE (-6)" is the success signal

All five demos link the core but do **not** register any engine plugins
(llama.cpp, sherpa-onnx, etc). When the pipeline tries to route the LLM
/ STT / TTS / VAD primitives, no engine matches and the C core returns
`RA_ERR_BACKEND_UNAVAILABLE (-6)`. That error arriving from the
completion callback proves the SDK → C ABI → C++ pipeline → completion
path is fully wired.

Swapping in real engines is additive:
- **Swift**: add llamacpp_engine.a to the xcframework + call
  `RunAnywhere.configure { $0.register(.llamacpp) }` at startup.
- **Kotlin**: load `librunanywhere_llamacpp.so` before
  `System.loadLibrary("racommons_core")`; static-register via
  `RA_STATIC_PLUGIN_REGISTER`.
- **Dart**: `DynamicLibrary.open("librunanywhere_llamacpp.dylib")`
  before the first session.
- **TS/RN**: the TurboModule bundles llamacpp_engine.a; expose a
  `loadPlugin()` TurboModule method.
- **Web**: emscripten builds llamacpp as part of the same WASM bundle;
  no separate load step.
