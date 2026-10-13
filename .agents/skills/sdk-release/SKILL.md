---
name: sdk-release
description: Cut a new RunAnywhere SDK release end-to-end in RunanywhereAI/runanywhere-sdks — version bump through a fully green, tagged, drafted-then-published GitHub Release. Stops BEFORE publishing to package registries (npm/Maven/pub.dev/SwiftPM dist) — that is the separate "sdk-publish" skill, invoked as the last step here.
---

# SDK Release (runanywhere-sdks)

Repo: `~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks` (verify with `pwd`/`ls` —
this is a workspace subfolder, not the repo root of the whole Qualcomm/ tree, and paths
drift; re-check script paths below still exist before trusting them blindly).

This is a **runbook**, not a description. Follow the steps in order. Every `gh`/`git`
command below is meant to be run close to verbatim — adjust only the version/PR/run-id
values for the release you're actually cutting.

**THIS SKILL HAS BEEN SKIPPED THREE TIMES IN A ROW (v0.20.29, v0.20.30, v0.20.31),
producing the IDENTICAL failure each time, DESPITE step 2/3 below documenting the exact
fix since the v0.20.25/v0.20.29 incidents.** All three times, an agent ran
`sync-versions.sh`, opened the PR, merged it, and pushed the tag directly — skipping the
"dispatch a release candidate BEFORE merging, sync checksums from it, THEN merge" sequence
in steps 2-3 — usually because the version bump was one step inside a longer autonomous
chain (a downstream repo re-pin, a multi-repo release cascade) and felt like "just a
version bump," not a release. **A version bump to `core/VERSION` IS a release. If you are
about to run `scripts/release/sync-versions.sh` for ANY reason — including re-pinning this
repo as a step in some OTHER repo's release — stop and follow this skill from step 1,
including the candidate dispatch. Do not improvise the sequence from memory even if you
did it correctly last time; do not skip it because "this bump is small" or "we're in a
hurry."** v0.20.31 additionally caught a second, previously-undetected instance of the
same class of bug in the SAME commit: `RunAnywhereMLXRuntime` in the Flutter podspec (which
`RAC_CHECKSUM_SKIP` exempts from CI verification, so it fails silently for a consumer
instead of failing `publish`) was ALSO stale, and had to be independently re-verified
against the same candidate build — see step 3's checksum-location table; check every row
in it, not just the one CI complained about.

Companion skill: **sdk-publish** — invoke it at the very end (step 10) for the actual
npm / Maven / pub.dev / SwiftPM-distribution publishing. This skill's job stops at a
published (non-draft) GitHub Release with correct assets.

---

## 0. Orientation facts (confirm these still hold before relying on them)

- Canonical version file: `core/VERSION` (single line, e.g. `0.20.24`). `core/VERSIONS`
  also carries a `PROJECT_VERSION=` line that must agree — `sync-versions.sh` updates
  both, `auto-tag.yml` reads `core/VERSIONS`, `check_release_version_coherence.sh` reads
  `core/VERSION`. Don't hand-edit either; always go through the script.
- `scripts/release/sync-versions.sh <version>` — bumps ~20 files (Package.swift,
  gradle.properties, all package.json/pubspec.yaml, Kotlin/Swift/TS version constants,
  AGENTS.md). Accepts a leading `v` and strips it.
- `scripts/validation/gates/check_release_version_coherence.sh` — the gate that enforces
  "PR changing VERSION must carry exactly one `release:patch|minor|major` label, and the
  new version must be exactly base+1 for that bump type." Reads `PR_BASE_SHA` and
  `PR_RELEASE_LABELS_JSON` env vars when run under CI; locally it only checks the
  canonical-version-format part.
- `.github/workflows/pr-build.yml` job **`centralization`** is what actually runs the
  coherence gate in CI (`Release-train version coherence` step), alongside
  `check_typescript_centralization.sh`, `check_flutter_centralization.sh`,
  `check_gradle_centralization.sh`, `check_wasm_provenance_contract.sh`,
  `check_swift_dist_repo_sync.sh`, `check_agents_claude_sync.sh`,
  `check_no_hardcoded_defaults.sh`. This job's trigger types are
  `[opened, synchronize, reopened, labeled, unlabeled]` — **adding the release label
  after opening the PR fires a fresh run**, which is how the gate clears without a new
  commit (see step 1).
- `.github/workflows/release.yml` — the build/package/draft-release workflow. Triggers:
  tag push `v*.*.*` OR `workflow_dispatch` (works on **any branch**, not just tags) with
  inputs `version` (required), `validate_external_starters` (bool, default false),
  `publish_from_run_id` (optional), `reuse_native_web_run_id` (optional).
- `.github/workflows/auto-tag.yml` — fires on `pull_request: closed` to `main` when the
  merged PR carries a `release:*` label. Verifies the version bump matches the label,
  pushes the `v<version>` tag, and **explicitly dispatches a fresh `release.yml` run at
  that tag** (plain `git push` of a tag with `GITHUB_TOKEN` does not auto-trigger
  workflows, so it calls `gh workflow run release.yml --ref v<version> -f version=<version>`
  itself). This is the redundant rebuild you must cancel — see step 7.
- Branch protection on `main`: check
  `gh api repos/RunanywhereAI/runanywhere-sdks/branches/main/protection` — 2 approvals +
  code owner review required, but look for a `bypass_pull_request_allowances` (users/teams/apps)
  list. If your `gh api user --jq .login` is on that list, `gh pr merge --squash --admin`
  is a legitimate, pre-configured bypass — not a hack. If not on the list, stop and ask a
  human to approve/merge.
- Never let any `qhexrt`-named asset reach the public asset set. `release.yml`'s own
  manifest-assertion step (`find release-flat -maxdepth 1 -type f -iname '*qhexrt*'`)
  hard-fails the run if one is found — this is enforced, not just policy.
