---
name: sdk-test-starters
description: Run a REAL end-to-end inference smoke test (model download + load + generate, with visible output) on every RunAnywhere starter app — iOS, macOS/Swift, Android, Web, Electron — after a runanywhere-sdks release. Build success alone is never sufficient evidence.
---
# SDK Test Starters

Post-release validation runbook for the five RunAnywhere SDK consumer apps. This
skill exists because "it built" has been reported as "tested" before, and that is
not evidence of anything except that the compiler ran.

## 0. The evidence bar (applies to every app, no exceptions)

For each app you must produce, and be able to state explicitly:

1. **Version proof** — print/log the actual resolved SDK version from inside the
   running app (a startup log line, a version screen, an `swift package show-dependencies`
   / `./gradlew dependencies` / `npm ls @runanywhere/...` output, etc). Never assume
   a version bump "took" just because you edited a manifest.
2. **Real model acquired** — a real (small) model downloaded fresh, or confirmed
   already cached, by the app itself (not a file you hand-placed unless that IS the
   app's supported flow).
3. **Load** — the model actually loads (watch for a load-succeeded log/state, not
   just "no crash").
4. **One real inference call** — LLM `generate()` is almost always the easiest
   modality to drive; use it unless another modality is genuinely less work for
   that specific app.
5. **Visible output** — capture the actual generated text (or audio/image) and
   quote it in your report. "It responded" is not enough — show what it said.
6. **Logs reviewed** — read the console/log stream for errors and warnings and
   explicitly explain any that appear. Do not silently drop a stack trace because
   the app "still produced output."

Reporting an app as tested from a build/compile success alone is a skill violation.
If you could not get past build, that is a BLOCKED report (see §8), not a PASS.

## 1. Locating each app's real local checkout

This machine accumulates many differently-named copies of the same repos over time
(worktrees, experiment clones, old branches, scratch dirs). **Never trust a
directory name.** Before touching anything in a candidate directory:

```bash
git remote get-url origin          # must be https://github.com/RunanywhereAI/<repo>.git
git status --short --branch        # what branch, what's dirty, is it someone else's WIP?
```

As of this writing, the known-good local checkouts for this user are here (verify
this each time — do not hardcode it further than "check this location first"):

```
~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-ios       -> RunanywhereAI/runanywhere-ios.git
~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-android   -> RunanywhereAI/runanywhere-android.git
~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-web       -> RunanywhereAI/runanywhere-web.git
~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-electron  -> RunanywhereAI/runanywhere-electron.git
```

The macOS/Swift case has no separate consumer repo — see §4, it lives inside
`~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks` (confirm with
`git remote get-url origin` there too — this machine also has stray full-monorepo
clones elsewhere, e.g. under `~/development/hard/ambient/`, that are NOT the one to
use unless you've verified it's the intended checkout).

These starter checkouts are commonly sitting on a feature branch, not `main` — e.g.
at last check `runanywhere-ios` and `runanywhere-android` were on
`add-gemma4-qwen3.6-qwen3.8-models` and `runanywhere-web` on `add-supertonic-3-tts`.
That is fine to test FROM, but say so in your report, and do not `git checkout` away
from a branch that has uncommitted work you didn't create — if `git status --short`
shows dirty files you don't recognize, stop and ask rather than stashing/resetting.

If genuinely unsure which directory is real, `git clone` a fresh one into the
scratchpad rather than guessing — a wrong guess wastes far more time than a clone.

## 2. Cross-repo facts this skill assumes

- SDK version SoT: `core/VERSION` in `runanywhere-sdks`, bumped everywhere by
  `scripts/release/sync-versions.sh <version>`.
- Release publish is `.github/workflows/release.yml` (dispatch or `v*.*.*` tag).
- **Never** treat a build success against `RUNANYWHERE_USE_LOCAL_NATIVES=1` (or any
  monorepo-local staged artifact) as proof the *public* release works — see §4.
- QHexRT/QNN material must never appear in a public artifact — release.yml
  hard-fails on it. If anything you're testing surfaces a QHexRT asset in a public
  package, stop and flag it, don't route around it.

## 3. iOS — `runanywhere-ios`

SDK pin lives in `Package.swift`:

```swift
.package(url: "https://github.com/RunanywhereAI/runanywhere-swift.git", from: "0.20.19")
```

This only resolves once `runanywhere-swift` (the generated Swift-only SPM
distribution repo — see `~/.claude/skills/sdk-publish/SKILL.md` §4) is
actually tagged at the target version. Steps:

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-ios
# bump the `from:` version in Package.swift to the target release, then:
swift package update            # or open in Xcode and let it resolve
./scripts/build_and_run_ios_sample.sh simulator "iPhone 16 Pro"
```

`./scripts/verify.sh` is the CI-equivalent gate: it resolves the package remotely
and runs a full `xcodebuild` against the iOS Simulator — use it to prove the
resolve is clean (it fails if `Package.resolved` ends up dirty, i.e. the committed
pin was stale). `./scripts/smoke.sh` is a fast, non-compiling grep-based check —
it does NOT count as evidence for this skill's bar, only `build_and_run` +
watching real output does.

Drive one real `generate()` call through the app UI (or the equivalent debug
action if the sample exposes one) against a small downloaded model, then watch the
runtime log stream for the version line, the model download/load, the generation,
and any errors:

```bash
log stream --predicate 'subsystem CONTAINS "com.runanywhere"' --info --debug
```

Most loggers use `com.runanywhere.RunAnywhereAI`; a few use plain
`com.runanywhere`; the SDK logs under its own subsystem — the `CONTAINS` match
covers all of them. On a physical device use `idevicesyslog | grep "com.runanywhere"`
instead.

## 4. macOS/Swift — no consumer repo, use the in-tree example

There is no `runanywhere-macos` consumer repo. Use the in-tree example, inside
`~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks`:

- `bindings/swift/example/` — a minimal SwiftPM example app/executable.

The CLI is no longer in this repo; it moved to `RunanywhereAI/RCLI`, so it is not a
second in-monorepo option any more.

**The critical gotcha**: the repo's own `Package.swift` is fail-closed toward the
*real published release* — it resolves the remote `binaryTargets` unless you
explicitly opt into locally staged XCFrameworks with
`RUNANYWHERE_USE_LOCAL_NATIVES=1`. Every doc/script example in this repo sets that
env var (because local dev wants fast iteration against in-progress binaries) —
but that means copy-pasting those examples verbatim tests your LOCAL staged build,
not the actual public release artifact. To prove the published release works:

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks/bindings/swift/example
# DO NOT set RUNANYWHERE_USE_LOCAL_NATIVES — leave it unset so Package.swift
# resolves the real remote release binaries for the target version.
swift build
swift run runanywhere-minimal "Name three colours."
```

If the example was previously built/run with the env var set, `swift build` may
reuse a stale resolve — run `swift package reset` (or delete `.build/`) first if
you're not sure which mode the last resolve used.

For rcli instead (also validates the real published core):

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks
rcli models download qwen3          # ~639MB, small enough for a quick smoke test
rcli llm generate --model qwen3 "Reply with exactly: RCLI WORKS" --reasoning off
```

`rcli models list --all` shows the rest of the built-in catalog
(`whisper-tiny`, `smolvlm2`, `piper`, …) if LLM generate isn't the right modality
for what you're verifying.

## 5. Android — `runanywhere-android`

Version pin: `gradle/libs.versions.toml` has ONE shared catalog entry:

```toml
runanywhere = "0.20.19"
...
runanywhere-sdk      = { group = "io.github.sanchitmonga22", name = "runanywhere-sdk",              version.ref = "runanywhere" }
runanywhere-llamacpp = { group = "io.github.sanchitmonga22", name = "runanywhere-llamacpp",          version.ref = "runanywhere" }
runanywhere-onnx     = { group = "io.github.sanchitmonga22", name = "runanywhere-onnx",               version.ref = "runanywhere" }
runanywhere-qhexrt   = { group = "io.github.sanchitmonga22", name = "runanywhere-qhexrt-android",     version.ref = "runanywhere" }
```

**CRITICAL — do not bump this block as one unit.** `runanywhere-qhexrt-android` is
permanently frozen at whatever version it was last published at before being
excluded from the public Maven train; by policy it can never move forward via
public Maven again. Verify the actual frozen version FRESH every time (do not
trust a remembered number — it doesn't change, but don't skip the check):

```bash
curl -s https://repo1.maven.org/maven2/io/github/sanchitmonga22/runanywhere-qhexrt-android/maven-metadata.xml
```

The other three artifacts (`runanywhere-sdk`, `-llamacpp`, `-onnx`) CAN and should
move to the new release version. This means the single `runanywhere` catalog ref
must be **split into two entries** — one at the new version for sdk/llamacpp/onnx,
one pinned to the frozen qhexrt version — not bumped as a block.

**Before trusting a mixed pin works**: verify `RAC_PLUGIN_API_VERSION` (the
plugin ABI version constant in the C++ core, exposed identically to Kotlin) is
unchanged between the old public SDK version and the new one. If it changed, mixing
a newer sdk/llamacpp/onnx with the frozen qhexrt version is NOT safe — this is a
human decision (needs either an ABI-compat shim or dropping qhexrt from this build),
not something to force through.

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-android
./gradlew :app:assembleDebug
./gradlew :app:installDebug        # installs to a connected emulator/device
adb logcat | grep -i runanywhere   # or a more specific tag if the app uses one
```

Launch the app, drive one real `generate()` call against a small downloaded model
(the app's own model picker/download flow), confirm the resolved SDK version is
logged, and review logcat for errors before reporting a PASS.

## 6. Web — `runanywhere-web`

`package.json` has 4 `@runanywhere/*` deps pinned with a caret range:

```json
"@runanywhere/proto-ts":    "^0.20.19",
"@runanywhere/web":         "^0.20.19",
"@runanywhere/web-llamacpp":"^0.20.19",
"@runanywhere/web-onnx":    "^0.20.19"
```

Bump all 4 to the new version, then:

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-web
npm install
npm run build
npm run dev      # vite --host localhost --port 3000 --strictPort
```

The dev/preview server is what supplies COOP/COEP headers required for
`SharedArrayBuffer` — WASM inference will silently fail (or refuse to init
threads) without them, so don't swap in a bare static file server.

`~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks/bindings/web/AGENTS.md`
has the authoritative Validation section (its own heading is `## Validation`) —
full checklist:

1. Fresh browser context.
2. Example app served with COOP/COEP headers.
3. Model download.
4. Model load.
5. Real browser inference for the target modality.
6. Logs/screenshots reviewed.

Its "Required release gates" (run before browser validation) from the same repo:

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/runanywhere-sdks/bindings/web
npm run typecheck && npm run lint && npm run test && npm run build
npm run test:browser
npm run test:browser:release
cd example && npm run typecheck && npm run build
```

Static gates passing is not the smoke test — you still need an actual browser
watching real inference happen against the starter app. Prefer a real browser
automation tool (`claude-in-chrome` MCP tools, or Playwright — the maintained
suites under `bindings/web/tests/browser/` already use `playwright.config.ts`)
over curling the served page: WASM inference genuinely needs a browser JS engine.
Load the served starter app, download/load a small model, trigger generate, and
read the actual rendered output text plus the browser console — do not infer
success from an HTTP 200 on the page load.

## 7. Electron — `runanywhere-electron` (SPECIAL CASE)

**Do not assume a fresh SDK publish is available for this app.** Electron's own
npm packages (`@runanywhere/electron`, `-llamacpp`, `-onnx`, `-sherpa`, `-qhexrt`,
`-neurt`) are on a SEPARATE, manual-publish pipeline — NOT part of `release.yml`
(grep confirms zero mentions of these package names there). This separation is a
**confirmed, deliberate** repo-owner decision, not a gap. Check
`~/.claude/skills/sdk-publish/SKILL.md` §6 before assuming anything moved.
Electron is **no longer WIP on a branch** — the old "in-progress on
`smonga/electron_upgrade`" note is gone from the root `AGENTS.md`/`CLAUDE.md`
entirely as of this checkout; `bindings/electron/` is a fully merged SDK on `main`.
As of `fix/electron-cicd-staging-url-npu-ane`,
`.github/workflows/electron-native-package.yml` builds every backend for real and
packages every tarball — but still does not publish; verify against a live run
rather than assuming build automation status either way.

Test the starter against whatever version it is CURRENTLY pinned to unless a human
has explicitly confirmed a newer Electron publish is ready and intended:

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-electron
cat package.json | grep '@runanywhere/electron'   # confirm current pin before touching it
```

**`@runanywhere/electron-qhexrt` being public on npm is a CONFIRMED, settled
policy decision** (repo owner, 2026-08-20), not a contradiction to flag — it
contains real Hexagon NPU binaries (`libQnnHtpV81Skel.so`, `QnnHtp*.dll`,
`rac_commons.dll`, `runanywhere_qhexrt.dll`) on purpose. The QHexRT-stays-private
policy enforced elsewhere in this repo family is specifically about the
GitHub-Release-side asset set (Android etc.), a different channel. Only re-raise
this if you find evidence the policy changed.

Two layers to actually exercise, do not conflate them:

**(a) Cross-platform Electron JS + macOS native addon** — buildable and testable
locally on this Mac right now:

```bash
cd ~/development/ODLM/MONOREPOOO/Qualcomm/starters/runanywhere-electron
npm install
npm run build   # or the app's documented dev/start script — check package.json scripts
npm start        # or equivalent — launch the actual Electron app
```

Drive one real `generate()` call in the running app, watch its console/log output
for the resolved SDK version, model download, load, and generation, and read any
errors rather than ignoring them.

**(b) Genuine Windows-native behavior** — a macOS build proves NOTHING here
regardless of how clean the cross-platform code looks; the native addon and any
Windows-only DLLs must be exercised on real Windows.

The team keeps a **Windows ARM64 test machine reachable over SSH**. Its hostname,
user, key, and VPN/mesh node name are operator-specific and deliberately not
recorded in this repo — read them out of the operator's own `~/.ssh/config` (look
for the Windows/ARM64 host entry) and use that alias below wherever `$WIN_BOX`
appears. If no such entry exists, the box is not configured for you: say so and
ask, rather than guessing at a hostname.

```bash
WIN_BOX=<the ssh alias from ~/.ssh/config>
```

**Always check reachability first, never just try SSH and retry on timeout.** The
box lives on a private mesh VPN and is frequently asleep, so start by asking the
VPN client whether the node is up (e.g. `tailscale status`, matching on the host
entry's `HostName`) rather than opening a connection.

If the node reports `offline, last seen ...`, the box is asleep/powered off.
**A connection timeout here means "device asleep," not "config is wrong."** Tell
the human and ask them to wake it; do not loop retrying SSH. Only once the node
shows a live/idle state, confirm with:

```bash
ssh -o ConnectTimeout=8 "$WIN_BOX" "whoami"
```

Then, with the repo already cloned there:

```bash
ssh "$WIN_BOX" "cd <repo-path-on-that-box>; git pull; npm install; npm run build"
# then run whatever launches the Windows Electron build and drive a real generate call
scp "$WIN_BOX":<remote-log-or-artifact-path> ./local-copy   # pull back evidence to inspect
```

Do not claim Windows-specific validation happened unless you actually obtained a
shell on that box and ran something real there — a clean macOS build is not
substitute evidence.

**`node_modules/electron` on this box silently tracks whichever arch last ran `npm
install`, not which Node launches the test.** The x64 (llamacpp/onnx/sherpa) and
arm64 (QHexRT) lanes share ONE `runanywhere-electron` checkout/`node_modules` tree.
Prepending an x64 Node to `PATH` and running `npx playwright test` does NOT make
Electron itself x64 — `require('electron')` always resolves the single installed
`node_modules/electron/dist/electron.exe`, and whichever arch that binary actually
is determines which `prebuilds/win32-<arch>/` directory the running app looks in,
regardless of `scripts/use-sdk.mjs local`'s staging (which itself is arch-aware
based on the *launching* Node, so it can correctly report "staged win32-x64" while
the process that will actually run is arm64 — a silent mismatch). Verify with:
`powershell -Command "$p=[IO.File]::ReadAllBytes('...\electron.exe'); $peOff=
[BitConverter]::ToInt32($p,60); [BitConverter]::ToUInt16($p,$peOff+4)"` — `43620`
(`0xAA64`) is ARM64, `34404` (`0x8664`) is x64. If it's the wrong arch (e.g. a prior
session's `npm install` for the other lane silently overwrote it), a genuine re-test
of the other lane needs a FULLY SEPARATE checkout/`node_modules` tree installed
under the matching-arch Node — don't assume PATH-prepending alone is sufficient, and
don't trust `use-sdk.mjs status`'s "platform: win32-x64" output as proof the running
Electron process is actually x64.

**NPU hardware is a scarce, single-owner resource — serialize, never parallelize.**
This box has ONE physical Hexagon NPU. `engines/qhexrt/qhexrt_session.cpp`'s
`session_open()` has a load-bearing comment on this exact failure mode: the HTP
exposes a small number of protection domains with a per-PD context ceiling, so a
*second* concurrent model load fails with `RAC_ERROR_BACKEND_INIT_FAILED`
("Backend initialization failed") — a fast (tens-of-ms), generic-looking failure
that is easy to mistake for a real regression. Confirmed once tonight: two agents
each independently exercising QHexRT on this box at the same time produced exactly
this failure. Before concluding a QHexRT test genuinely failed, confirm nothing
else (another agent, a leftover Electron process, a stuck previous test run) is
also holding an NPU session open on this box — check for lingering `electron.exe`/
`node.exe` processes from a prior run and kill them if orphaned, and never launch
two NPU-touching verification passes concurrently on this machine.

**"Backend initialization failed" has (at least) three distinct root causes —
don't stop at PD exhaustion.** Confirmed on 2026-08-17 after PD-exhaustion and
staleness were both ruled out (fresh rebuild, source-identical prebuilt, no other
process holding a session): the *actual* bug was two compounding issues, both now
fixed/documented —
1. **Real source bug, fixed in PR #733**: `qhexrt_session.cpp`'s `runtime_acquire()`
   called `qhx_runtime_create(nullptr, nullptr)` on every non-Android platform,
   trusting the OS default DLL search order to find `QnnHtp.dll`/`QnnSystem.dll`.
   On Windows that order never includes a dynamically-loaded sibling plugin's own
   directory (`LOAD_WITH_ALTERED_SEARCH_PATH`, used to load `runanywhere_qhexrt.dll`
   itself, only widens the search for *that* load call, not later `LoadLibrary`
   calls made by code already running inside it) — so the QNN DLLs were invisible
   even sitting right next to the plugin. Fixed by resolving the plugin's own
   module directory (`GetModuleHandleExA`+`GetModuleFileNameA`) and passing
   explicit paths, mirroring Android's existing `ADSP_LIBRARY_PATH` resolution in
   the same file.
2. **Operational staleness, NOT a script bug**: even after (1), the QNN runtime
   DLLs actually staged into `@runanywhere/electron-qhexrt`'s
   `prebuilds/win32-arm64` (`node_modules/.../electron-qhexrt/prebuilds/win32-arm64/`)
   were from an old QAIRT build (~2.45.x vintage, Dec 2025 files) while the box's
   installed QAIRT was 2.48.0.260626 — a real ABI-relevant version mismatch.
   `bindings/electron/scripts/bundle-native.ts`'s `stageQnnRuntime()` just mirrors
   whatever `RA_QNN_RUNTIME_DIR` points at with **no version check** — it's
   correct-as-written; someone had pointed it at a stale neurun-side
   `qairt-runtime-248`-named folder that was never refreshed. Fix: rebuild that
   flat dir from the CURRENT QAIRT SDK's `lib/aarch64-windows-msvc/` (host DLLs:
   `QnnHtp.dll`, `QnnHtpPrepare.dll`, `QnnHtpV81Stub.dll`,
   `QnnHtpV81CalculatorStub.dll`, `QnnSystem.dll`) + `lib/hexagon-v81/unsigned/`
   (DSP side: `libQnnHtpV81Skel.so`, `libqnnhtpv81.cat`), point
   `RA_QNN_RUNTIME_DIR` at it, and re-run
   `npm run bundle:native -- --package=qhexrt` from `bindings/electron/`.
   **The already-published `@runanywhere/electron-qhexrt` npm package (as of
   0.20.24) almost certainly ships the same stale DLLs** — this needs a
   human decision (republish/patch) before claiming the published package works
   on Windows NPU, separate from the source fix in PR #733.
