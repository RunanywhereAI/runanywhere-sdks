# scripts/

Every script in the repo lives here. `./run` at the repo root is the only
entry point — it dispatches into these directories.

| Directory | Contents |
|---|---|
| `lib/` | Shared shell helpers (`common.sh`), mode detection, version loading, JS/TS version pins (`versions.json`, `syncpack.json`) |
| `setup/` | Host provisioning: `setup.sh`, `doctor.sh`, `toolchain.sh` (IDL codegen toolchain) |
| `build/` | Native core builds: `android.sh`, `ios-xcframework.sh`, `linux.sh`, `wasm.sh`, `windows.bat`, `deps/` (vendored prebuilt downloads), `wasm/` (emsdk + vendor + bundle) |
| `codegen/` | Proto codegen for all languages (`generate_all.sh`, per-language generators, tests) |
| `release/` | Version sync, per-SDK packaging (`package-*.sh`), checksums, rcli packaging/tap |
| `validation/` | Source gates: centralization, deprecated surfaces, PII logging, RAC API exports, `lint-cpp.sh` |
| `examples/` | Per-example-app verify/smoke/stage helpers |

Conventions: bash + `set -euo pipefail`, `--help` on every executable script,
output through `lib/common.sh` helpers. Native builds run CMake from
`sdk/runanywhere-commons` (the CMake root); build output lands in
`sdk/runanywhere-commons/build/<preset>/`.