- **Electron IS part of `release.yml` now** (as of `fix/electron-cicd-staging-url-npu-ane`,
  2026-08-21) — this reverses the prior "deliberately separate" policy noted below by an
  earlier pass; the repo owner explicitly asked for Electron to produce ready-to-publish
  artifacts through the real release train like every other SDK. `native_electron`
  invokes `.github/workflows/electron-native-package.yml` as a **reusable workflow**
  (`workflow_call`) rather than duplicating its ~400 lines of hard-won native-build logic
  inline; `sdk_electron` downloads the resulting `electron-packaged-tarballs` artifact,
  runs `scripts/release/prepublish_check.py` on every tarball, computes checksums, and
  splits public vs. QHexRT-private before anything reaches `release-flat`. `publish`
  hard-gates on `sdk_electron` succeeding (same tier as `sdk_kotlin`/`sdk_web`/
  `sdk_react_native`) but treats `native_electron`'s own result as advisory, because that
  job's result folds in `native_win_arm64_qhexrt` — a single, personally-owned
  self-hosted NPU runner whose outage should cost only `@runanywhere/electron-qhexrt`
  for that release, not the whole SDK train (`native_win_x64_and_package`, the job that
  actually produces the tarballs, tolerates a failed/skipped QHexRT lane and still packages
  the other five real artifacts). Like every other SDK here, this still does **not**
  `npm publish` anything — it only produces the tarballs as GitHub Release assets
  (public ones) / a workflow artifact (the private QHexRT one) for a human to publish by
  hand, matching the "build automated, publish manual" shape everywhere else.
  **Electron is no longer WIP on a branch** — the old root `AGENTS.md`/`CLAUDE.md`
  "Active issues" section describing `smonga/electron_upgrade` as in-progress is gone
  entirely as of this checkout; `bindings/electron/` is a fully merged, real SDK on
  `main` with its own `AGENTS.md`. Re-check that section is still absent before trusting
  this note — if it has reappeared, something regressed.
  See `thoughts/shared/plans/electron_cicd_staging_url_and_npu_ane_pipeline.md` for the
  full history (this pipeline shipped the placeholder-URL bug three times before
  `electron-native-package.yml` existed).
  **QHexRT public/private boundary — CONFIRMED POLICY, not an open flag**: the repo
  owner explicitly confirmed (2026-08-20) that `@runanywhere/electron-qhexrt` stays
  public on npm intentionally (it already is, and is a real, working precedent worth
  studying before touching QHexRT packaging elsewhere) — the QHexRT-stays-private
  policy enforced everywhere else in this pipeline is specifically about the
  **GitHub-Release-side** asset set (e.g. Android), a different distribution channel.
  This is settled; stop re-flagging it as an unresolved contradiction. Only re-raise it
  if you find evidence the policy has changed.

---

## 0b. NeuRT is a PINNED PREBUILT now — check this before anything else

`native_ios` no longer compiles the private `neurun` repo. It downloads archives that
repo publishes, pinned by tag + SHA-256 in `core/VERSIONS`, the same shape as sherpa-onnx:

```
NEURUN_REPO=RunanywhereAI/neurun      # shared: one repo publishes BOTH engines
NEURT_RELEASE_TAG=v<version>          # per-engine: a release may carry one lane only
NEURT_RAC_ABI_VERSION=9
NEURT_MACOS_ARM64_SHA256=…
NEURT_IOS_ARM64_SHA256=…
NEURT_IOS_ARM64_SIMULATOR_SHA256=…
```

`NEURUN_REPO` is shared because one neurun release carries both engines. The **tags stay
per-engine** on purpose: that repo can cut a release for one lane only, so a given tag may
carry just one engine's assets.

**Run the gate after re-pinning** — it verifies the pins against the release itself, so a
mistyped or locally-computed value fails there instead of mid-build:

```bash
NEURUN_TOKEN="$(gh auth token)" bash scripts/validation/gates/check_engine_prebuilt_pins.sh
```

### Local engine development — there is no source mode

The engine has no `NEURT_ROOT` path any more; nothing here compiles engine source. To iterate
on NeuRT, build a slice in the neurun checkout and point the engine at it — no release, no
tag, no pin edit:

```bash
# in neurun
NeuRT/tools/scripts/package-rac-dist.sh --sdk-root <this repo> --version 0.0.0-dev \
    --slice macos-arm64 --out /tmp/devdist
mkdir -p /tmp/devslice && tar -xzf /tmp/devdist/neurt-macos-arm64-v0.0.0-dev.tar.gz \
    -C /tmp/devslice --strip-components=1

# here
NEURT_PREBUILT_ROOT=/tmp/devslice cmake -S . -B build/dev -G Ninja \
    -DRAC_BUILD_BACKENDS=ON -DRAC_BACKEND_NEURT=ON -DRAC_RUNTIME_COREML=ON
# expect: Mode: PREBUILT (macos-arm64, ABI 9)
```

`NEURT_PREBUILT_ROOT` is a **single-slice** root, which is why
`build-core-xcframework.sh` deliberately ignores it: packaging needs all three slices, so
honouring a single-slice override there would let one staged slice satisfy the guard and
silently package two non-routable stubs. Use an obviously-not-a-release version like
`0.0.0-dev` so a dev slice can never be mistaken for a published one.

**Why this changed, and why it matters to you specifically.** `engines/neurt/CMakeLists.txt`
used to resolve a `NEURT_ROOT` checkout of that private repo and **regex-parse its root
`CMakeLists.txt`** for a source list. Under that arrangement, commons widened
`rac_llm_stream_callback_fn` with `tokens_in_delta`, the pinned neurun commit still passed
4 arguments, and `native_ios` died with *"too few arguments to function call, expected 5,
have 4"* on **v0.20.15, v0.20.16 and v0.20.17**. Every packaging job needs `native_ios`,
so all three shipped **iOS-only — 18 assets where a healthy release has 55+**. That is the
single most expensive failure this runbook exists to prevent, and it came from this seam.

**Before opening the release PR**, confirm the pin is current:

```bash
grep -A5 '^NEURT_REPO' core/VERSIONS
gh release view "$(grep '^NEURT_RELEASE_TAG=' core/VERSIONS | cut -d= -f2)" \
    --repo RunanywhereAI/neurun --json assets --jq '.assets[].name'
```

Expect six assets — three `neurt-<slice>-v<version>.tar.gz` plus their `.sha256` sidecars.

**If the plugin ABI changed this cycle** (`RAC_PLUGIN_API_VERSION` in
`core/include/rac/plugin/rac_plugin_entry.h`), the pinned archives are invalid and
`native_ios` will fail at the download step. Cut a neurun release first — that repo's
`release_sdk_archives` skill is the runbook — then re-pin both `NEURT_RELEASE_TAG` and
`NEURT_RAC_ABI_VERSION` here. The downloader refuses to run if `NEURT_RAC_ABI_VERSION`
disagrees with the header, so this cannot be half-done.

Prove it locally before trusting a tag build:

```bash
NEURUN_TOKEN="$(gh auth token)" bash scripts/build/download-neurt.sh --all
```

That verifies each tarball's SHA-256 **and** that its `RECEIPT.json` names the same ABI
version this repo defines. Then check configure prints `Mode: PREBUILT (<slice>, ABI N)`.
`SOURCE` means a local neurun checkout was picked up (prebuilt is meant to win, so the
download did not land); `SHELL` means the engine is **not routable** and a release built
now would ship an engine that registers, claims Apple availability and serves nothing.

`release.yml` treats the downloader's exit **3** ("no token — degrade to the shell") as
**fatal**. That degrade is right for a fork PR and catastrophic for a release.

### The complete engine matrix — who consumes what, and how

There are only **three fetch points in the entire repo**. Everything else consumes an
sdks artifact, which is why a single fetch fix can repair five SDKs at once — and why a
single missing fetch can silently break several.

```
neurun release (private)
  ├─ native_ios         ──NeuRT x3 slices──►  RABackendNeuRT.xcframework
  │                                              ├─ Swift  (Package.swift binary target)
  │                                              ├─ Flutter / React Native (co-vendored
  │                                              │   in the onnx package's podspec)
  │                                              └─ rcli-macos (stages it, then GREPS
  │                                                  `backends --json` for neurt)
  ├─ native_android     ──QHexRT arm64-v8a──►  one build stages jniLibs into
  │                                              Kotlin + React Native + Flutter
  └─ electron           ──NeuRT macos-arm64 AND QHexRT win-arm64──►  its own natives
```

