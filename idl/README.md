# RunAnywhere IDL

**These proto3 schemas are the single source of truth for every shared enum,
struct, streaming event, and pipeline/solution config across every SDK.**
No frontend hand-defines its own copy; every language consumes codegen output.

| File                | Purpose                                                                  |
|---------------------|--------------------------------------------------------------------------|
| `model_types.proto` | Model / framework / audio / category / environment / artifact enums + `ModelInfo` struct |
| `voice_events.proto`| Streaming events emitted by the VoiceAgent pipeline                      |
| `pipeline.proto`    | General DAG specification (operators + edges + options)                  |
| `solutions.proto`   | Ergonomic configs for VoiceAgent, RAG, WakeWord, AgentLoop, TimeSeries   |

## Regenerating bindings

```bash
# Install toolchain (protoc, language plugins)
./scripts/setup-toolchain.sh

# Regenerate every language
./idl/codegen/generate_all.sh

# Per language
./idl/codegen/generate_swift.sh    # → sdk/runanywhere-swift/Sources/RunAnywhere/Generated/
./idl/codegen/generate_kotlin.sh   # → sdk/runanywhere-kotlin/src/commonMain/kotlin/com/runanywhere/sdk/generated/
./idl/codegen/generate_dart.sh     # → sdk/runanywhere-flutter/packages/runanywhere/lib/generated/
./idl/codegen/generate_ts.sh       # → sdk/runanywhere-react-native/packages/core/src/generated/
                                   #   sdk/runanywhere-web/packages/core/src/generated/
./idl/codegen/generate_python.sh   # → sdk/runanywhere-python/src/runanywhere/generated/
./idl/codegen/generate_cpp.sh      # → sdk/runanywhere-commons/src/generated/proto/
```

Every regenerated file is tracked in git. The `idl-drift-check` CI job runs
`generate_all.sh` on every PR and fails if `git diff --exit-code` shows any
change — this is the one mechanism that prevents the hand-written enum drift
problem from returning.

## Compatibility policy

- **Never remove** an existing field number. Deprecate the field, stop
  reading it, but leave it in the schema for binary compatibility.
- **Never repurpose** a field number. Assign a fresh number when adding a
  replacement field.
- **Bumping `RAC_ABI_VERSION`** (in `sdk/runanywhere-commons/include/rac/core/rac_version.h`)
  is required when adding a new `oneof` arm to `VoiceEvent` or changing the
  binary shape of the C ABI.
- **Bumping `RAC_PLUGIN_API_VERSION`** (introduced in GAP 02) is required
  when changing `rac_engine_vtable_t`.

## Wire format

The C ABI carries proto3 messages as length-prefixed byte buffers — `(const uint8_t*, size_t)`.
Every frontend decodes with its native proto3 runtime. In-process C++ edges
carry raw data by reference; the proto3 surface only appears at the ABI
boundary.

## Relationship to Nitrogen (React Native)

Nitrogen (`react-native-nitro-modules`) generates C++/JSI HybridObject
signatures at the RN ↔ JS bridge layer. That is orthogonal to this IDL:
Nitrogen describes the **function signatures** crossing JSI; this IDL
describes the **data types** carried in those signatures. Both generators
coexist and cover different layers.
