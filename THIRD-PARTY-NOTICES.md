# Third-party notices

RunAnywhere SDKs redistribute binaries from third parties. This file names them,
says which published artifacts carry them, and points at the upstream terms.

## Qualcomm AI Runtime (QAIRT / Qualcomm AI Engine Direct)

**RunAnywhere is an authorized Qualcomm partner and redistributes the QAIRT
runtime under that agreement.**

The `qhexrt` engine runs prebuilt QNN context binaries on Snapdragon Hexagon
NPUs. It compiles against QAIRT **headers only** and `dlopen`s the runtime at
execution time, so the runtime libraries have to ship alongside the engine — an
application that links the engine without them gets a plugin that registers and
then fails at model load.

Pinned version: see `QAIRT_RUNTIME_VERSION` in [`core/VERSIONS`](core/VERSIONS).
The redistributables are published as checksum-pinned public release assets
(`qairt-runtime-v<version>`), produced by
[`scripts/build/publish-qairt-runtime.sh`](scripts/build/publish-qairt-runtime.sh)
from a licensed QAIRT install and consumed by
[`scripts/build/download-qairt-runtime.sh`](scripts/build/download-qairt-runtime.sh).
The exact file list is
[`scripts/build/qairt-runtime-manifest.json`](scripts/build/qairt-runtime-manifest.json).

Qualcomm's own `NOTICE.txt`, `QNN_NOTICE.txt` and `LICENSE.pdf` travel inside
every published QAIRT runtime asset and inside each SDK artifact that bundles
these libraries.

### Which artifacts carry Qualcomm binaries

| Artifact | Platform | Contents |
|---|---|---|
| `runanywhere-qhexrt-android` (Maven) | Android arm64-v8a | 10 host libs in `jni/arm64-v8a/`, 3 DSP skels in `assets/` |
| `@runanywhere/qhexrt` (npm) | Android arm64-v8a | same set |
| `@runanywhere/electron-qhexrt` (npm) | Windows ARM64 | 5 DLLs, the v81 skel, and its `.cat` catalog |

Per-artifact notices ship inside each package (for example
`META-INF/THIRD-PARTY-NOTICES-QAIRT.txt` in the Android AAR).

### Not redistributed

The FastRPC libraries (`libcdsprpc.so` / `libadsprpc.so`) and the Hexagon DSP
firmware are vendor/OS components. They are declared with
`<uses-native-library required="false">` and resolved on device; nothing here
ships them.

## Other bundled dependencies

Sherpa-ONNX, ONNX Runtime, llama.cpp and MLX are pinned in
[`core/VERSIONS`](core/VERSIONS) and carry their own upstream licenses. Their
notices ship with the artifacts that bundle them.