| target | NeuRT | QHexRT | note |
|---|---|---|---|
| Swift (iOS/macOS) | ✅ xcframework | — | NeuRT is Apple-only |
| Flutter / React Native (Apple) | ✅ xcframework | — | co-vendored in the onnx package |
| Flutter / React Native (Android) | — | ✅ jniLibs | from the same Android build as Kotlin |
| Kotlin (Android) | — | ✅ jniLibs | arm64-v8a only; the only ABI with a Hexagon NPU |
| Electron macOS | ✅ fetches | — | builds its own natives |
| Electron win-arm64 | — | ✅ fetches | |
| rcli macOS | ✅ xcframework | — | **best check in the tree** (below) |
| rcli linux / windows-x64 | — | — | correct: NeuRT is Apple-only, QHexRT is win-arm64 |

**`rcli-macos` is the strongest verification that exists here.** It greps
`backends --json` for `"name":"neurt"` — and a non-routable shell *refuses
registration*, so that grep proves the engine is **routable**, not merely present. Copy
this pattern when adding an engine rather than checking for a file on disk.

**Two silent-failure traps this matrix exists to prevent:**

- **`RAC_BACKEND_<X>=ON` does not mean the engine works.** Without a payload the engine
  builds as a non-routable shell and registration is refused — no build error. Android
  shipped that way for months, and `rcli-macos-release` still sets
  `RAC_BACKEND_NEURT: ON` regardless of whether a payload was fetched.
- **`copy_if_exists` in `build-core-android.sh` silently no-ops** when a lib was never
  built. That is the same guarded-copy pattern that shipped Windows with zero engines for
  several releases. The release now asserts `librunanywhere_qhexrt.so` is really inside
  the arm64-v8a archive.

`scripts/validation/gates/check_engine_prebuilt_pins.sh` asserts all of the above plus
the pins, the ABI, header drift against the receipt, and (with a token) the release
contents. Run it before cutting a release; it is also wired into `pr-build` offline.

### QHexRT is pinned the same way — check it too

The Hexagon-NPU engine crosses the identical boundary, published by the same neurun release:

```
QHEXRT_RELEASE_TAG=v<version>
QHEXRT_ARM64_V8A_SHA256=…      QHEXRT_ARM64_V8A_RECEIPT=…
QHEXRT_WIN_ARM64_SHA256=…      QHEXRT_WIN_ARM64_RECEIPT=…
```

Two pins per ABI, not one: the tarball checksum **and** the payload's own build-receipt
hash. The receipt is the directory name under `engines/qhexrt/prebuilt/versions/`, so
pinning it is what makes the pin describe the bytes rather than trusting the archive's
own claim about itself.

```bash
NEURUN_TOKEN="$(gh auth token)" bash scripts/build/download-qhexrt.sh --abi arm64-v8a
NEURUN_TOKEN="$(gh auth token)" bash scripts/build/download-qhexrt.sh --abi win-arm64
```

**`current` selects ONE ABI at a time.** Both payloads can sit in `versions/` together, but
a build targets one platform — so re-run the downloader when switching between an Android
and a Windows build. The downloader ends by running `validate-qhexrt-prebuilt.py` itself,
so a bad payload fails at the pin rather than mid-build.

**The QHexRT lane in neurun is deliberately non-blocking.** It runs on a single
self-hosted Snapdragon box (QAIRT is licence-gated and exists on no hosted runner). If
that machine is offline, neurun's release publishes the Apple artifacts and **warns** that
no QHexRT payload was produced — and the SDK simply keeps its previously pinned prebuilt.
That is correct behaviour, not a failure: do not block an SDK release on it. Only treat it
as blocking if this release is specifically meant to ship new NPU kernels.

**Do not hand-stage `engines/qhexrt/prebuilt/`.** That was the old flow, and it is how the
Electron win-arm64 lane once pinned a receipt staged months earlier and silently shipped
NPU kernels from an old commit. If the tree looks stale, re-pin and re-download; never
copy a payload in by hand.

---

## 1. Decide the version and open the release PR

Check for an already-open release PR first — don't duplicate work:

```bash
gh pr list --repo RunanywhereAI/runanywhere-sdks --label release:patch --label release:minor
```

(gh ORs multiple `--label` flags into a single AND-filtered query per invocation is not
guaranteed across all gh versions — if unsure, run the two label queries separately:
`--label release:patch` then `--label release:minor`, plus `--label release:major`.)

Pick a patch/minor/major bump based on the changes since the last tag. Then:

```bash
git checkout -b release/v<version>
./scripts/release/sync-versions.sh <version>      # e.g. 0.20.25 (no 'v' needed, either works)
bash scripts/validation/gates/check_release_version_coherence.sh
```

The coherence script may point out generated locks/changelogs that need regenerating
(e.g. package-lock.json version bumps it expects but didn't find, or a missing CHANGELOG
heading for the new version). Fix everything it flags, and add **explicit, human-written
changelog entries** — the gate requires a heading for the new version to exist; it does
not write prose for you.

Open the PR and **apply exactly one `release:patch` or `release:minor` (or `release:major`)
label** — this is required, not optional. Two failure modes to know:

- If you forget the label and push a commit later, the `centralization` job's
  `Release-train version coherence` step fails.
- **Adding the label after the PR is already open does NOT get picked up by the run that
  already executed.** Because `pr-build.yml`'s `centralization` job triggers on
  `labeled`/`unlabeled` PR events, applying the label fires a **new** run of the whole
  job — that new run is what goes green. Don't push an empty commit to "retrigger" it;
  just add/re-add the label (or use `gh pr edit <pr> --add-label release:patch`, and if it
  was already present, remove + re-add to force the event).

---

## 2. Get REAL native-artifact checksums BEFORE merging — dispatch a release candidate

Do not merge on faith that native builds will succeed. `release.yml`'s
`workflow_dispatch` trigger works on **any branch**, including your unmerged release
branch — use it to build a full release candidate first:

```bash
gh workflow run release.yml --ref release/v<version> -f version=<version>
```

Get the run id and watch it:

```bash
gh run list --repo RunanywhereAI/runanywhere-sdks --workflow=release.yml --limit 5
```

**Do not block synchronously waiting on it.** Load the `Monitor` tool (or a background
poll loop) to watch for completion/failure, and keep doing other release prep (changelog
review, CodeRabbit thread triage, branch-protection check) in the meantime. Keep
notifications to real state changes only — don't ping on every intermediate job
completing, only on the run's overall failure or full completion.

### REAL job durations — measured, not guessed. NEVER cancel a job for being "slow".

Measured on the 0.20.25 train (2026-08-21/22). A release train legitimately takes
**4-5 hours** wall-clock when `native_web` has to build.

