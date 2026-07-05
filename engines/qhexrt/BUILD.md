# QHexRT Engine — Qualcomm Hexagon NPU backend

QHexRT is RunAnywhere's **private** Hexagon NPU runtime; this directory is the
public glue that exposes it as the `qhexrt` engine plugin. It runs prebuilt QNN
context binaries on Snapdragon HTP. Android **arm64-v8a only**, on Hexagon
**v75 / v79 / v81** parts (Snapdragon 8 Gen 3 / 8 Elite class); other devices
get a probe warning and no QHEXRT catalog entries.

## The public repo always compiles

QHexRT source never enters this repo — only its compiled archives do, and even
those are gitignored. The prebuilt tree (see `.gitignore`):

```text
engines/qhexrt/prebuilt/               # gitignored — staged locally
├── include/qhexrt/qhexrt_c.h
└── lib/arm64-v8a/
    ├── libqhexrt_core.a
    └── libqhexrt_host.a
```

Build modes (`CMakeLists.txt`):

- `RAC_BACKEND_QHEXRT=OFF` (**the default**) — the backend is skipped entirely;
  nothing here is compiled.
- `RAC_BACKEND_QHEXRT=ON`, prebuilt tree **absent** (a fresh public clone) — a
  **not-routable stub** compiles with no private header/lib. It still exports
  the plugin entry symbol but publishes an all-NULL vtable and rejects
  registration with `RAC_ERROR_BACKEND_UNAVAILABLE`. The build always links.
- `RAC_BACKEND_QHEXRT=ON`, all three prebuilt files present (or
  `-DQHEXRT_ROOT=<path>`) — the real engine links into
  `librac_backend_qhexrt.so` (plus `librac_backend_qhexrt_jni.so` for Kotlin).

## Integration surface at a glance

- **Plugin registration** (`rac_plugin_entry_qhexrt.cpp`,
  `rac_backend_qhexrt_register.cpp`): priority **150** for
  `QNN_CONTEXT`-format models, gated at runtime on a supported Hexagon arch
  (v75/v79/v81) — unsupported parts never register the providers.
- **Bundle policy** (`qhexrt_bundle_policy.h`): registered with the commons
  bundle-policy registry, so a model is a **one-line registration** —
  `registerModel(url = "hf.co/<org>/<model>_HNPU/<arch>/<manifest>.json",
  framework = QHEXRT)`. Commons resolves the full HF folder-bundle file set;
  apps carry no file lists.
- **`ADSP_LIBRARY_PATH` is engine-owned** (`qhexrt_session.cpp`): set once
  before the first runtime create, from the engine `.so`'s own directory plus
  the vendor DSP fallbacks. Apps and platform glue must **not** set it.
- **NPU capability probe**: `rac_npu_probe` / `rac_npu_probe_proto` (commons,
  `rac/infrastructure/device/rac_npu_capability.h`, `NpuCapability` proto)
  reads the SoC identity **without loading QNN**; surfaced to apps as
  `QHexRT.probeNpu()` (Kotlin) and the equivalent Flutter/RN bindings.

## Full build / stage / run documentation (private)

The complete flow — building the QHexRT static libs, staging them into
`prebuilt/`, Kotlin/Flutter/React-Native packaging, the QAIRT runtime + skel
library set, example-app requirements (`uses-native-library libcdsprpc.so`,
legacy jniLibs packaging), HF-token setup for gated bundles, smoke checks, and
troubleshooting — lives in the **private QHexRT repo: `docs/BUILD.md`**.
