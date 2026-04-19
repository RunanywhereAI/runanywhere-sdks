# RunAnywhere v2 — proto3 IDL

These three schemas are the single source of truth for event shapes, pipeline
configuration, and ergonomic solution configs across every frontend. No
frontend defines its own event/config types by hand; all types are codegen'd
from these files.

| File | Purpose |
| --- | --- |
| `voice_events.proto` | Streaming events emitted by the VoiceAgent pipeline |
| `pipeline.proto`     | General DAG specification (operators + edges + options) |
| `solutions.proto`    | Ergonomic configs for VoiceAgent, RAG, WakeWord, etc. |

## Regenerating bindings

```bash
./idl/codegen/generate_all.sh      # runs every language
# or per language:
./idl/codegen/generate_swift.sh    # → frontends/swift/Sources/RunAnywhere/Generated
./idl/codegen/generate_kotlin.sh   # → frontends/kotlin/src/main/kotlin/com/runanywhere/generated
./idl/codegen/generate_dart.sh     # → frontends/dart/lib/generated
./idl/codegen/generate_ts.sh       # → frontends/ts/src/generated, frontends/web/src/generated
./idl/codegen/generate_python.sh   # → frontends/python/runanywhere/generated
```

Every regenerated file is tracked in git — CI verifies that `generate_all.sh`
produces a clean tree (no uncommitted diffs) so that hand-edits are caught.

## Compatibility policy

- **Never remove** an existing field number. Deprecate the field, stop
  reading it, but leave it in the schema for binary compatibility.
- **Never repurpose** a field number. Assign a fresh number when adding a
  replacement field.
- **Bumping `ra_abi_version`** (`core/abi/ra_version.h`) is required when
  adding a new `oneof` arm to `VoiceEvent` or changing the C ABI surface.
- **Bumping `ra_plugin_api_version`** is required when changing the
  `ra_engine_vtable_t` layout in `core/abi/ra_plugin.h`.

## Wire format

The C ABI (`core/abi/ra_pipeline.h`) carries proto3 messages as length-prefixed
byte buffers — `(const uint8_t*, size_t)`. Every frontend decodes with its
native proto3 runtime. In-process C++ edges carry raw data by reference; the
proto3 surface only appears at the ABI boundary.