| Job | Real duration | Notes |
|---|---|---|
| **`native_web`** (release.yml) | **~3h51m** | The long pole, by far. Its `Vendor ONNX Runtime and Sherpa-ONNX WASM archives` step alone is **~71 minutes** — it BUILDS onnxruntime + sherpa to WASM from source; it is not a git clone. Then 4 more WASM builds: CPU core+llamacpp+onnx ~89m, WebGPU llamacpp ~37m, WebGPU onnx+sherpa ~33m. |
| `native_ios` | ~60-75 min | XCFrameworks + MLX. No longer compiles neurun — it downloads the pinned NeuRT archives (see §0b), which is seconds, not minutes. |
| `swift-spm` (pr-build) | **69-85 min** | `Build XCFramework` step is most of it. Measured across 6 consecutive `main` runs (2026-08-21/22): 69, 78, 75, 85, 77, 69. A run sitting at ~78 minutes is **healthy**, not hung — check this row before reaching for cancel. |
| `kotlin-android` (pr-build) | ~40 min | |
| `python-windows` (pr-build) | ~40 min | |
| `electron (windows-2022)` (electron-sdk-ci) | ~40 min | |
| `rcli-windows` | ~30 min | |
| `native_electron / native_win_arm64_qhexrt` | ~28 min | Self-hosted; may sit **queued** for a long time first if the single runner is busy. Queued ≠ hung. |
| `native_electron / native_win_x64_and_package` | ~35-45 min | |
| `wasm` (pr-build) | ~12 min | **Do NOT use this as a proxy for `native_web`.** Totally different scope. |

**The mistake this table exists to prevent**: `pr-build.yml`'s `wasm` job takes ~12
minutes, so a ~50-minute `native_web` "vendor" step looks hung. It is not. On the 0.20.25
train this misread caused two healthy `native_web` jobs to be cancelled at 2h19m and
~55m, wasting ~3 hours and two full candidate builds. Before concluding "hung", check
step-level progress and compare against THIS table:

```bash
gh run view <run-id> --repo RunanywhereAI/runanywhere-sdks --json jobs \
    --jq '.jobs[] | select(.name=="native_web") | {startedAt, steps: [.steps[] | select(.status=="in_progress") | .name]}'
```

### `reuse_native_web_run_id` is the correct way to avoid re-paying that ~4 hours

If a run needs redoing and **nothing under `bindings/web/wasm/`, `engines/`, or `core/`
changed** since a run whose `native_web` succeeded, reuse it instead of rebuilding:

```bash
git diff --stat <good-run-sha> <current-sha>      # prove the scope first
gh workflow run release.yml --ref release/<version> \
    -f version=<version> -f reuse_native_web_run_id=<good-run-id>
```

`native_web` then shows `skipped`, and `sdk_web` + `validate_consumer_web` still run and
pass against the reused artifact — which is also your proof the reuse was valid. Track the
run id that **originally built** it: that is the id you keep citing (see the chaining note
in step 7).

---

## 3. Sync checksums once native_ios finishes

Pre-tag, `gh release download` will not work (there is no release yet) — pull the run's
artifact directly:

```bash
gh run download <candidate-run-id> --repo RunanywhereAI/runanywhere-sdks \
    --name native-ios-macos --dir release-artifacts/native-ios-macos
```

Verify every `.zip` against its `.sha256` sidecar **yourself** before trusting it:

```bash
cd release-artifacts/native-ios-macos
for f in *.zip; do shasum -a 256 -c "${f}.sha256" || echo "MISMATCH: $f"; done
cd -
```

Then sync:

```bash
bindings/swift/scripts/sync-checksums.sh release-artifacts/native-ios-macos
```

**KNOWN FACT — do not treat this as a bug**: `RunAnywhereMLXRuntime` (and occasionally
`RACommons`) are **not byte-reproducible** between rebuilds of identical source. Expect
their checksums to differ from any prior candidate build every single time you rebuild,
even with zero source changes. Only investigate if a checksum for a framework that
historically IS reproducible (e.g. plain XCFrameworks with no Swift codegen step)
suddenly changes.

**Where each checksum actually lives — these are NOT all in one file:**

| Manifest | Carries |
|---|---|
| root `Package.swift` | `RACommons` + the 5 backend XCFrameworks (6 checksums total) |
| nested Flutter `Package.swift` (under `bindings/flutter/`) | same 6 |
| `bindings/flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec` → `mlx_checksums` hash | `RunAnywhereMLXRuntime`, `RunAnywhereMLXMetal`, `RunAnywhereMLXResources` — **only here**, nowhere else |

After `sync-checksums.sh` runs, verify centralization didn't drift and re-run the version
coherence gate locally:

```bash
bash scripts/validation/gates/check_flutter_centralization.sh
bash scripts/validation/gates/check_release_version_coherence.sh
```

Commit and push the checksum-sync commit to the release branch:

```bash
git add Package.swift bindings/flutter/Package.swift \
    bindings/flutter/packages/runanywhere_mlx/ios/runanywhere_mlx.podspec
git commit -m "release: sync v<version> checksums from candidate run <candidate-run-id>"
git push
```

### THIS STEP IS NOT OPTIONAL — skipping it fails `publish` after the tag already exists

**What happens if you skip it** (observed on the 0.20.25 train): every build and package
job goes green, `publish` gets all the way past flatten and the asset-manifest assertion,
then dies at **`Verify built Apple checksums match tagged package contracts`**:

```
mismatch: RACommonsBinary
  Package.swift: 0609dae6...      release zip: 1ae55ae4...
mismatch: RABackendLlamaCPPBinary
  Package.swift: 0597442f...      release zip: 7062f7c8...
>> Done. 8 processed, 0 missing, 4 failed.
ERROR: built Swift archives do not match the immutable tagged manifest
```

Note `8 processed / 4 failed` is really **2 distinct archives counted twice** (root
manifest + Flutter manifest each). On that train `RACommons` and `RABackendLLAMACPP`
drifted while ONNX/Sherpa/NeuRT/MLX/MLXMetal/MLXResources all matched — so "6 of 8 passed"
is a normal-looking partial failure, not evidence of something exotic.

**Recovery once the tag already exists** (this is safe and was done on 0.20.25):

1. Confirm nothing was actually published — a failed `publish` dies *before* creating the
   release, so there is usually nothing to undo:
   ```bash
   gh release view v<version> --repo RunanywhereAI/runanywhere-sdks   # expect "release not found"
   ```
2. Download the **exact artifacts the release will publish** (the candidate run named in
   `publish_from_run_id`), verify each against its sidecar, and sync on a branch off `main`.
3. Merge that branch, then **re-point the tag** at the new commit. `git push origin --delete`
   can hang on flaky networks; the API is more reliable:
   ```bash
   gh api -X DELETE repos/RunanywhereAI/runanywhere-sdks/git/refs/tags/v<version>
   gh api -X POST   repos/RunanywhereAI/runanywhere-sdks/git/refs \
       -f ref="refs/tags/v<version>" -f sha="<new-main-sha>"
   ```
   Only do this while **no release exists and nothing has been published**. If a release
   was already published, do NOT move the tag — cut the next patch version instead.
4. **Creating a tag via the API DOES trigger `release.yml`'s `push` trigger** (unlike a
   `GITHUB_TOKEN` git-push of a tag, which does not). So immediately after re-tagging you
   will have TWO runs: a full rebuild from the `push` event, and your own
   `workflow_dispatch`. Identify by event and cancel the `push` one:
   ```bash
   gh run list --repo RunanywhereAI/runanywhere-sdks --workflow=release.yml --limit 3 \
       --json databaseId,event,headBranch --jq '.[] | "\(.databaseId) \(.event) \(.headBranch)"'
   gh api -X POST repos/RunanywhereAI/runanywhere-sdks/actions/runs/<push-run-id>/cancel
   ```

