# C++ desktop kit

The kit is the **only** supported way for [RCLI](https://github.com/RunanywhereAI/RCLI)
to consume this SDK. It is not an rcli binary.

## Layout

```text
include/rac/**                         public C ABI
include/runanywhere/proto/*.pb.h       generated messages (same protoc as commons)
include/google/protobuf/**             vendored runtime headers (PROTOBUF_VERSION pin)
include/absl/**                        vendored absl headers the runtime needs
lib/librac_commons.a                   STATIC_PLUGINS=ON, DESKTOP_ADAPTER=ON
lib/cmake/RunAnywhere/RunAnywhereConfig.cmake
share/runanywhere/idl/*.proto          wire schema
share/runanywhere/SCHEMA_LOCK          proto fingerprint (idl/SCHEMA_LOCK)
share/runanywhere/VERSION
third_party/                           onnxruntime / sherpa shared libs if needed
```

## Protobuf contract (SOT across SDK and RCLI)

`idl/*.proto` is the schema. There is **one** C++ compilation of that schema:
commons, packed into `librac_commons.a`. The kit also ships the matching
`*.pb.h` plus the exact protobuf/absl headers commons was built against.

RCLI includes those headers and uses `runanywhere::v1::*` at the `rac_*` byte
boundary (`ParseFromArray` / `SerializeToString`). It must not run `protoc`,
compile `*.pb.cc`, or `find_package(Protobuf)` against Homebrew.

Cross-repo consistency is `idl/SCHEMA_LOCK` (digest of every `.proto` +
`IDL_VERSION` + pinned protoc). The kit copies that lock into
`share/runanywhere/SCHEMA_LOCK` and `find_package(RunAnywhere)` exports
`RunAnywhere_IDL_SCHEMA_SHA256`. RCLI pins the same values in
`cmake/sdk-pin.cmake` and configure-fails on mismatch. Bump the pin when you
consume a new kit — never regenerate headers in RCLI.

`find_package(RunAnywhere)` puts the proto include path and, when the kit was
built with namespace isolation, `google=runanywhere_internal` on
`RunAnywhere::commons`.

## Build locally

```bash
./scripts/build/package-cpp-desktop.sh          # macOS arm64 default
cmake --preset cpp-desktop-windows-x64 && cmake --build --preset cpp-desktop-windows-x64
```

Then in RCLI:

```bash
cmake -B build -DCMAKE_PREFIX_PATH=/path/to/dist/cpp-desktop-macos-arm64
```

`find_package(RunAnywhere ${PIN} EXACT REQUIRED)` links `RunAnywhere::commons`.

## Private packs

NeuRT (Apple ANE) and QHexRT (Windows ARM64 NPU) are **not** in the public kit.

```bash
NEURUN_TOKEN=... ./scripts/build/fetch-private-engine-pack.sh neurt macos-arm64
```

RCLI defines `RCLI_HAS_NEURT` only when `RunAnywhere::neurt` (or the pack) is present.