3. **PD exhaustion** (the pre-existing entry above) remains real and still applies
   when two sessions genuinely contend for the one physical NPU — but it is not
   the only explanation, and the log line to actually check first is the native
   one: subscribe via `window.runanywhere.logging.records()` (after
   `logging.setDebugMode(true)`) or add a temporary main-process log capture —
   `app.process().stdout`/`stderr` do NOT carry it, because the addon runs in a
   separate `utilityProcess.fork()` host, not the Electron main process, and
   `RAC_LOG` is not an env var the logger reads (it does nothing). The generic
   `[QHexRT] qhx_runtime_create failed (QNN libs unavailable?)` vs.
   `qhx_model_load failed: ... N NPU model(s) already resident` log text is what
   actually distinguishes cause (1)/(2) from cause (3) — always get that line
   before diagnosing further.

**Workflow gotcha:** if you orchestrate this via the Workflow tool, its agent()
calls do NOT reliably block-wait on a long-running remote build the way a direct
poll loop does — observed once tonight where a workflow's own agents spawned an
internal Monitor/poller for the build log and then returned immediately,
reporting "still waiting," which let the whole workflow finish with nothing
actually verified. For "wait N tens-of-minutes for a real native build to
finish," use the top-level Monitor tool yourself (a shell poll loop over SSH
checking for a terminal BUILD_SUCCEEDED/BUILD_FAILED marker line) rather than
delegating the wait itself into a workflow agent's own judgment.