Cheapest prevention: run `sync-checksums.sh --check <zip_dir>` against the candidate's
artifacts and require **`N processed, 0 missing, 0 failed`** before you merge the release
PR at all.

**Recurred on v0.20.30 and again on v0.20.31** — same `mismatch: RACommonsBinary` /
`mismatch: RACommons` failure, same root cause (step 2's candidate dispatch skipped
entirely both times), fixed the same way both times: compute the real checksum from the
already-built release-artifact zip (`gh run download <failed-run-id> --name
native-ios-macos`), commit it on a fix branch, merge, then move the tag (§10d) to
re-trigger `release.yml`. On v0.20.31 this ALSO surfaced the `RunAnywhereMLXRuntime`
podspec entry as independently stale — `RAC_CHECKSUM_SKIP` means `publish` never checks
it, so it would have shipped broken to Flutter consumers silently. **When fixing this
failure after the fact, check every row of the checksum-location table in step 3, not
only the archive named in the CI error** — the ones `RAC_CHECKSUM_SKIP` exempts are
exactly the ones that won't tell you.

---

## 4. Watch for the "package intentionally doesn't bundle a sibling dep" bug class

This exact release hit a real bug in `bindings/web/scripts/package-sdk.sh`:
`@runanywhere/web-onnx` deliberately does **not** bundle its own `proto-ts` copy (only
`core`/`llamacpp` do — enforced by `bindings/web/scripts/validate_public_packages.py` and
mirrored in `bindings/react-native/scripts/validate_public_packages.py`), but the
packaging script's install-smoke-test (`verify_candidate_install`, around line 165 of
`package-sdk.sh`) never supplied a resolution target for that unbundled dependency, so
`npm install` reached out to the real npm registry for a not-yet-published version and
failed with `ETARGET`.

Fix pattern (already applied, keep it this way): the `onnx` call to
`verify_candidate_install` passes the just-built local `proto-ts` tarball
(`$PROTO_ARCHIVE`, built via `npm pack ../proto-ts`) as an explicit extra install arg —
see lines ~209-233 of `bindings/web/scripts/package-sdk.sh`, where `core` and `llamacpp`
calls omit it (they bundle proto-ts themselves) but `onnx`'s call appends `"$PROTO_ARCHIVE"`.

**Generalize this as a standing check for every release**: grep for the asymmetric
bundling flags before trusting any packaging script —

```bash
grep -n "expects_bundled_proto\|--bundle" \
    bindings/web/scripts/package-sdk.sh bindings/react-native/scripts/package-sdk.sh
```

Whenever a package intentionally does NOT bundle a sibling first-party dependency, its
local pre-publish verification step must supply that dependency some other way (a local
tarball) — the real registry version genuinely does not exist yet at candidate-build
time, and letting `npm`/`yarn` hit the real registry will `ETARGET`.

**Before trusting any packaging script is bug-free, actually run it** against the real
downloaded native artifacts and check the exit code — do not just read the code and
assume it's fine:

```bash
cd bindings/web && ./scripts/package-sdk.sh   # then check $?
cd bindings/react-native && ./scripts/package-sdk.sh
```

### 4b. The two Electron-specific release bugs (both fixed — know the shapes)

The 0.20.25 train was the **first** release to run Electron packaging inside `release.yml`,
and it surfaced two defects that no local test or green PR check could have caught. Both
are fixed; recognize the shapes because they generalize.

