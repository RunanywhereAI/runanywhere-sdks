# Refreshing the QHexRT win-arm64 prebuilt

How to get newer [neurun](https://github.com/RunanywhereAI/neurun) QHexRT work into
`@runanywhere/electron-qhexrt`. This is a **manual procedure on one physical machine**.
It is not automatable today, for reasons recorded below — read those before trying.

## Why this is manual

`engines/qhexrt/CMakeLists.txt` consumes a **prebuilt receipt tree**
(`include/qhexrt/qhexrt_c.h`, `lib/win-arm64/qhexrt_{core,host}.lib`, plus
`qhexrt-build-receipt.json` and `qhexrt-prebuilt.json`). It never builds QHexRT from
source. Three things block producing that tree in CI:

| Blocker | Evidence |
|---|---|
| neurun's `qhexrt_build_receipt` CMake target is `if(ANDROID)`-gated, so it does not exist for the `windows-arm64-*` presets | neurun `CMakeLists.txt:375` |
| neurun's `stage_prebuilt_for_sdk.sh` is POSIX-only (`ps -o lstart=`, `os.symlink`, `diff -qr`) | neurun `QHexRT/device_suites/run_windows_e2e.ps1:78-88` documents this and says the win-arm64 payload is published as a plain `versions/<64-hex>` dir |
| QAIRT is licence-gated; `qhexrt_core` compiles against its QNN headers | neurun `CMakePresets.json:43-54` |

**The durable fix belongs upstream in neurun**, not here: un-gate the receipt target
and add a Windows-capable publisher. Until then, this procedure plus
`scripts/validation/gates/check_qhexrt_provenance.py` is the honest scope — the gate
makes staleness *loud* instead of silent.

## Prerequisite: QAIRT ≥ 2.47 (2.48 recommended)

**As of 2026-08-22 the runner has QAIRT 2.41.0.251128, which is too old.** A human
with a Qualcomm account must install a newer QAIRT on the Snapdragon X2 Elite box
first. Requirements, from neurun's own rules:

- **≥ 2.42** for the Windows-on-ARM HTP stack (`lib/aarch64-windows-msvc/`) —
  `QHexRT/AGENTS.md` rule 43a
- **≥ 2.47** for Hexagon v81 work — `QHexRT/docs/BUILD.md:30`
- A context binary **does not load on a QAIRT older than the one that compiled it**.
  Measured: a v81 bundle compiled on 2.47 fails `contextCreateFromBinary` with
  `err=0x1388` on 2.41, and loads on 2.48 — `QHexRT/AGENTS.md` rule 43b. Metadata
  parsing is *not* a load test, so this will not show up in a pre-flight.

## Procedure

On the X2 Elite box (SSH alias `runanywhere-win`; check `tailscale status | grep runanywhere`
first — if it says `offline, last seen …` the box is asleep, ask a human to wake it).

```powershell
# 0. point at the NEW QAIRT, and clone/update neurun at the commit you want
$env:QNN_SDK_ROOT = "C:\path\to\qairt\2.48.x"
git clone https://github.com/RunanywhereAI/neurun.git C:\src\neurun   # or: git -C C:\src\neurun fetch --all
cd C:\src\neurun; git checkout <neurun-sha>

# 1. build ONLY the two archives the SDK links (tools/tests need more of the SDK)
cmake --preset windows-arm64-release-vs2026 -DQHEXRT_BUILD_TOOLS=OFF -DQHEXRT_BUILD_TESTS=OFF
cmake --build build/windows-arm64-release-vs2026 --config Release `
      --target qhexrt_core qhexrt_host -- /m

# 2. the .libs land in build/<preset>/Release/, but the staging script wants them FLAT
Copy-Item build\windows-arm64-release-vs2026\Release\qhexrt_*.lib `
          build\windows-arm64-release-vs2026\

# 3. no CMake receipt target off Android -> call the tool directly.
#    NOTE: --qn is REQUIRED and --ndk is REJECTED for win-arm64.
#    Take compiler id/version from build/<preset>/CMakeCache.txt.
python QHexRT\tools\scripts\qhexrt_build_receipt.py create `
  --receipt build\windows-arm64-release-vs2026\qhexrt-build-receipt.json `
  --source-root . --build-dir build\windows-arm64-release-vs2026 `
  --header QHexRT\include\qhexrt\qhexrt_c.h `
  --core build\windows-arm64-release-vs2026\qhexrt_core.lib `
  --host build\windows-arm64-release-vs2026\qhexrt_host.lib `
  --abi win-arm64 --build-type Release `
  --compiler "<CMAKE_CXX_COMPILER>" --compiler-id MSVC `
  --compiler-version "<CMAKE_CXX_COMPILER_VERSION>" --qnn "$env:QNN_SDK_ROOT"

# 4. publish. stage_prebuilt_for_sdk.sh needs Git Bash + Developer Mode (for the
#    `current` symlink). The SDK path used here passes -DQHEXRT_ROOT explicitly and
#    never reads `current`, so hand-building the versions/<sha> dir is fine and is
#    what run_windows_e2e.ps1 documents as normal on Windows:
#      versions/<sha256-of-receipt>/{include/qhexrt/qhexrt_c.h,
#                                    lib/win-arm64/qhexrt_{core,host}.lib,
#                                    qhexrt-build-receipt.json, qhexrt-prebuilt.json}
```

## Then, in this repo — one commit, three files

1. `.github/workflows/electron-native-package.yml` — move `QHEXRT_ROOT` (it appears
   **twice**: the provenance-check step and the configure step) to the new
   `versions/<sha>` path. The directory name must equal the receipt's own
   `build_receipt_sha256`; `engines/qhexrt/CMakeLists.txt` enforces that self-identity
   rule and will `FATAL_ERROR` on a friendly-named directory.
2. `engines/qhexrt/PREBUILT_PROVENANCE.json` — update `build_receipt_sha256`,
   `neurun.*`, `qhexrt_version`, `staged_at`, `recorded_on`, and prune any
   `known_gaps` the refresh resolves. Read the values straight off the new receipt:
   ```bash
   ssh runanywhere-win "python -c \"import json;print(json.dumps(json.load(open(r'<path>\\qhexrt-build-receipt.json')),indent=1))\""
   ```
3. Verify before pushing:
   ```bash
   python3 scripts/validation/gates/check_qhexrt_provenance.py --record-only   # expect 0 behind
   ```

## Verifying the result actually shipped

After the release, prove the NPU plugin is real and routable rather than trusting CI:

```bash
gh run download <run-id> --name sdk-electron-qhexrt-private --dir /tmp/q
python3 scripts/validation/gates/check_plugin_natives.py --tarball /tmp/q/*.tgz
# expect: qhexrt ... satisfies its routability contract: qhexrt:engine-available
```

`qhexrt:engine-available` is the marker that distinguishes a real Hexagon plugin from
a shell that exports `rac_plugin_entry_qhexrt` and looks healthy by size —
`g_qhexrt_llm_ops` is internal on PE and is **not** evidence.