### The Windows box's actual layout, and why it's more than a cross-platform check

**This is a Hexagon-NPU-equipped Windows machine** (Snapdragon-class ARM Windows
device, Copilot+ PC), not just a generic x86 Windows box. That makes it the one
place a QHexRT/Hexagon backend build+test can produce real device-only truth for
Windows — matching the parent workspace's own "x86 is a simulator, device-only
truth" rule (see the top-level `Qualcomm/CLAUDE.md` and `QHexRT/CLAUDE.md`). Don't
treat this box as merely a Windows Electron smoke-test target; it's the only real
Hexagon NPU test rig reachable for this platform.

Per the user (2026-08-17), under `~/Downloads/RunAnywhere/` on that box there are
three sibling repo checkouts at the same level — **verify each on connect, don't
assume paths without checking, since this is relayed secondhand and may have
drifted**:
- `runanywhere-sdks` — this monorepo, presumably already cloned; `git fetch && git
  log -1 origin/main` to see how far behind it is before doing anything.
- `runanywhere-electron` — the Electron starter app (same repo as
  `RunanywhereAI/runanywhere-electron` elsewhere in this skill).
- a third repo referred to verbally as "the neuron/new-run inference engine for the
  Hexagon NPU" — almost certainly **`neurun`**, the QHexRT/NeuRT split-out repo
  (see memory: "neurun component split merged — QHexRT/ + NeuRT/ + shared/, root is
  a closed 20-entry set enforced by a test"). Confirm the actual directory name and
  remote (`git remote get-url origin`) on connect rather than guessing from the
  transcription.

**Full task on this box (per explicit user instruction, not just a smoke test):**
1. `git pull` (or fetch+fast-forward) all three repos to latest `main`.
2. Rebuild the QHexRT/Hexagon NPU backend from `neurun` against this device's real
   Hexagon NPU — this is the one environment where that build+run is meaningful
   proof, not a simulator claim.
3. Bump Electron's native dependencies to their latest versions — llama.cpp,
   sherpa-onnx, ONNX Runtime, and whatever else `bindings/electron` pins — across
   the repos involved. Treat this as a real dependency-bump task (check for
   breaking API changes, don't just edit a version string and assume it builds).
4. Update the model catalog for **all 5 starter apps across all 4 consumer repos**
   (iOS, Android, Web, Electron — plus whatever the "5th app" split means for
   macOS/Swift, see the rest of this skill) so the catalog is consistent everywhere,
   not just on this Windows box.
5. Run a real end-to-end inference pass on this box specifically (not just build
   success) — both the general Electron/llama.cpp path AND the Hexagon NPU path via
   `neurun`/QHexRT.
6. Open PRs for whatever changed, in each affected repo. Do not merge them —
   the user explicitly said they'll review.

This is real engineering work (native dependency bumps + an NPU backend rebuild),
not a mechanical version-string edit — expect it to take real time and to
genuinely need `QHexRT/CLAUDE.md` and `neurun`'s own docs read in full before
touching that backend, per the parent workspace's own instructions.

## 8. Reporting

For each of the 5 apps (iOS, macOS/Swift, Android, Web, Electron), state exactly
one of these two outcomes — never blur them:

- **FULLY VERIFIED** — with concrete evidence: the version string actually
  resolved/logged, the model used, and the actual output produced (quote it).
- **BLOCKED** — with the exact concrete reason, e.g.: the Windows ARM64 box's
  mesh-VPN node is offline; Android emulator unavailable in this environment; App Store /
  notarization credential missing; `runanywhere-swift` not yet tagged at target
  version so `swift package update` can't resolve; electron-qhexrt policy conflict
  needs a human call before proceeding further.

A clearly reported partial/blocked result is far more valuable than an optimistic
summary that overstates what was actually observed. If you hit the known Electron
qhexrt npm-publish policy conflict (§7), call it out in the report even if it
wasn't the thing blocking your specific test — it's a standing issue every release
night should re-surface until a human resolves it.

## Credentials referenced but never printed by this skill

These exist and are checked for presence only — never print their values:

- Maven Central: `mavenCentral.username` / `mavenCentral.password`,
  `signing.gnupg.keyName` / `signing.gnupg.passphrase` in `~/.gradle/gradle.properties`.
- GPG signing key `CC377A9928C7BB18` — check with
  `gpg --list-secret-keys --keyid-format LONG`.
- macOS notarization profile `runanywhere-notary` — check with
  `xcrun notarytool history --keychain-profile runanywhere-notary`; codesign
  identity `Developer ID Application: RunAnywhere, Inc` — check with
  `security find-identity -v -p codesigning`.
- npm — `npm whoami` should already show a logged-in user.

None of the app-level smoke tests in this skill require touching these directly;
they matter only if a test path requires a fresh distro-repo publish (e.g.
`runanywhere-swift` not yet tagged) — that's a separate concern of the
`sdk-publish` skill, not this one.