**(1) `sync-versions.sh` has a hardcoded package list, and new packages get missed.**
`bindings/electron/packages/neurt/package.json` sat at the previous version while every
sibling moved, because `neurt` was added (electron#734) after that list was last touched.
Symptom: `native_win_x64_and_package` fails with

```
ERROR: npm pack did not produce .../runanywhere-electron-neurt-<version>.tgz
```

— because `npm pack` correctly produced `...-neurt-<OLD-version>.tgz` from the stale
manifest. **Whenever you add a package anywhere, add it to `sync-versions.sh` the same
day.** Cheap pre-flight check that catches the whole class:

```bash
grep -h '"version"' bindings/electron/package.json bindings/electron/packages/*/package.json \
    bindings/electron/native/package.json | sort -u     # expect exactly ONE distinct version
```

**(2) `publish` downloads EVERY artifact, including intermediate hand-off bundles.**
`publish`'s `Download all artifacts` step has no name filter. `electron-packaged-tarballs`
is `native_win_x64_and_package`'s raw output whose only purpose is feeding `sdk_electron`,
which re-uploads the curated public set as `sdk-electron`. Flattening both duplicated all
5 Electron tarballs *and* dragged in the raw bundle's own `proto-ts` copy, which collided
with `sdk_web`'s:

```
::error::flatten collision: release-flat/runanywhere-proto-ts-<v>.tgz already exists
::error::Refusing to publish — 6 filename collision(s) detected during flatten
```

Fixed by pruning that directory in the flatten `find`
(`-type d -name "electron-packaged-tarballs" -prune -o -type f \( ... \)`). **Standing
rule: any new intermediate artifact must be either excluded from the flatten or named so
it cannot collide.** When editing that `find`, test the exact expression against a fake
`release-artifacts/` tree locally first — `-prune -o` + `-print0` is easy to get subtly
wrong and the only other way to find out costs a full release run.

---

## 5. Resolve CodeRabbit (or any bot) review findings properly

Do not resolve a review thread without a real, evidence-backed reply. Steps:

1. Fetch unresolved threads via GraphQL:

```bash
gh api graphql -f query='
query($owner:String!, $repo:String!, $pr:Int!) {
  repository(owner:$owner, name:$repo) {
    pullRequest(number:$pr) {
      reviewThreads(first:100) {
        nodes { id isResolved comments(first:10) { nodes { id databaseId body } } }
      }
    }
  }
}' -f owner=RunanywhereAI -f repo=runanywhere-sdks -F pr=<pr-number>
```

2. For each unresolved thread, reply via REST with `in_reply_to` set to the comment's
   `databaseId` (not the GraphQL node id), citing concrete evidence — a real run id,
   a real checksum, a real commit SHA, not "looks fine":

```bash
gh api -X POST repos/RunanywhereAI/runanywhere-sdks/pulls/<pr-number>/comments \
    -f body="Verified against candidate run <run-id>: RunAnywhereMLXRuntime checksum
matches release-artifacts/native-ios-macos/RunAnywhereMLXRuntime-ios-v<version>.zip.sha256.
See commit <sha>." \
    -F in_reply_to=<comment-database-id>
```

3. Only then resolve, via GraphQL mutation on the thread id from step 1:

```bash
gh api graphql -f query='
mutation($threadId:ID!) { resolveReviewThread(input:{threadId:$threadId}) { thread { isResolved } } }
' -f threadId=<thread-node-id>
```

---

## 6. Merge

Before merging, verify:

```bash
gh pr view <pr-number> --repo RunanywhereAI/runanywhere-sdks --json mergeable,reviewDecision
```

Zero unresolved review threads (re-check the GraphQL query from step 5 — it should return
none with `isResolved: false`), and `mergeable == "MERGEABLE"`.

Confirm bypass eligibility before relying on `--admin`:

```bash
gh api repos/RunanywhereAI/runanywhere-sdks/branches/main/protection \
    --jq '.required_pull_request_reviews.bypass_pull_request_allowances'
gh api user --jq .login
```

If your login appears in that allowance list (users, or a team/app you belong to):

```bash
gh pr merge <pr-number> --repo RunanywhereAI/runanywhere-sdks --squash --admin
```

If not on the list, **stop** — ask a human to approve or merge instead of forcing it.
`--admin` is a legitimate configured bypass only for allow-listed identities; do not use
it to route around review for anyone else.

---

## 7. GOTCHA — cancel the auto-tag-dispatched rebuild, dispatch a publish-only run instead

The moment the PR merges, `auto-tag.yml` runs, pushes the `v<version>` tag, and **itself**
dispatches a brand-new full `release.yml` run at that tag (see orientation section — plain
tag pushes via `GITHUB_TOKEN` don't auto-trigger, so the workflow does it explicitly).
This is redundant — you already have a fully green, checksum-verified candidate from step
2-3 — and wasteful, because Apple/MLX bytes will drift again for zero benefit (see the
non-reproducibility fact in step 3).

**Cancel it immediately, before it burns real compute** (ideally within the first minute
or two, before native_ios starts real work):

```bash
gh run list --repo RunanywhereAI/runanywhere-sdks --workflow=release.yml --limit 5
gh api -X POST repos/RunanywhereAI/runanywhere-sdks/actions/runs/<auto-triggered-run-id>/cancel
```

Then dispatch a **publish-only** run that reuses your already-verified candidate's exact
bytes instead of rebuilding:

```bash
gh workflow run release.yml --ref v<version> \
    -f version=<version> \
    -f publish_from_run_id=<candidate-run-id>
```

**CRITICAL SUB-GOTCHA**: if your candidate run in step 2 itself passed
`reuse_native_web_run_id=<X>` to skip rebuilding WASM (a packaging-only re-release), that
candidate run **never uploaded its own copy of the `native-web` artifact** — it was
skipped. `publish_from_run_id` alone will then fail during the release-manifest assertion
with `"Missing or empty Web WASM payload"`, because the publish job's artifact-download
step only pulls `reuse_native_web_run_id`'s artifact when that input is passed to *this*
dispatch too (see `.github/workflows/release.yml` around the "Download reused Web natives"
step — it is gated on `inputs.reuse_native_web_run_id != ''`, independent of
`publish_from_run_id`). You must **also** pass the same original run id:

```bash
gh workflow run release.yml --ref v<version> \
    -f version=<version> \
    -f publish_from_run_id=<candidate-run-id> \
    -f reuse_native_web_run_id=<X>
```

This chains forward across releases: whichever run **originally** built `native_web` is
the run you keep citing at every subsequent `reuse_native_web_run_id`, not the most recent
run that merely borrowed it from an earlier one. Track that original run id explicitly if
you're doing back-to-back packaging-only releases.

---

## 8. Verify the draft release's asset set

The publish job only creates a **draft** GitHub Release (`softprops/action-gh-release`,
`draft: true`) with built assets attached — it does not touch npm/Maven/pub.dev at all
(grep `release.yml` for `npm publish`, `mavenCentral`, `pub publish` — none exist there).

Expected asset count for a full, non-Windows-focused release: **~65 assets** —

- 9 Apple archives (iOS/macOS XCFrameworks: RACommons + 5 backends + MLX runtime/Metal/
  resources + CoreML/NeuRT)
- 3 Android RACommons zips (arm64-v8a, armeabi-v7a, x86_64)
- 1 Linux RACommons tar.gz
- 1 Windows RACommons zip (preserved as an asset, advisory — see step 9)
- 1 Web WASM tar.gz (`RACommons-web-v<version>.tar.gz`)
- 3 rcli tarballs (macOS arm64, Linux x86_64, Windows x86_64 — macOS may also have a
  notarized `.dmg` if Developer ID/notary secrets are configured; this is soft-skipped
  otherwise, not a failure)
- 1 Kotlin Maven repo zip
- 8 npm tarballs (proto-ts, web core, web-llamacpp, web-onnx, RN core, RN llamacpp, RN mlx,
  RN onnx)
- 5 Electron npm tarballs (`runanywhere-electron-<v>.tgz` core, `-llamacpp`, `-onnx`,
  `-sherpa`, `-neurt`) — added by `sdk_electron`; each has its own `.sha256` sidecar
  counted separately below. **`electron-qhexrt` is deliberately excluded** — it still
  gets built and packaged, but only as the `sdk-electron-qhexrt-private` workflow
  artifact (not a release asset); download it separately for a manual `npm publish`.
- 1 `MANIFEST.txt`
- **explicitly ZERO** `qhexrt`-named files (the manifest assertion step hard-fails the run
  if it finds any — confirm the run actually reached the publish job and didn't die there)

Every asset above except `MANIFEST.txt` has a `.sha256` sidecar, which is itself a
separate asset. **v0.20.25 landed at exactly 65 assets** — use that as the concrete
baseline rather than re-deriving the arithmetic.

Cross-check every checksum's `.sha256` sidecar against what got committed to
`Package.swift` / the flutter `Package.swift` / the MLX podspec in step 3 — they must
match byte for byte, because this run's artifacts are exactly what step 10 (sdk-publish)
ships to real consumers.

```bash
gh run view <publish-run-id> --repo RunanywhereAI/runanywhere-sdks --json jobs \
    --jq '.jobs[] | {name, conclusion}'

# Asset count + the Electron set + the qhexrt-leak assertion, in three commands:
gh release view v<version> --repo RunanywhereAI/runanywhere-sdks --json assets --jq '.assets|length'
gh release view v<version> --repo RunanywhereAI/runanywhere-sdks --json assets \
    --jq '[.assets[].name | select(startswith("runanywhere-electron"))] | sort'
gh release view v<version> --repo RunanywhereAI/runanywhere-sdks --json assets \
    --jq '[.assets[].name | select(test("qhexrt";"i"))]'          # MUST be []
```

### Prove the artifacts are real — don't trust green checkmarks

A green `publish` only proves the assertions ran. To prove the bytes are right, run the
repo's own fail-closed gate against the **published** tarballs. This is the single highest
-value verification in the whole runbook and it takes about a minute:

```bash
gh release download v<version> --repo RunanywhereAI/runanywhere-sdks \
    -p 'runanywhere-electron*.tgz' -D /tmp/verify
python3 scripts/validation/gates/check_plugin_natives.py --expect-version <version> \
    $(for t in /tmp/verify/*.tgz; do printf -- '--tarball %s ' "$t"; done)
```

Expect `All N check(s) passed: plugin natives are routable and no staging-URL placeholder
was found.` On v0.20.25 that was **20 checks** across 5 tarballs, asserting three separate
things per binary: the real `STAGING_BASE_URL` is baked in (no `YOUR_STAGING_BASE_URL`
placeholder), `rac_commons` embeds the right version string, and each backend is actually
**routable** (real op tables — `g_llamacpp_ops`, `g_sherpa_stt_ops`, `g_neurt_llm_ops`,
etc.), which is what distinguishes a real plugin from a same-sized shell.

Sanity-check the shipped layout too — a tarball missing a platform is a silent regression:

| Package | Expected `prebuilds/` |
|---|---|
| `@runanywhere/electron` | `darwin-arm64` + `win32-x64` + `win32-arm64` |
| `-llamacpp`, `-onnx`, `-sherpa` | `darwin-arm64` + `win32-x64` |
| `-neurt` | `darwin-arm64` only (Apple Neural Engine) |
| `-qhexrt` (private artifact) | `win32-arm64` only (Hexagon NPU) |

---

## 9. Windows handling — build/preserve only, never auto-publish

`native_windows` and `native_rcli_windows` run and their outputs are **preserved** as
release assets (proving the binaries build), but nothing Windows-specific is published to
any package registry as part of the standard flow unless a human explicitly asks for it —
that's a deliberate, separate decision, not an oversight.

For anything that needs actual execution on Windows (smoke-testing the native Windows
build, or Electron's Windows packaging), do not assume a macOS cross-build proves
Windows correctness — SSH to the real Windows box. The team keeps a **Windows ARM64
machine reachable over SSH**; its hostname, user, key, and mesh-VPN node name are
operator-specific and deliberately not recorded in this repo — read the Windows/ARM64
host entry out of the operator's `~/.ssh/config` and use that alias. If there is no such
entry, the box is not configured for you: say so and ask, rather than guessing.

```bash
WIN_BOX=<the ssh alias from ~/.ssh/config>
# Ask the mesh-VPN client whether the node is up FIRST (e.g. `tailscale status`,
# matching on that host entry's HostName) — never just try SSH and retry on timeout.
ssh -o ConnectTimeout=8 "$WIN_BOX" "whoami"
```

If the VPN reports the node offline/asleep, **that's not a config problem** — ask the
user to wake the box; don't debug SSH config against a machine that's simply off.

---

## 10. Publish the draft, then hand off

Once the draft's asset set is verified complete and correct (step 8):

```bash
gh release edit v<version> --repo RunanywhereAI/runanywhere-sdks --draft=false --latest
```

This is the point where SwiftPM's `from: "<version>"` resolution and the download URLs
baked into `Package.swift` start actually working for real external consumers — draft
release assets are not publicly downloadable, so nothing before this line is
externally live.

**Hand off to the `sdk-publish` skill** for the actual npm / Maven Central / pub.dev /
SwiftPM-distribution-repo publishing steps. This skill's job ends here.

---

## 10b. MANDATORY, and it turns `main` RED until you do it — cut runanywhere-swift

The moment `v<version>` exists in this repo, `check_swift_dist_repo_sync.sh` (run by
`pr-build.yml`'s `centralization` job) **fails on every PR and every push to `main`**:

```
[FAIL] runanywhere-swift has no 0.20.25 tag (latest: 0.20.24)
       v0.20.25 is published here, so 'from: "0.20.25"' is broken for every
       SwiftPM consumer of https://github.com/RunanywhereAI/runanywhere-swift.git
```

This is **by design**, not a bug, and it is the #1 reason a release looks "not green"
after everything else succeeded. Do not go hunting for a code defect — cut the repo:

```bash
git clone https://github.com/RunanywhereAI/runanywhere-swift.git /tmp/ra-swift
bindings/swift/scripts/sync-dist-repo.sh --zips <zip_dir> --tag /tmp/ra-swift
# verify BEFORE pushing (content check passes locally; the tag check needs the push)
RUNANYWHERE_SWIFT_DIST_REPO=/tmp/ra-swift \
    bash scripts/validation/gates/check_swift_dist_repo_sync.sh
git -C /tmp/ra-swift push origin main --follow-tags
bash scripts/validation/gates/check_swift_dist_repo_sync.sh    # now [OK]
```

Gotchas found doing this on 0.20.25:

- `--check` **cannot be combined** with `--zips`/`--commit`/`--tag` (hard error). Run a
  bare `--check <repo>` first to preview, then the real invocation separately.
- `--check` legitimately reports `ERROR: distribution repo is out of sync` before you
  sync — that's the preview telling you what it will change (expect the `sdkVersion` bump,
  ~3 changed files, `0 added / 0 removed`). Non-zero exit there is not a failure.
- The script **never pushes**; `--tag` only creates the tag locally. The dist repo tag has
  **no `v` prefix** (`0.20.25`, not `v0.20.25`) while the monorepo tag does.
- Running the gate locally right after `--tag` still shows `[FAIL] ... has no <version>
  tag` while simultaneously showing `[OK] ... checkout matches: all 6 checksums`. That is
  expected: the content check reads your local checkout, the tag check queries the real
  remote. It clears the moment you push.
- It chains into `sync-checksums.sh`, so run it **after** step 3's checksums are committed,
  or the dist manifest gets stale hashes.

---

## 10c. Windows + self-hosted-runner traps (read before debugging a red Windows job)

These all cost a full CI cycle. The unifying fact:

> The self-hosted runner service executes as `NT AUTHORITY\NETWORK SERVICE`, which has its
> own PATH **and** its own NTFS permissions. Anything you verify over SSH on that box tells
> you nothing about what the job can do. `native_win_arm64_qhexrt` already carries a long
> comment about this — read it before inventing a fix, and keep it in sync with neurun's
> equivalent lane, which runs on the *same machine*.

**Environment**

- **`bash: command not found`** — Git for Windows puts `Git\cmd` (git.exe) on PATH but not
  `Git\bin` (bash.exe). `actions/checkout` still works because it calls git.exe directly,
  which makes this look unrelated to runner setup.
- **`pwsh` does not exist on that box** — Windows PowerShell 5.1 only. Use
  `shell: powershell`.
- **`gh` is not installed on that box, and must not be assumed anywhere.** A QHexRT
  download died on `gh: command not found`. The fix is deliberately *not* to install it:
  every fetch of a private release asset now goes through
  `fetch_release_asset()` in `scripts/build/_release_asset.sh`, which uses `curl` + the
  REST API. `curl` ships with Windows, macOS and every Linux image we use, so this is one
  code path everywhere instead of a per-runner provisioning step. If you add a new
  consumer of a private asset, source that helper — do not reach for `gh`.
  Note the helper matches the asset name **exactly**: a prefix match picks the `.sha256`
  sidecar (its name starts with the tarball's), and you get a 65-byte "archive" that fails
  much later with a confusing error.
- **Tool availability is the single most common failure class on this runner** — `bash`,
  `python3`, `ninja`, `gh`, GNU `tar` and NDK `.exe` suffixes have each broken a lane
  once. When a self-hosted job fails, check "does this tool exist as spelled" before
  reading any logic.
- **`ln -s` under Git-Bash COPIES the directory** unless `MSYS=winsymlinks:nativestrict`.
  It does not fail, so the result looks like real content and whatever validates a
  "must be a symlink" invariant rejects a payload that was actually fine. Never use shell
  `ln -s` on this box — go through `scripts/build/_selection.py`.
- **Windows selects with a JUNCTION, not a symlink, and that is deliberate.** The runner
  service account cannot create symlinks (below), but a junction is the same kind of
  reparse point to a directory and needs no privilege. Two traps when reading that code:
  `Path.is_symlink()` returns **False** for a junction (`stat.S_ISLNK` is true only for
  `IO_REPARSE_TAG_SYMLINK`) — use `_selection.is_selection()`; and a junction stores an
  **absolute** target, so compare `_selection.read_target()`, which normalizes both
  platforms back to `versions/<receipt>`. `Path.is_junction` is 3.12+ and that box runs
  3.10, so the `lstat`/`st_reparse_tag` fallback is the live path there.

**A green PR does not mean the win-arm64 lane passed**

`native_win_arm64_qhexrt` is gated `if: github.event_name != 'pull_request'` — never run
on a PR, fork or not, because a `pull_request` run would execute PR-controlled
`npm install` scripts on a persistent personally-owned runner. It therefore only runs on
`push` / `workflow_dispatch` / `workflow_call`. Consequences to plan around:

- **Check the paths filter covers what you changed.** `electron-native-package.yml` watches
  `scripts/build/**` *because* of this — a fix to `download-qhexrt.sh` used to trigger no
  push run at all, so it would merge with the lane it was written for never having run.
  If you add a new dependency of that workflow, add it to both paths lists.
- To exercise the lane on an unmerged branch, `gh workflow run electron-native-package.yml
  --ref <branch>` — `workflow_dispatch` has no paths filter and satisfies the event gate.
- **Do not push while that dispatch run is in flight.** The concurrency group is
  `${{ github.workflow }}-${{ github.ref }}` with `cancel-in-progress: true` and does not
  distinguish event types, so a push cancels the dispatch run you are waiting on.
- Read the step list, not just the job conclusion: `skipped` on this job looks nothing like
  `success` but sorts the same way in a rollup summary.
- **ASCII only inside a PowerShell `run:` block.** The runner writes it to a `.ps1` with no
  BOM and PS 5.1 decodes CP1252, so a UTF-8 em-dash ends in `0x94` — a smart closing quote —
  and the script dies with `The string is missing the terminator` on a line that is
  perfectly balanced. In a YAML *comment* it is harmless.
- **The runner service caches its environment at start.** After changing machine PATH,
  `Restart-Service` or the next job still sees the old one.
- `cmake`/`python`/`ninja` may be pip-installed under a user profile and invisible to the
  service account; add them to `$GITHUB_PATH` with a **concrete** path (a wildcard
  `Get-ChildItem` there silently finds nothing, because access-denied on enumeration is
  swallowed by `-ErrorAction SilentlyContinue`).

**Batch scripts (`core/scripts/windows/*.bat`)** — both of these emit the identical, useless
`... was unexpected at this time.` **after** an apparently successful download, which sends
you looking in the wrong place entirely:

- **`::` is a label and is ILLEGAL inside a `( )` block** — use `rem` there.
- **Unescaped parens inside an `echo` close the block early.**
  `echo Decompressing (7-Zip)...` is fine at top level and fatal once nested; needs
  `^(` / `^)`.

Both were introduced purely by moving existing, working lines *into* an `if`/`else` block.

**`7z` is not guaranteed.** It ships on GitHub's windows runners but is not part of a stock
Windows install. `download-sherpa-onnx.bat` now falls back to bsdtar, which handles
`.tar.bz2` directly (measured: 2.5 s, exit 0, on Windows 11 ARM64).

**CMake on Windows**

- **Visual Studio is a MULTI-CONFIG generator**: `CMAKE_BUILD_TYPE` is a no-op; `--config
  Release` at *build* time is what selects Release. Getting this wrong silently ships Debug.
- **An Android cross-build needs `-G Ninja` explicitly.** Windows' default generator is
  Visual Studio, which cannot drive the NDK toolchain file — and macOS/Linux pick a working
  default, so an omitted generator breaks *only* on Windows.

## 10d. Re-tagging: verify the tag actually moved

`git tag -d <tag> -q` is **not valid** (`-q` is not a flag there). Guarded with `|| true`
it fails silently, and the next `git push origin <tag>` pushes the **stale** tag. This has
already started a release building the wrong commit. Always verify:

```bash
[ "$(git rev-parse v<version>^{commit})" = "$(git rev-parse main)" ] \
  && echo "tag OK" || echo "STALE — delete on BOTH sides and re-tag"
```

Deleting locally is not enough; `git push origin :refs/tags/<tag>` removes the remote one.
And if a release run already started on the stale tag, cancel it before re-tagging or you
will race two publishes at the same tag.

## 11. Non-blocking loose ends — note, don't chase

- **`python-linux` no longer exists** — it was removed from `pr-build.yml` on 2026-08-22.
  It had a chronic ~90-minute hang that tripped its own `timeout-minutes: 90` on nearly
  every run (on both a two-version matrix and a single pinned 3.12), surfacing as a red X
  or a whole-run "cancelled" for a job that was never a required status check and whose
  ecosystem (PyPI) `release.yml` does not touch at all. `python-macos` and `python-windows`
  still cover the wheel build/install/test flow. Trade-off accepted knowingly: **no CI job
  now verifies the `requires-python = ">=3.9"` floor** declared in
  `bindings/python/pyproject.toml`. If Python 3.9 support starts mattering, add one cheap
  single-version job rather than resurrecting the old matrix.
- Confirm branch protection still has **no required status checks** (so a stray red X
  cannot silently block a merge):
  ```bash
  gh api repos/RunanywhereAI/runanywhere-sdks/branches/main/protection --jq '.required_status_checks'
  gh api repos/RunanywhereAI/runanywhere-sdks/rulesets --jq '.[] | {id, name, enforcement}'
  ```
  As of 2026-08-22 the active `main` ruleset enforces `pull_request`,
  `required_linear_history`, `copilot_code_review`, `deletion`, `non_fast_forward` — and
  **zero** required status checks. Merge gating is 2 approvals + code-owner review, with
  `bypass_pull_request_allowances` covering sanchitmonga22, shubhammalhotra28, Siddhesh2377.
- `native_win_arm64_qhexrt` / `native_win_x64_and_package` showing **`skipping`** on any
  `pull_request` event is intentional security gating (see the Electron section in step 0),
  not a failure. They run on `push`/`workflow_dispatch`.
- Transient GitHub-infra failures do happen and look alarming: on the 0.20.25 train
  `native_ios` died once with `fatal: unable to access 'https://github.com/nlohmann/json.git/':
  Could not resolve host: github.com` during a CMake `FetchContent` clone. Re-run the failed
  job (`gh run rerun <id> --failed`) — but note you **cannot** re-run failed jobs while the
  run is still in progress ("This workflow is already running"); wait for the run to finish
  first. Distinguish this from a slow-but-healthy job using the duration table in step 2.
- `@runanywhere/electron-qhexrt`'s npm exposure (step 0) is a confirmed, settled policy
  decision, not an open item — no need to re-flag it every run anymore.
