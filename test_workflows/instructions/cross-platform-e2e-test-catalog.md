# Cross-Platform E2E Test Catalog

**Authoritative manual/automated checklist** for RunAnywhere SDK example apps across five SDKs and seven runtime lanes. Use with **Mobile MCP** (Android/iOS simulators) and **cursor-ide-browser MCP** (Web).

**Source of truth for ambiguous behavior:** iOS Swift example (`examples/ios/RunAnywhereAI/`).

**Related docs:**

- Run contract: `common/run_contract.md`
- Fixed inputs: `common/modality_matrix.md`
- Report schema: `common/report_schema.md`
- Per-lane quick starts: `kotlin/README.md`, `swift/README.md`, `flutter/`, `react_native/`, `web/README.md`
- Log scripts: `../scripts/README.md`, `../scripts/web/capture-web-logs.md`, `logging/capture_logs.sh`
- Log layout: `../logs/README.md` → `logs/runs/<run-id>/lanes/`
- MCP runbook: `mcp-agent-runbook.md`

---

## Table of contents

1. [Overview](#1-overview)
2. [Shared reference](#2-shared-reference)
3. [Session lifecycle & edge cases](#3-session-lifecycle--edge-cases)
4. [Android Kotlin](#4-android-kotlin-lane-01_android_kotlin)
5. [iOS Swift](#5-ios-swift-lane-02_ios_swift)
6. [Flutter (Android + iOS)](#6-flutter-android--ios-lanes-05--06)
7. [React Native (Android + iOS)](#7-react-native-android--ios-lanes-03--04)
8. [Web](#8-web-lane-07_web)
9. [runanywhere-commons (C++)](#9-runanywhere-commons-c)
10. [Appendix: grep patterns](#10-appendix-grep-patterns)
11. [Appendix: feature parity matrix](#11-appendix-feature-parity-matrix)

---

## 1. Overview

### Purpose

This catalog expands **21 test cases (TC-01 … TC-21)** into step-by-step UI actions, log expectations, and pass/fail criteria for every SDK example app. It is intended for:

- Human testers clicking through simulators/devices
- Cursor agents using **mobile-mcp** or **cursor-ide-browser** with this file as a checklist
- Post-run reports under `test_workflows/logs/runs/<run-id>/lanes/` (matrix: `runs/<run-id>/matrix/`)

### How to use with MCP agents

See **`mcp-agent-runbook.md`** for execution order, MCP tool mapping, and browser lock rules.

1. **Create a run ID:** `RUN_ID=$(test_workflows/scripts/run-manage.sh new <suffix>)` then `export RAC_RUN_ID="$RUN_ID"`
2. **Init lane + start log capture before launch** (mandatory). Logs go to `test_workflows/logs/runs/<run-id>/lanes/<NN>_<lane>/`.
3. **Fresh install** per `common/run_contract.md` (uninstall → build → install → launch).
4. Execute TCs **in order** where dependencies exist (TC-01 → TC-02 → TC-04 → TC-05; edge cases after TC-02/15).
5. After each TC: `snapshot` logs, screenshot `screenshots/tcNN_<step>.png`.
6. **Stop** log capture; write `modality_report.md` (and `REPORT.md` for seven-lane runs) using `common/report_schema.md`.

### Mandatory log capture workflow

Every platform run **must** follow this pattern:

```bash
RUN_ID=$(test_workflows/scripts/run-manage.sh new kotlin-android)
export RAC_RUN_ID="$RUN_ID"
test_workflows/scripts/session-manage.sh lane kotlin
test_workflows/scripts/kotlin/capture-kotlin-logs.sh start "$RUN_ID"
# ... MCP / manual test steps; snapshot after each TC ...
test_workflows/scripts/kotlin/capture-kotlin-logs.sh snapshot "$RUN_ID" tc05_inference
test_workflows/scripts/kotlin/capture-kotlin-logs.sh stop "$RUN_ID"
# Analyzer → test_workflows/logs/runs/$RUN_ID/lanes/01_kotlin_android/modality_report.md
```

| Platform | Script (under `test_workflows/scripts/`) |
| --- | --- |
| Kotlin | `kotlin/capture-kotlin-logs.sh` |
| Swift | `swift/capture-swift-logs.sh` |
| React Native | `react-native/capture-react-native-logs.sh` (+ Metro → `logs/metro.log`) |
| Flutter | `flutter/capture-flutter-logs.sh` |
| Web | `web/capture-web-logs.sh` + `web/capture-web-logs.md` |
| Commons | `commons/capture-commons-test.sh run <run-id>` |

CLI: `run-manage.sh`, `session-manage.sh`. Layout: [`../logs/README.md`](../logs/README.md).

### Log capture expectations

| Lane slug | Log directory |
| --- | --- |
| `01_kotlin_android` | `logs/runs/<run-id>/lanes/01_kotlin_android/logs/` |
| `02_swift_ios` | `…/02_swift_ios/logs/` |
| `03_react_native_android` | `…/03_react_native_android/logs/` |
| `04_react_native_ios` | `…/04_react_native_ios/logs/` |
| `05_flutter_android` | `…/05_flutter_android/logs/` |
| `06_flutter_ios` | `…/06_flutter_ios/logs/` |
| `07_web` | `…/07_web/logs/` |
| `08_commons_cpp` | `…/08_commons_cpp/logs/` |

### Report output paths

```text
test_workflows/logs/<run-id>/
  REPORT.md                    # human summary
  modality_report.md           # optional modality table
  modality_results.tsv         # machine-readable
  <lane>/screenshots/
  <lane>/logs/
  <lane>/actions.jsonl         # schema v2 lanes
```

---

## 2. Shared reference

### Recommended models (all platforms unless noted)

| Role | Display name | Model ID |
| --- | --- | --- |
| LLM (download test) | SmolLM2 360M Q8_0 | `smollm2-360m-q8_0` |
| STT | Sherpa Whisper Tiny (ONNX) | `sherpa-onnx-whisper-tiny.en` |
| TTS (on-device) | Piper TTS (US English - Medium) | `vits-piper-en_US-lessac-medium` |
| TTS (system, Android) | System TTS | `system-tts` |
| VAD | Silero VAD | `silero-vad` |
| VLM (mobile) | SmolVLM 500M Instruct | `smolvlm-500m-instruct-q8_0` |
| VLM (Web) | SmolVLM2 256M Video Instruct Q8_0 | `smolvlm2-256m-video-instruct-q8_0` |
| RAG embedding | All MiniLM L6 v2 (Embedding) | `all-minilm-l6-v2` |

### Fixed test inputs (`common/modality_matrix.md`)

| Modality | Input |
| --- | --- |
| LLM | `In one sentence, explain what RunAnywhere does.` |
| STT phrase | `RunAnywhere runs models on device.` |
| TTS text | `RunAnywhere runs privately on your device.` |
| VLM question | `What is visible in this image?` |
| RAG ingest | `RunAnywhere keeps model lifecycle logic in C++.` |
| RAG query | `Where should model lifecycle logic live?` |
| Voice agent | `Tell me one benefit of on-device AI.` |

### RAG fixture document (create locally)

Create `test_workflows/fixtures/rag-sample.txt`:

```text
RunAnywhere keeps model lifecycle logic in C++.
The SDK registers backends such as LlamaCPP and ONNX/Sherpa on device.
```

**Android push (per app — same device path, different package for uninstall only):**

```bash
# Shared fixture path on device (pick from Downloads in file picker)
adb push test_workflows/fixtures/rag-sample.txt /sdcard/Download/rag-sample.txt

# Verify (optional)
adb shell ls -la /sdcard/Download/rag-sample.txt
```

| App | Android package | RAG UI navigation |
| --- | --- | --- |
| Kotlin | `com.runanywhere.runanywhereai.debug` | **More** → **Document Q&A** |
| Flutter | `com.runanywhere.runanywhere_ai` | **Chat** → **Document Q&A** (toolbar) |
| React Native | `com.runanywhereaI` | Tab **RAG** |

**iOS Simulator:** drag file into Files app or `xcrun simctl addmedia booted` / open via Document Q&A file picker.

**Web:** use **Docs** tab file picker.

### TC applicability summary

| TC | Kotlin | Swift | Flutter | RN | Web |
| --- | --- | --- | --- | --- | --- |
| TC-01–TC-16 | ✓ | ✓ | ✓ | ✓ | ✓ |
| TC-17 Solutions | Deferred | Deferred | Deferred | Deferred | Deferred |
| TC-18 Validation | N/A | N/A | N/A | ✓ tab | N/A |
| TC-19 Benchmarks | ✓ More | ✓ Settings | N/A | N/A | N/A |
| TC-20 Settings | ✓ | ✓ | ✓ | ✓ | ✓ |
| TC-21 LoRA | ✓ More | ✓ Chat | N/A | Validation only | N/A |

**Test case counts (executable, excluding deferred/N/A):**

| Platform | Applicable TCs |
| --- | ---: |
| Android Kotlin | 19 (+ TC-17 deferred, TC-18 N/A) |
| iOS Swift | 19 (+ TC-17 deferred, TC-18 N/A) |
| Flutter Android / iOS | 18 each (+ TC-17 deferred, TC-18/19/21 N/A) |
| RN Android / iOS | 19 each (+ TC-17 deferred; TC-21 via Validation) |
| Web | 16 (+ TC-17 deferred, TC-09/18/19/21 N/A, TC-06 VAD no dedicated UI) |

### Edge-case & lifecycle TC index

| TC ID | Title | Kotlin | Swift | Flutter | RN | Web |
| --- | --- | --- | --- | --- | --- | --- |
| TC-03a | Force-kill / swipe away persistence | ✓ | ✓ | ✓ | ✓ | ✓ (tab close) |
| TC-03b | Reboot persistence | ✓ opt | ✓ opt | ✓ opt | ✓ opt | N/A |
| TC-03c | Uninstall → reinstall (models gone) | ✓ | ✓ | ✓ | ✓ | ✓ (clear origin) |
| TC-03d | Clear app data vs uninstall | ✓ | ✓* | ✓ | ✓ | ✓ (site data) |
| TC-Storage-OPFS | OPFS / browser storage UI | N/A | N/A | N/A | N/A | ✓ |
| TC-Download-interrupt | Cancel mid-download | ✓† | ✓† | ✓† | ✓† | ✓† |
| TC-Load-OOM | Load failure (no crash loop) | ✓ | ✓ | ✓ | ✓ | ✓ |
| TC-Inference-cancel | Stop mid-stream | ✓‡ | ✓‡ | ✓‡ | ✓‡ | ✓ |

\* iOS: delete app from home screen (no Settings “clear data”).
† Use model download cancel if UI exposes it; LoRA cancel on Kotlin; otherwise mark **LIMITED**.
‡ Chat stop may be absent; use **Vision** **Stop** (Android VLM) or Web **Clear** during stream; document **LIMITED** if no cancel control.

---

## 3. Session lifecycle & edge cases

Run after **TC-02** (model downloaded) unless noted. Always capture logs + screenshots at each step.

### Package / bundle IDs (uninstall & clear data)

| App | Android package (debug) | iOS bundle ID | Uninstall (Android) | Uninstall (iOS sim) |
| --- | --- | --- | --- | --- |
| Kotlin | `com.runanywhere.runanywhereai.debug` | — | `adb uninstall com.runanywhere.runanywhereai.debug` | — |
| Swift | — | `com.runanywhere.RunAnywhere` | — | `xcrun simctl uninstall booted com.runanywhere.RunAnywhere` |
| Flutter | `com.runanywhere.runanywhere_ai` | `com.runanywhere.runanywhereAi` | `adb uninstall com.runanywhere.runanywhere_ai` | `xcrun simctl uninstall booted com.runanywhere.runanywhereAi` |
| React Native | `com.runanywhereaI` | `com.runanywhere.runanywhereai` | `adb uninstall com.runanywhereaI` | `xcrun simctl uninstall booted com.runanywhere.runanywhereai` |
| Web | — | — | Clear origin storage (see TC-03c) | — |

### TC-03a — Model persists after force-kill / swipe away

**Preconditions:** TC-02 pass; **SmolLM2 360M Q8_0** downloaded.

| Platform | Steps | Pass | Fail | Log grep |
| --- | --- | --- | --- | --- |
| Kotlin Android | `adb shell am force-stop com.runanywhere.runanywhereai.debug`; relaunch; **Chat** → **Select Model** | Row still downloaded; no full re-download | Shows not downloaded; re-downloads entire artifact | `discoverDownloadedModels` / registry hydrate; no fatal |
| Swift iOS | Swipe app away in app switcher; relaunch | **Ready** / **Use** without re-download | Stuck **Loading available models...** | `Model registry refreshed` |
| Flutter | Force-stop (Android) or swipe away (iOS); relaunch | Model **Ready** in sheet | Empty registry | `Models registered` / local path |
| RN | Force-stop / swipe; relaunch | **Downloaded** on row | **Download** again | Metro: no registry wipe error |
| Web | Close tab; reopen `http://127.0.0.1:5173` (normal refresh) | Model still downloaded | Must re-download | `[RunAnywhere] hydrated` … `from OPFS` |

### TC-03b — Model persists after device reboot (OPTIONAL)

**Platforms:** Kotlin, Swift, Flutter, RN on **physical device or emulator** only. Mark **SKIPPED** on CI simulators if reboot impractical.

**Steps:**

1. Complete TC-02; note model downloaded.
2. Reboot device: `adb reboot` (Android) or restart simulator / device (iOS).
3. After boot, launch app (do **not** uninstall).
4. Verify model still downloaded in **Chat** model sheet / **Storage**.

**Pass:** Downloaded state survives reboot.
**Fail:** Registry empty after reboot.
**Logs:** Post-boot init without full catalog re-fetch of multi-GB artifact.

### TC-03c — Uninstall → reinstall (models must be GONE)

**Expected:** All on-device model files removed; user must re-download via UI.

**Steps:**

1. After TC-02, note **Storage** / downloaded size > 0.
2. Uninstall app (commands in table above). Web: clear all site data for origin.
3. Reinstall fresh build; launch (TC-01).
4. Open **Chat** → model sheet / **Storage**.

**Pass:** **SmolLM2 360M Q8_0** shows **not downloaded**; storage near zero.
**Fail:** Model still **Downloaded** / **Ready** without new download (stale storage).
**Logs:** Fresh init; no `hydrated N models` with N>0 on first launch (Web).

### TC-03d — Clear app data vs uninstall

**Expected difference:**

| Action | App binary | Downloaded models | App preferences |
| --- | --- | --- | --- |
| **Uninstall** (TC-03c) | Removed | **Gone** | **Gone** |
| **Clear data** (Android) | Kept | **Gone** (app sandbox wiped) | **Gone** |
| **Clear data** (iOS) | N/A — use delete app | — | — |
| **Web clear site data** | N/A | **Gone** (OPFS/IDB) | **Gone** |

**Android clear data:**

```bash
adb shell pm clear com.runanywhere.runanywhereai.debug   # Kotlin
adb shell pm clear com.runanywhere.runanywhere_ai        # Flutter
adb shell pm clear com.runanywhereaI                     # RN
```

**Steps:** After TC-02 → `pm clear` (or Web: clear storage only, keep tab open) → relaunch → check **Storage** + model sheet.

**Pass:** Models gone; app may show onboarding (**Welcome!** / **Get Started**) again.
**Fail:** Models still listed with non-zero sizes after clear.

### TC-16 — Storage screen after lifecycle events

**Preconditions:** TC-15 baseline (models listed with sizes).

**Steps (run sub-steps after each lifecycle event):**

1. **Baseline:** Open storage UI (see platform table below); screenshot file list / **Downloaded Models** / free space.
2. **After TC-03a (force-kill):** Relaunch → storage UI unchanged (same models, sizes ± small delta).
3. **After TC-03d (clear data):** Storage empty or zero models.
4. **After TC-03c (reinstall):** Storage empty on first launch.

| Platform | Navigation | Key UI strings |
| --- | --- | --- |
| Kotlin | **Settings** → **Storage Overview**, **Downloaded Models** | Section titles from `SettingsScreen.kt` |
| Swift | **More** → **Storage** | **Storage Overview**, **Downloaded Models** |
| Flutter | **Settings** (storage sections) | Mirror Swift |
| RN | **Settings** → **Storage Overview**, **Model Catalog** | |
| Web | Tab **Storage** | **Browser Storage (OPFS)**, **Registered Models**, **Manage Models** |

**Pass:** UI matches expected state for each lifecycle phase.
**Fail:** **Downloaded Models** non-empty after clear/uninstall.
**Logs:** `getStorageInfo` / storage delete paths; Web OPFS listing.

### TC-Storage-OPFS — Web OPFS persistence

**Platforms:** Web only.

**Preconditions:** COOP/COEP active (SharedArrayBuffer available); TC-02 complete.

**Steps:**

1. Download **SmolLM2 360M Q8_0**; confirm **Storage** tab shows OPFS usage > 0.
2. **Hard refresh:** Cmd+Shift+R (or browser MCP reload with cache bypass).
3. Confirm model still downloaded; console: `[RunAnywhere] hydrated` … `from OPFS`.
4. Close tab completely; open new tab to same origin.
5. Repeat step 3.

**Pass:** Models survive hard refresh and tab close.
**Fail:** SAB/OPFS errors, empty registry after refresh.
**Fail signals:** Console `SharedArrayBuffer`, isolation headers missing.

### TC-Download-interrupt — Cancel mid-download

**Preconditions:** Fresh or partial download state; network available.

**Steps:**

1. Start download of **SmolLM2 360M Q8_0** (or smaller STT model for faster test).
2. At 10–50% progress, tap **Cancel** / close icon on download row if exposed (Kotlin **LoRA Adapters** has **Cancel download**; main LLM sheet may lack cancel — try **Settings** cancel if present).
3. Observe UI: progress stops; row returns to not-downloaded or partial state per app.
4. Start download again.

**Pass:** No crash; second download completes OR app shows clear error (no infinite spinner).
**Fail:** ANR, stuck progress, corrupt “downloaded” state without files.
**Logs:** `download` / cancel / checksum; no `FATAL EXCEPTION`.

Mark **LIMITED** if platform has no download cancel in LLM sheet (document screenshot).

### TC-Load-OOM — Load failure handling

**Preconditions:** Large model downloaded (or use biggest available on low-RAM emulator).

**Steps:**

1. Download model; attempt **Use** / **Load** on low-memory emulator or after loading other heavy models.
2. If load fails, observe error UI (**Model Load Error** dialog / toast).

**Pass:** Single error surface; app remains usable; no crash loop on relaunch.
**Fail:** Repeated native crash on launch, OOM kill loop (`AndroidRuntime`, jetsam on iOS).
**Logs:** `Model load failed` / OOM; **no** repeated crash stack on every launch without user action.

### TC-Inference-cancel — Stop generation mid-stream

**Preconditions:** TC-04 pass; streaming model loaded. Configure the
streaming run with `max_tokens >= 2000` (raise the slider/config in app
settings, or override via tools/dev menu) so generation is guaranteed to
run long enough for a mid-stream cancel — short caps (e.g. default 256)
finish before the tap fires and produce false PASS.

**Steps by platform:**

| Platform | Control | Action |
| --- | --- | --- |
| Kotlin Android | **Vision** → **Vision Chat** → **Stop** (during VLM stream) OR Chat if stop exposed | Tap **Stop** mid-stream |
| Swift iOS | Chat / VLM if stop visible during `isGenerating` | Stop generation |
| Flutter | **Vision** VLM stream if stop in UI | Cancel stream |
| RN | **Vision** / VLM cancel if exposed | Stop stream |
| Web **Chat** | Toolbar **Clear** during generation | Clears and calls `cancelGeneration` |

1. Send the long-form cancel prompt:
   `Write a comprehensive multi-section essay (target ~2000 tokens) about on-device AI, covering hardware, latency, privacy, model formats, energy use, on-device fine-tuning, and future trends. Provide concrete examples in every section.`
   (the prompt is intentionally long so token streaming runs for several
   seconds before the user gets a chance to tap **Stop**.)
2. While tokens stream, trigger stop/clear.
3. Verify stream stops within ~5s; UI not frozen.

**Pass:** Generation stops; no zombie streaming; app responsive. Token
count at cancel should be well below the configured cap (proof that the
cancel — not the natural EOS — ended the stream).
**Fail:** Infinite spinner, crash, tokens continue after cancel,
generation reaches `max_tokens` cap (cancel never actually exercised).
**Logs:** `cancelGeneration` / stream end / no unhandled native fault.

Mark **LIMITED** on Chat if only VLM/Web cancel tested — note in report.

---

## 4. Android Kotlin (lane `01_android_kotlin`)

**Example path:** `examples/android/RunAnywhereAI/`
**Package (debug):** `com.runanywhere.runanywhereai.debug`
**Navigation:** Bottom tabs — **Chat**, **Vision**, **Voice**, **More**, **Settings**

### Prerequisites

```bash
# From repo root
scripts/validation/e2e/run_global_source_checks.sh
scripts/validation/commons/run_commons_proto_checks.sh

cd examples/android/RunAnywhereAI
./gradlew :app:assembleDebug -Prunanywhere.useLocalNatives=false
# APK: app/build/outputs/apk/debug/app-debug.apk

adb devices -l
adb uninstall com.runanywhere.runanywhereai.debug || true
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell pm grant com.runanywhere.runanywhereai.debug android.permission.RECORD_AUDIO
adb shell pm grant com.runanywhere.runanywhereai.debug android.permission.CAMERA
```

### Log capture

```bash
RUN_ID="kotlin-${RUN_ID:-manual}"
test_workflows/scripts/capture-android-logs.sh start "$RUN_ID"
# launch app via MCP or: adb shell monkey -p com.runanywhere.runanywhereai.debug -c android.intent.category.LAUNCHER 1
test_workflows/scripts/capture-android-logs.sh snapshot "$RUN_ID" tc01_launch
# ... after each TC ...
test_workflows/scripts/capture-android-logs.sh stop "$RUN_ID"
```

**Alternative (lane layout):**

```bash
test_workflows/instructions/logging/capture_logs.sh start android "$RUN_DIR" 01_android_kotlin com.runanywhere.runanywhereai.debug
```

### TC-01 — SDK initialization

| Field | Value |
| --- | --- |
| **Platforms** | Kotlin Android |
| **Preconditions** | Fresh install; log capture running; logcat cleared |

**Steps:**

1. Cold launch the app (force-stop first: `adb shell am force-stop com.runanywhere.runanywhereai.debug`, then launch).
2. Observe splash/home; wait until bottom tabs **Chat**, **Vision**, **Voice**, **More**, **Settings** are visible.
3. Do **not** navigate away for ~10s to allow lazy Phase 2 if triggered.

**Expected logs (grep):**

- `SDK Phase 1 ready` or `SDK initialization complete`
- `Registering backends` / `Seeding curated model catalog`
- `LlamaCPP` / `ONNX` / `Sherpa` registration (no fatal)
- Absence of: `FATAL EXCEPTION`, `UnsatisfiedLinkError`, `Hermes` proto crash (N/A on Kotlin), `proto decode failed`

**Pass:** Home tabs visible; init completes without crash dialog; filtered logcat has no fatal errors.
**Fail:** Stuck splash, crash dialog, `AndroidRuntime` stack trace, 16 KB compatibility dialog.

---

### TC-02 — Chat / LLM model download

| Field | Value |
| --- | --- |
| **Preconditions** | TC-01 pass |

**Steps:**

1. Tap bottom tab **Chat**.
2. If overlay **Welcome!** appears, tap **Get Started**.
3. If toolbar shows **Select Model**, tap it. Bottom sheet title: **Select LLM Model**.
4. Under **Choose a Model**, find **SmolLM2 360M Q8_0**.
5. Tap **Download** (download icon) on that row.
6. Watch progress; wait until row shows downloaded state (no spinner; **Use** available).

**Expected logs (grep -Ei):** `Download accepted for` / `⬇️ Download accepted for` / `Registered downloaded model` / `Starting download for model:` / `task=download-proto` / model id `smollm2-360m-q8_0`; no stuck progress >15 min on fast network.

**Pass:** Model shows downloaded; UI not frozen.
**Fail:** Download error dialog, checksum failure, 0% stuck, app ANR.

---

### TC-03 — Model persistence across sessions

Superseded for detail by **TC-03a** (force-kill). Run TC-03a as the canonical persistence check; use TC-03b–d for extended lifecycle.

**Quick check (same as TC-03a on Android):**

1. Note **SmolLM2 360M Q8_0** downloaded in **Select LLM Model**.
2. Force-stop: `adb shell am force-stop com.runanywhere.runanywhereai.debug`.
3. Relaunch; **Chat** → **Select Model** → confirm still downloaded.

**Pass / fail:** See TC-03a table.

---

### TC-04 — Model load into memory

| Field | Value |
| --- | --- |
| **Preconditions** | TC-03 pass |

**Steps:**

1. In **Select LLM Model**, tap **Use** on **SmolLM2 360M Q8_0**.
2. Wait for loading overlay to dismiss; toolbar shows model name.
3. Check memory indicator if shown in UI.

**Expected logs (grep -Ei):** `Model load succeeded for` / `LLM model loaded` / `Found downloaded chat model` / `[ChatScreen] Text model loaded: true` / `✅ LLM model loaded:` / `smollm2-360m-q8_0`; no OOM kill in `dumpsys meminfo`.

**Pass:** Chat input **Type a message...** enabled; model name in toolbar.
**Fail:** **Model Load Error** dialog, native crash, empty toolbar after timeout.

---

### TC-05 — LLM inference (streaming)

| Field | Value |
| --- | --- |
| **Preconditions** | TC-04 pass |

**Steps:**

1. In **Chat**, type: `In one sentence, explain what RunAnywhere does.`
2. Tap **Send** (content description **Send**).
3. Observe assistant message streaming token-by-token until complete.

**Expected logs (grep -Ei):** `LLM stream complete` / `[PARAMS] generateStream` / `Streaming token` / stream completion marker; fallback: load marker from TC-04.

**Pass:** Non-empty assistant reply; stream ends (cursor stops).
**Fail:** Empty response, infinite spinner, crash mid-stream.

---

### TC-06 — VAD (Voice Activity Detection)

| Field | Value |
| --- | --- |
| **Navigation** | **More** → **Voice Activity Detection** |

**Steps:**

1. Open **More** tab → card **Voice Activity Detection**.
2. Tap **Select Model** / **Change** if needed; download **Silero VAD** if not present.
3. Load model; grant microphone if prompted.
4. Speak briefly, then stay silent; observe speech/silence UI states.

**Expected logs:** VAD lifecycle / `racVad` / state transitions; no JNI null from `processLifecycle`.

**Pass:** Detects speech start and end (UI or log state change).
**Fail:** No transitions, permission denied without recovery, crash.

---

### TC-07 — ASR / STT

| Field | Value |
| --- | --- |
| **Navigation** | **More** → **Speech to Text** |

**Steps:**

1. Open **Speech to Text** screen (top bar title).
2. Download/load **Sherpa Whisper Tiny (ONNX)** via **Select Model** / **Change**.
3. Use **Batch** mode: record phrase `RunAnywhere runs models on device.` (or play fixture audio).
4. Wait for transcription result.

**Expected logs (grep -Ei):** `Batch transcription complete` / `STT model loaded successfully` / `STT model loaded: true` / `Sherpa.STT.*STT model loaded` / transcription text.

**Pass:** Final text contains key words (allow ASR variance).
**Fail:** Empty transcript, model load failure, timeout.

---

### TC-08 — TTS

| Field | Value |
| --- | --- |
| **Navigation** | **More** → **Text to Speech** |

**Steps:**

1. Open **Text to Speech**.
2. Download/load **Piper TTS (US English - Medium)**.
3. Enter: `RunAnywhere runs privately on your device.`
4. Generate speech; verify playback completes.
5. **Optional:** Select **System TTS** model — expect log `System TTS` / skip C++ load on Android.

**Expected logs (grep -Ei):** `Speech generation complete` / `Synthesis complete` / `Synthesis completed` / `Sherpa.TTS.*Synthesis complete` / duration / `System TTS started` for system path.

**Pass:** Audible or logged synthesis complete.
**Fail:** Silent failure, Piper load error on system path conflated.

---

### TC-09 — VLM / Vision

| Field | Value |
| --- | --- |
| **Navigation** | **Vision** tab → **Vision Chat** → screen **Vision AI** |

**Steps:**

1. Tap **Vision** → **Vision Chat**.
2. Download/load **SmolVLM 500M Instruct**.
3. Pick image from photo picker (grant **CAMERA** if using camera).
4. Prompt: `What is visible in this image?`
5. Wait for streaming completion.

**Expected logs (grep -Ei):** `VLM streaming completed` / `VLM processing complete` / `Starting VLM streaming` / `Model load succeeded for smolvlm`.

**Pass:** Non-empty vision response.
**Fail:** mmproj/path errors, blank response, crash.

---

### TC-10 — Speech-to-text screen experience

Full UX on **More** → **Speech to Text**: model sheet, record button states, error banners, switching models. Re-run TC-07 with screenshots at: open, model sheet, recording, result.

**Pass:** Coherent flow without dead-ends.
**Fail:** Back stack broken, model sheet empty.

---

### TC-11 — Text-to-speech screen experience

Full UX on **More** → **Text to Speech**. Re-run TC-08; capture **Select Model**, text field, generate/stop controls.

**Pass:** Generate and stop (if exposed) work.
**Fail:** UI stuck on generating.

---

### TC-12 — Voice AI / voice agent pipeline

| Field | Value |
| --- | --- |
| **Navigation** | **Voice** tab |

**Steps:**

1. Open **Voice**; setup cards: **Speech Recognition**, **Language Model**, **Text to Speech**.
2. Load STT (**Sherpa Whisper Tiny**), LLM (**SmolLM2 360M**), TTS (**Piper** or **System TTS**).
3. Start voice assistant session; speak: `Tell me one benefit of on-device AI.`
4. Observe pipeline: capture → STT → LLM → TTS (partial OK if live speech hard to automate).

**Expected logs:** `Model states synced - STT: true, LLM: true, TTS: true`; transcription and TTS complete markers.

**Pass:** All three components loaded; at least one full or partial turn with evidence.
**Fail:** Component fails to load, session never starts.

---

### TC-13 — RAG (Document Q&A)

| Field | Value |
| --- | --- |
| **Navigation** | **More** → **Document Q&A** |

**Steps:**

1. Push fixture: `adb push test_workflows/fixtures/rag-sample.txt /sdcard/Download/rag-sample.txt`
2. Open **Document Q&A**; select embedding **All MiniLM L6 v2** and LLM **SmolLM2 360M Q8_0** (download if needed).
3. Import `rag-sample.txt` via file picker (Downloads).
4. Ingest; ask: `Where should model lifecycle logic live?`
5. Verify answer references C++ / on-device themes.

**Expected logs:** `ragIngest` / `ragQuery` / pipeline create; chunk retrieval.

**Pass:** Grounded answer citing ingested content.
**Fail:** Empty retrieval, pipeline create error.

---

### TC-14 — Tool calling

| Field | Value |
| --- | --- |
| **Navigation** | **Settings** → section **Tool Calling** |

**Steps:**

1. Open **Settings** tab; scroll to **Tool Calling**.
2. Enable tool calling; register demo tools if button present.
3. Return to **Chat** with LLM loaded; prompt that triggers `calculate` or device label tool (e.g. ask for device label).
4. Verify tool result appears in assistant message or tool trace in logs.

**Expected logs:** `registerTool` / tool execution / no proto encode errors.

**Pass:** Tool invoked with visible result.
**Fail:** Tool calling disabled silently, proto errors.

---

### TC-15 — Storage screen

| Field | Value |
| --- | --- |
| **Navigation** | **Settings** → **Storage Overview** / **Downloaded Models** |

**Steps:**

1. Open **Settings**; review **Storage Overview** sizes (sane, non-zero after downloads).
2. Open **Downloaded Models**; confirm **SmolLM2 360M Q8_0** listed with plausible size.
3. Do **not** delete unless running cleanup TC.

**Pass:** Downloaded models listed; sizes > 0.
**Fail:** Empty list despite TC-02, negative sizes.

---

### TC-16 — Kill app + storage persistence re-check

Run **TC-03a** then **TC-16** (storage UI after force-kill). See [§3 TC-16](#tc-16--storage-screen-after-lifecycle-events).

**Pass:** Storage + **Chat** model state consistent after force-kill.
**Fail:** Storage cleared unexpectedly while model still shown downloaded.

---

### TC-17 — Solutions

**Status: DEFERRED / N/A for now** per product guidance.

**Note:** Android exposes **More** → **Solutions** with segments **Voice Agent** and **RAG**, but automated vision-solution YAML runs are deferred. Document-only: open screen, confirm YAML list renders, mark `DEFERRED` in report.

---

### TC-18 — Validation

**Status: N/A** — no Validation tab in Kotlin app. Use modality tests TC-06–TC-14 for coverage.

---

### TC-19 — Benchmarks

| Field | Value |
| --- | --- |
| **Navigation** | **More** → **Benchmarks** |

**Steps:**

1. Open **Benchmarks**; review categories **LLM**, **STT**, **TTS**, **VLM**.
2. Ensure LLM model loaded; tap **Run All Benchmarks** (or **Run Selected (N)**).
3. Wait for run completion; open **Benchmark Details** if shown.

**Pass:** At least one category completes without crash; metrics non-empty.
**Fail:** Benchmark Error dialog, hang at 0%.

---

### TC-20 — Settings

**Steps:**

1. **Settings** tab: toggle **Generation Settings** (temperature/max tokens) if exposed.
2. Open **API Configuration (Testing)** sheet — verify opens (dev mode).
3. Confirm **Logging Configuration** visible.

**Pass:** Settings persist after leaving screen (optional re-open check).
**Fail:** Crash opening API sheet.

---

### TC-21 — LoRA adapters

| Field | Value |
| --- | --- |
| **Navigation** | **More** → **LoRA Adapters** |
| **Platforms** | Kotlin + Swift only |

**Steps:**

1. Open **LoRA Adapters**.
2. If sample adapter listed, **Download** then **Apply** with scale slider.
3. Return to **Chat** with compatible LLM; run short inference.
4. **Unload** / **Clear All Adapters**; verify removed.

**Pass:** Apply/remove without crash; inference still works.
**Fail:** Incompatible adapter crash, apply no-op with error log.

---

## 5. iOS Swift (lane `02_ios_swift`)

**Example path:** `examples/ios/RunAnywhereAI/`
**Bundle ID:** `com.runanywhere.RunAnywhere`
**Navigation:** **Chat**, **Vision**, **Voice**, **More**, **Settings** (same tab labels as Kotlin)

### Prerequisites

```bash
cd examples/ios/RunAnywhereAI
xcodebuild -project RunAnywhereAI.xcodeproj -scheme RunAnywhereAI \
  -destination 'platform=iOS Simulator,name=iPhone 16 Pro' \
  -derivedDataPath build/XcodeDerivedData build

xcrun simctl uninstall booted com.runanywhere.RunAnywhere || true
xcrun simctl install booted build/XcodeDerivedData/Build/Products/Debug-iphonesimulator/RunAnywhereAI.app
```

### Log capture

```bash
test_workflows/scripts/capture-ios-simulator-logs.sh start "$RUN_ID" RunAnywhere
test_workflows/scripts/capture-ios-simulator-logs.sh snapshot "$RUN_ID" tc01_launch RunAnywhere
test_workflows/scripts/capture-ios-simulator-logs.sh stop "$RUN_ID"
```

### UI label deltas (vs Kotlin)

| Feature | iOS label |
| --- | --- |
| STT | **More** → **Transcribe** (screen title **Speech to Text**) |
| TTS | **More** → **Speak** (screen **Text to Speech**) |
| VAD | **More** → **Voice Detection** |
| Storage | **More** → **Storage** |
| Model download button | **Get** (not Download) on sheet |
| Chat overlay CTA | **Get Started** |

### TC-01 — SDK initialization

**Steps:**

1. Launch on booted simulator (`xcrun simctl launch booted com.runanywhere.RunAnywhere`).
2. Splash: **Setting Up Your AI** / **Preparing your private AI assistant...** → tabs visible.

**Expected logs:** `🎯 Initializing SDK...`, `✅ SDK initialized in DEVELOPMENT mode`, `✅ SDK successfully initialized!`, `Model registry refreshed`

**Pass:** **Chat** tab interactive; no **Initialization Failed**.
**Fail:** Stuck **Initializing SDK...**, crash report in DiagnosticReports.

### TC-02 — Chat / LLM model download

1. **Chat** → **Welcome!** → **Get Started** if shown.
2. Open sheet **Select LLM Model** → **SmolLM2 360M Q8_0** → tap **Get**.
3. Wait for **Ready** / **Use**.

**Pass:** Download completes; **Use** available.
**Fail:** Stuck **Loading available models...**

### TC-03 — Model persistence

Swipe app away in app switcher; relaunch. Confirm model still **Ready** without re-download.

### TC-04 — Model load

Tap **Use**; wait for **Loading Model** overlay to finish.

### TC-05 — LLM inference

Send fixed LLM prompt; verify streaming response.

### TC-06 — VAD

**More** → **Voice Detection** → download **Silero VAD** → speak/silence test.

### TC-07 — ASR

**More** → **Transcribe** → **Speech to Text** flow with **Sherpa Whisper Tiny**.

### TC-08 — TTS

**More** → **Speak** → Piper model + fixed text.

### TC-09 — VLM

**Vision** → **Vision Chat** → **Vision AI** with **SmolVLM 500M Instruct**.

### TC-10 — STT screen UX

Full **Transcribe** flow documentation; same as TC-07 with UX screenshots.

### TC-11 — TTS screen UX

Full **Speak** flow.

### TC-12 — Voice AI

**Voice** tab; load STT+LLM+TTS; spoken prompt.

### TC-13 — RAG

**More** → **Document Q&A**; import PDF/JSON/text via picker; embedding + LLM selection; query.

### TC-14 — Tool calling

**Settings** → **Enable Tool Calling** / **Registered Tools**; test from Chat.

### TC-15 — Storage

**More** → **Storage**; verify downloaded models and sizes.

### TC-16 — Kill + persistence

Simulator app kill; recheck Storage + Chat model state.

### TC-17 — Solutions

**DEFERRED** — **More** → **Solutions** screen exists; do not require YAML pipeline pass.

### TC-18 — Validation

**N/A** on iOS.

### TC-19 — Benchmarks

**Settings** → **Benchmarks** → **Run All Benchmarks**.

### TC-20 — Settings

Generation settings, API config, tool calling toggles.

### TC-21 — LoRA adapters

LoRA managed from **Chat** toolbar (sheet), not More tab. Example adapter name: **Abliterated LoRA (F16)**. Apply → infer → remove.

---

## 6. Flutter (Android + iOS, lanes `05` / `06`)

**Example path:** `examples/flutter/RunAnywhereAI/`
**Android package:** `com.runanywhere.runanywhere_ai`
**iOS bundle:** `com.runanywhere.runanywhereAi`
**Tabs (8):** **Chat**, **Vision**, **STT**, **Speak**, **Voice**, **Tools**, **Solutions**, **Settings**

### Prerequisites

```bash
cd examples/flutter/RunAnywhereAI
flutter pub get
flutter build apk --debug   # Android
flutter build ios --simulator --debug   # iOS
```

### Log capture

```bash
test_workflows/scripts/capture-flutter-logs.sh start "$RUN_ID" android
# or ios
test_workflows/scripts/capture-flutter-logs.sh stop "$RUN_ID" android
```

### Known platform differences

- **Two-phase init** logs in `runanywhere_ai_app.dart` (no explicit "Phase 2" string; watch `Initializing SDK` → `Models registered`).
- **RAG:** Chat toolbar → **Document Q&A** (not a tab).
- **No VAD/Benchmarks/LoRA/Validation** screens — TC-06, TC-18, TC-19, TC-21 **N/A**.
- **Hermes/proto:** less relevant; watch `FlutterError` and platform channels.

### TC-01 — SDK initialization

Launch app; wait for tabs. Logs: `🎯 Initializing SDK...`, `✅ SDK initialized in DEVELOPMENT mode`.

**Pass:** All 8 tabs visible.
**Fail:** Red error screen, stuck init.

### TC-02 — Chat / LLM download

**Chat** → banner **No model selected** → **Select Model** → sheet **Select LLM Model** → **SmolLM2 360M Q8_0** → **Download**.

Overlay title when empty: **Start a Conversation** / **Select a Model**.

### TC-03 — Persistence

Kill app; relaunch; model still **Ready**.

### TC-04 — Load

Tap downloaded model → **Loading Model** / **Initializing {name}...** completes.

### TC-05 — LLM inference

Input **Type a message...** (when model loaded); send fixed prompt.

### TC-06 — VAD

**N/A** — no dedicated VAD screen; VAD model may appear only in Solutions YAML. Mark **N/A** with source reference `content_view.dart`.

### TC-07 — ASR

Tab **STT** → app bar **Speech to Text** → download **Sherpa Whisper Tiny** → **Batch** / **Live** → record phrase.

### TC-08 — TTS

Tab **Speak** → **Text to Speech** → **Speak** / **Generate**.

### TC-09 — VLM

Tab **Vision** → **Vision Chat** → load VLM model.

### TC-10 — STT screen UX

Full **STT** tab flow with **Tap to start recording**.

### TC-11 — TTS screen UX

Full **Speak** tab.

### TC-12 — Voice AI

Tab **Voice** → **Voice Assistant Setup** → **Start Voice Assistant**; components **Speech-to-Text**, **Language Model**, **Text-to-Speech**.

### TC-13 — RAG

**Chat** → tooltip **Document Q&A** → screen **Document Q&A**; ingest fixture; query.

### TC-14 — Tool calling

Tab **Tools** header **Tool Calling** OR **Settings** → **Enable Tool Calling** / **Add Demo Tools**.

### TC-15 — Storage

**Settings** → storage sections (mirror iOS patterns).

### TC-16 — Kill + persistence

Force-stop (Android) or swipe away (iOS); recheck model + storage.

### TC-17 — Solutions

**DEFERRED** — tab **Solutions** exists; YAML pipelines reference `smollm2-360m-q8_0` / `silero-vad`; mark deferred.

### TC-18 — Validation

**N/A**.

### TC-19 — Benchmarks

**N/A**.

### TC-20 — Settings

Tab **Settings** → generation + tool calling.

### TC-21 — LoRA

**N/A**.

**Repeat all applicable TCs on both Android device/emulator and iOS simulator** (lanes `05_flutter_android`, `06_flutter_ios`).

---

## 7. React Native (Android + iOS, lanes `03` / `04`)

**Example path:** `examples/react-native/RunAnywhereAI/`
**Android package:** `com.runanywhereaI` (capital **I**)
**iOS bundle:** `com.runanywhere.runanywhereai`
**Tabs (9):** **Chat**, **Transcribe**, **Speak**, **Voice**, **RAG**, **Vision**, **Solutions**, **Validation**, **Settings**

### Prerequisites

```bash
cd examples/react-native/RunAnywhereAI
yarn install
yarn pod-install   # iOS
cd android && ./gradlew :app:assembleDebug

# Metro (separate terminal)
yarn start --reset-cache 2>&1 | tee test_workflows/logs/react-native-$RUN_ID/metro.log
```

### Log capture

```bash
test_workflows/scripts/capture-react-native-logs.sh start "$RUN_ID" android
```

### Known platform differences

- **Hermes + proto-ts:** watch Metro for `proto` / `encode` errors and redboxes.
- **Validation tab** unique to RN (TC-18).
- **LoRA:** no dedicated manager tab — use Validation actions (TC-21).
- Overlay: **No Language Model Selected** → **Select a Model**.

### TC-01 — SDK initialization

Splash **RunAnywhere AI** / **Initializing SDK...** → tabs. Metro: `[App] SDK initialized in DEVELOPMENT mode`.

**Fail:** **Initialization Failed**, redbox, Nitro module errors.

### TC-02 — Chat / LLM download

**Chat** → **Select a Model** → sheet **Select LLM Model** → **Download** on **SmolLM2 360M Q8_0** → **Downloading... N%** → **Downloaded**.

### TC-03 — Persistence

Kill app; relaunch; row still **Downloaded**.

### TC-04 — Load

Tap **Select** on model; **Loading Model** dismisses.

### TC-05 — LLM inference

Placeholder **Type a message...**; send fixed prompt; streaming visible.

### TC-06 — VAD

**No dedicated VAD tab.** Use **Validation** → **VAD Silence** / **VAD Tone** (TC-18) for synthetic VAD, or mark primary TC-06 **N/A** and cross-reference TC-18.

### TC-07 — ASR

Tab **Transcribe** → STT screen; download Whisper tiny; transcribe phrase.

### TC-08 — TTS

Tab **Speak** → synthesis.

### TC-09 — VLM

Tab **Vision** → **Vision Chat (VLM)** → **Select Model** → SmolVLM family.

### TC-10 — Transcribe UX

Full **Transcribe** tab including **Initializing...** on first open.

### TC-11 — Speak UX

Full **Speak** tab.

### TC-12 — Voice AI

Tab **Voice** → load STT/LLM/TTS; voice turn.

### TC-13 — RAG

Tab **RAG** → ingest fixture text/file → query.

### TC-14 — Tool calling

**Settings** → **Tool Settings** → **Add Demo Tools** → Chat prompt for tool.

### TC-15 — Storage

**Settings** → **Storage Overview**, **Model Catalog**.

### TC-16 — Kill + persistence

Recheck storage + Chat.

### TC-17 — Solutions

**DEFERRED** — tab **Solutions** present.

### TC-18 — Validation harness

Tab **Validation** — subtitle *Capture deterministic modality evidence as JSONL in Metro logs.*

| Action button | Action ID |
| --- | --- |
| Structured Parse | `structured.extract_fixture` |
| Structured Generate | `structured.generate_fixture` |
| Tool Call | `tools.get_device_label` |
| VAD Silence | `vad.synthetic_silence` |
| VAD Tone | `vad.synthetic_tone` |
| LoRA List | `lora.list` |
| LoRA Compatibility | `lora.compatibility` |
| LoRA Apply | `lora.apply_fixture` |
| LoRA Remove | `lora.remove_fixture` |
| Plugin Snapshot | `pluginloader.snapshot` |
| Plugin Error | `pluginloader.load_empty_error` |

**Steps:** Tap each action; grep Metro for `[RN_VALIDATION_ACTION]` JSON line; status `PASS` or `EXPECTED_ERROR` (plugin error only).

**Pass:** All required actions emit JSONL records per `react_native/README.md`.
**Fail:** `FAIL` status or missing log line.

> **Known limitation (CLUSTER-12 / COMMONS-STRUCT-001):** the
> `structured.generate_fixture` action and the equivalent Kotlin/Flutter
> tool-call variants ride on small instruction-naive base models
> (SmolLM2-360M family). Until the commons LlamaCpp engine wires
> `rac_llm_options_t.grammar` through to `llama_sampler_init_grammar()`,
> base models may **echo the prompt instead of producing a strict JSON
> object**. The system prompt was hardened (see
> `sdk/runanywhere-commons/src/features/llm/structured_output.cpp`) but
> output validity is best-effort. Lenient PASS (prompt-echo, schema
> NOT parsed) is acceptable for these models until grammar-constrained
> decoding lands; treat a `FAIL` only if the action errored out, the
> JSONL record is missing, or a different instruction-tuned model still
> fails to produce JSON.

### TC-19 — Benchmarks

**N/A** — no Benchmarks tab.

### TC-20 — Settings

**Settings** tab sections; API configuration alerts.

### TC-21 — LoRA (via Validation)

Run **LoRA List**, **Compatibility**, **Apply**, **Remove** on Validation tab. Fixture path in source: `/tmp/runanywhere-validation-fixtures/lora/identity-adapter.gguf` (may need fixture setup on device — mark **BLOCKED** if file missing, with log evidence).

---

## 8. Web (lane `07_web`)

**Example path:** `examples/web/RunAnywhereAI/`
**URL:** `http://127.0.0.1:5173` (Vite dev)
**Tabs:** **Chat**, **Vision**, **Voice**, **Transcribe**, **Speak**, **Docs**, **Storage**, **Solutions**, **Settings**

### Prerequisites

See `instructions/web/README.md` for WASM vendor + build. Minimal smoke:

```bash
cd examples/web/RunAnywhereAI
npm install
npm run typecheck
npm run build
npm run dev -- --host 127.0.0.1
```

### Log capture

```bash
RUN_DIR="test_workflows/logs/web-$RUN_ID"
mkdir -p "$RUN_DIR/logs" "$RUN_DIR/screenshots"
# tee vite to $RUN_DIR/logs/vite.log
```

Use **cursor-ide-browser MCP**:

- Clear site storage before first navigation (OPFS/IndexedDB).
- Export console → `browser_console.jsonl`
- Screenshots after each TC step.

### Known platform differences

- **COOP/COEP** headers via Vite + `coi-serviceworker.js` for SharedArrayBuffer.
- **OPFS** persistence: `[RunAnywhere] hydrated N model(s) from OPFS`; SDK calls `navigator.storage.persist()` at init (may be denied headless — see TC-09 N/A).
- **WebGPU** runtime badge vs CPU WASM artifact split.
- **VLM / TC-09:** headless quota ceiling — catalog N/A; use persistent browser context for full VLM coverage.
- No LoRA/Benchmarks/Validation UI.

### TC-01 — SDK initialization

Navigate to app; boot UI **Setting Up Your AI** → **Initializing SDK...** → tabs clickable.

**Console grep:** `[RunAnywhere] llamacpp backend registered`, `[RunAnywhere] SDK initialized, version:`

**Pass:** `window.__RUNANYWHERE_AI_READY__` or `data-runanywhere-ai-ready` indicates ready; no console errors on load.
**Fail:** WASM init failed, blank page, COOP/COEP blocking SharedArrayBuffer.

### TC-02 — Chat / LLM download

**Chat** → overlay **Get started** → **Choose a Model** → sheet **Select Model** → **SmolLM2 360M Q8_0** → **Download** → progress → **Load**.

### TC-03 — Persistence

See **TC-03a** (tab close) and **TC-Storage-OPFS** (hard refresh). Log: `[RunAnywhere] hydrated` … `from OPFS`.

### TC-04 — Load

Click **Load**; toolbar shows model name; send enabled (**Send** tooltip not "Load a model first").

### TC-05 — LLM inference

Input **Message...**; send fixed prompt; stream tokens in UI.

### TC-06 — VAD

**N/A** dedicated screen. Optional: run opt-in browser test `RA_RUN_SPEECH_E2E=1` speech-rag spec, or Solutions YAML with `silero-vad`.

### TC-07 — ASR

Tab **Transcribe**; download STT model; transcribe (mic or fixture per UI).

### TC-08 — TTS

Tab **Speak**; download TTS; synthesize fixed text.

### TC-09 — VLM

**Status: N/A** for headless E2E (cursor-ide-browser / Playwright without a user gesture for storage persistence).

**Reason:** **SmolVLM2 256M Video Instruct Q8_0** is ~256 MB on the wire and expands to **>1 GB** on disk after extract (weights + mmproj shards). Headless browsers often grant only a small transient OPFS quota; `navigator.storage.persist()` is denied without user interaction, so downloads fail with `storage quota exceeded` even when pthread/WASM are healthy. The Web SDK requests persistent storage at `RunAnywhere.initialize()`; headed sessions that grant persist may pass manual Vision checks.

**Optional manual verification:** Tab **Vision** → **SmolVLM2 256M Video Instruct Q8_0** → image + `Describe what you see in this image.` in a headed Chrome/Safari profile with persistent storage granted (or a Playwright persistent context with a large `--disk-cache-size`).

### TC-10 — Transcribe UX

Full transcribe tab workflow.

### TC-11 — Speak UX

Full speak tab.

### TC-12 — Voice AI

Tab **Voice**; combined pipeline UI.

### TC-13 — RAG

Tab **Docs**; upload `rag-sample.txt`; ingest; query; expect references to ingested sentence.

### TC-14 — Tool calling

**Settings**; enable tools; Chat trigger.

### TC-15 — Storage

Tab **Storage** — **Browser Storage (OPFS)**, **Registered Models**, **Manage Models**.

### TC-16 — Kill + persistence

Run **TC-03a** (close tab, reopen) then **TC-16** storage UI checks. See §3.

### TC-17 — Solutions

**DEFERRED** — **Solutions** tab.

### TC-18 — Validation

**N/A**.

### TC-19 — Benchmarks

**N/A**.

### TC-Download-interrupt (Web specifics)

The Web LLM sheet currently does **not** expose a per-row **Cancel
download** affordance, so the canonical "tap Cancel mid-row" path from §3
is **NOT testable in Chat**. Acceptable Web criteria:

- **Storage tab** — open **Manage Models** during an in-flight download
  and use the **Delete** / **Remove** action on the partial entry, OR
- Browser DevTools → **Network** tab → right-click the in-flight gguf
  request → **Block request URL** / abort, then in app confirm the row
  recovers (returns to not-downloaded state) and a fresh download starts
  cleanly without zombie progress.
- Watch console for `[RunAnywhere] download cancelled` / abort signals;
  no `Uncaught (in promise)` or OPFS write errors after cancel.

If none of the above is exposed in the current build, mark **LIMITED**
and capture a screenshot of the **Storage** tab + the partial-file state
in OPFS (DevTools → **Application** → **Storage** → **OPFS**).

### TC-Inference-cancel (Web specifics)

Web Chat has no dedicated **Stop** button; cancel is wired to the
**Clear** action in the chat toolbar which invokes
`cancelGeneration()`. Web criteria:

- Set the generation cap to `max_tokens >= 2000` in **Settings** before
  starting the cancel prompt (the §3 long-form prompt body still
  applies); short caps finish before Clear can be tapped.
- Mid-stream tap **Clear**. Verify:
  - Token streaming halts within ~2-3s,
  - Chat input becomes responsive (no spinner lock),
  - Console shows `cancelGeneration` / stream-abort logging,
  - No `Uncaught` in the JS console or WASM trap.
- Compare token count emitted before cancel against the configured
  `max_tokens` — count must be strictly less, otherwise the cancel never
  exercised (treat as **FAIL**, not PASS).

If the build under test lacks the **Clear** toolbar entry, mark
**LIMITED** with a screenshot of the current Chat toolbar.

### TC-20 — Settings

**Settings** tab — generation, API, WASM/runtime info.

### TC-21 — LoRA

**N/A** (use SDK browser tests in `cross-cutting-e2e.spec.ts` for LoRA API if needed).

---

## 9. runanywhere-commons (C++)

**Path:** `sdk/runanywhere-commons/`
**Gate:** Run before mobile E2E when validating native/core changes. Failures **BLOCK** device lanes until green.

### Quick commands (macOS dev)

```bash
# Configure + build tests
cmake --preset macos-debug -DRAC_BUILD_TESTS=ON
cmake --build build/macos-debug

# Run all CTest targets
ctest --preset macos-debug --output-on-failure

# Core unit tests (no backends required)
./build/macos-debug/sdk/runanywhere-commons/tests/test_core --run-all
```

### Linux (CI / cloud VM)

```bash
cd sdk/runanywhere-commons
CC=gcc CXX=g++ cmake -B build -DRAC_BUILD_TESTS=ON -DRAC_BUILD_BACKENDS=ON \
  -DCMAKE_BUILD_TYPE=Debug -DRAC_BUILD_PLATFORM=OFF
cmake --build build
ctest --test-dir build --output-on-failure
./build/tests/test_core --run-all
```

Full backends (optional): `scripts/build-linux.sh --shared` per `AGENTS.md`.

### Streaming parity (ctest `stream` subset)

Cross-SDK wire-format parity (voice agent, LLM streaming, perf bench, cancel
parity) is exercised via the ctest `stream` subset — **not** standalone
executables. Do **not** build or invoke removed legacy targets
(`parity_test_cpp`, `perf_producer`, `cancel_producer`).

```bash
cmake --preset macos-debug -DRAC_BUILD_TESTS=ON
cmake --build build/macos-debug

# Parity gate — 3 streaming tests (llm_stream_proto, sdk_event_stream, stt_vad_stream_event)
ctest --test-dir build/macos-debug -R "stream|parity" --output-on-failure
```

Categories embedded in ctest: voice agent (`golden_events.txt`), LLM streaming
(`llm_golden_events.txt`), perf bench (p50 decode), cancel parity (interrupt at
index 500).

### Log capture

```bash
RUN_ID="commons-$(date +%Y%m%d-%H%M%S)"
test_workflows/scripts/capture-commons-test.sh run "$RUN_ID"
# or reuse existing build (stream parity subset only):
test_workflows/scripts/capture-commons-test.sh ctest "$RUN_ID" build/macos-debug --ctest-filter 'stream|parity'
```

Output: `test_workflows/logs/commons-<run-id>/logs/{cmake_configure,cmake_build,ctest,test_core}.log` + `command_summary.tsv`.

### Preflight scripts (repo root)

```bash
scripts/validation/e2e/run_global_source_checks.sh
scripts/validation/commons/run_commons_proto_checks.sh
```

### Pass criteria

- `test_core --run-all` exits 0 (13 core tests, no models)
- Full `ctest` exits 0 (112/112 on macos-debug)
- `ctest -R "stream|parity"` exits 0 (3 streaming parity tests) when streaming
  wire format is touched
- No sanitizer crashes in `linux-asan` preset when used

---

## 9b. Harness fixture + executor gaps (cross-lane)

Documented gaps that future executor / capture scripts should address —
each item below was flagged in a recent matrix run and is **not yet
auto-handled by the harness**; manual setup is required until the
referenced script change lands.

### RAG fixture pre-stage (TC-13)

- **iOS sim** — `rag-sample.txt` must be reachable from the Files
  provider used by the app. Pre-stage with:
  ```bash
  IOS_UDID="${RAC_IOS_SIM_UDID:-booted}"
  APP_BUNDLE_ID="${BUNDLE_ID:-com.runanywhere.runanywhereai}"
  DATA_DIR="$(xcrun simctl get_app_container "${IOS_UDID}" "${APP_BUNDLE_ID}" data)"
  mkdir -p "${DATA_DIR}/Documents"
  cp test_workflows/fixtures/rag/rag-sample.txt "${DATA_DIR}/Documents/"
  ```
- **Android device/emulator** — push to the app's documents dir before
  launching:
  ```bash
  adb -s "${RAC_ANDROID_SERIAL}" push test_workflows/fixtures/rag/rag-sample.txt \
    /sdcard/Documents/rag-sample.txt
  ```

### LoRA fixture deployment (TC-21 / Validation-LoRA)

- React Native example reads adapter from
  `RNFS.DocumentDirectoryPath + '/lora/identity-adapter.gguf'`
  (see `examples/react-native/RunAnywhereAI/src/screens/ValidationHarnessScreen.tsx`).
- iOS sim: copy adapter into the app's `Documents/lora/` (use
  `xcrun simctl get_app_container … data`).
- Android: `adb push identity-adapter.gguf
  /sdcard/Android/data/<package>/files/lora/` (or use `run-as` for an
  in-sandbox push).

### Synthetic audio + image fixtures (RN iOS TC-06/TC-07/TC-09)

- `ValidationHarnessScreen` synthesises `silence` / `tone` Float32 audio
  in-process (see `createSyntheticAudio`); no asset needs to be staged.
- Voice-turn fixture (sentence audio for end-to-end voice agent) is
  **not yet bundled** — manual mic capture is currently required on the
  RN-iOS lane; flag the TC as **LIMITED** until a bundled wav lands.
- Vision fixture image (small jpg/png used by VLM probes) is **not yet
  bundled**; harness uses simulator photo library — pre-seed images
  with `xcrun simctl addmedia "${IOS_UDID}" path/to/image.jpg`.

### Flutter iOS executor truncation marker

If a Flutter-iOS executor run produces sparse `lane.jsonl` (e.g. <10
TC rows) but dense screenshots (>30 PNGs), the harness should write
`EXECUTOR_TRUNCATED.md` into the lane root so triage agents can
correctly attribute "missing TC rows" to executor truncation rather
than test FAIL. Until that auto-marker is wired in, lane investigators
should add the file by hand when they detect the pattern.

### RN Android Metro reachability

`adb reverse tcp:8081 tcp:8081` must be run **after** `adb install`
and **before** app launch on every fresh adb session — otherwise the
RN bundle cannot reach Metro and TC-01 will block. The Android
executor (`scripts/react-native/run-rn-android-executor.sh`) now sets
this up automatically; manual lanes still need the command.

### RN iOS simulator cycle

Before RN-iOS executor runs, shut down stale boots and explicitly boot
the target UDID — leftover sims from earlier runs can otherwise
silently swallow `xcrun simctl` commands:

```bash
xcrun simctl shutdown all || true
xcrun simctl boot "${RAC_IOS_SIM_UDID}" || true
xcrun simctl bootstatus "${RAC_IOS_SIM_UDID}" -b
```

The RN-iOS executor (`scripts/react-native/run-rn-ios-executor.sh`)
performs this cycle automatically when `RAC_IOS_SIM_UDID` is a real
UDID (i.e. not the literal string `booted`); manual lanes still need
to do it explicitly.

---

## 10. Appendix: grep patterns

**Machine-readable alternates:** `test_workflows/scripts/_catalog_marker_patterns.sh` (`RAC_REGEX_TC*`).

Analyzers and regrade scripts use `grep -Ei` against all files under `logs/` (include `android_logcat.log`, `logcat_full.log`, `ios_live.log`, `metro.log` — not only filtered snapshots).

### TC marker mapping (legacy → actual SDK output)

| Step | Legacy pattern (iter ≤4) | Actual output observed (iter 5) | Updated grep (matches both) |
| --- | --- | --- | --- |
| TC-01 init | `SDK initialization complete` | `Phase 1 complete`, `[App] All models registered` | `SDK Phase 1 ready\|Phase 1 complete\|SDK successfully initialized\|\[App\] All models registered` |
| TC-02 download | `Download accepted for` | Kotlin `⬇️ Download accepted for`; C++ `Registered downloaded model`; Flutter `[RunAnywhere.Download] Download accepted`; Swift `task=download-proto-N` | `Download accepted for\|Registered downloaded model\|Starting download for model:\|task=download-proto` |
| TC-03 persistence | `Phase 1 complete` after relaunch | RN `[App] All models registered`; Android `SDK Phase 1 proto initialized`; Flutter `[RunAnywhere.Init] Phase 1 complete`; Swift `App is ready to use` | `Phase 1 complete\|SDK Phase 1 ready\|App is ready\|\[App\] All models registered\|SDK Phase 1 proto initialized` |
| TC-04 load | `LLM model loaded` | C++/Swift `Model load succeeded for`; Kotlin `✅ Model load succeeded for`; RN `[ChatScreen] Text model loaded: true`; Flutter `Voice agent LLM model loaded:`; Swift bootstrap `✅ LLM models registered`; C++ `Model loaded successfully` | `Model load succeeded for\|LLM model loaded\|Found downloaded chat model\|Text model loaded: true\|LLM models registered\|Model loaded successfully` |
| TC-05 chat | `LLM stream complete` | Kotlin `[PARAMS] generateStream`; stream token events; executor fallback on load marker | `LLM stream complete\|\[PARAMS\] generateStream\|Streaming token` (+ TC-04 load fallback) |
| TC-07 STT load | `STT model loaded successfully` | Flutter `STT model loaded:`; Kotlin `STT model loaded:` / `Batch transcription complete`; Sherpa `Sherpa.STT.*STT model loaded successfully`; RN `[STTScreen] STT model loaded: true` | `STT model loaded successfully\|STT model loaded: true\|Sherpa\.STT.*STT model loaded\|Batch transcription complete` |
| TC-08 TTS | `Speech generation complete` | Kotlin SDK `Synthesis complete`; C++ `Synthesis completed`; Flutter `debugPrint('Speech generation complete')` | `Speech generation complete\|Synthesis complete\|Synthesis completed` |
| TC-09 VLM | `VLM streaming completed` | Kotlin `VLM processing complete` / `Starting VLM streaming`; example `Frame description completed`; reject `VLM model loaded: false` | `VLM streaming completed\|VLM processing complete\|Starting VLM streaming\|Frame description completed\|VLM model loaded: true` |
| TC-13 RAG | `Document loaded successfully` | Kotlin `Embedding generation complete`; Flutter/RN example `Document loaded successfully`; C++ `Query complete` | `Document loaded successfully\|Embedding generation complete\|Query complete\|ragIngest\|ragQuery` |

### Quick-reference table

| Pattern | Indicates |
| --- | --- |
| `SDK Phase 1 ready` / `Phase 1 complete` | Phase 1 init (Kotlin/Swift/Flutter/RN) |
| `[App] All models registered` | RN catalog refresh complete (TC-01 RN) |
| `SDK initialized` / `SDK successfully initialized` | Init success (all platforms) |
| `FATAL EXCEPTION` / `AndroidRuntime` | Android crash |
| `UnsatisfiedLinkError` / `dlopen failed` | Native library failure |
| `Download accepted for` / `Registered downloaded model` | Download accepted (not load pass) |
| `Model load succeeded for` / `LLM model loaded` | Load OK |
| `[ChatScreen] Text model loaded: true` | RN example load OK |
| `Found downloaded chat model` | Kotlin example auto-load path |
| `LLM stream complete` / `[PARAMS] generateStream` | Chat stream OK |
| `Batch transcription complete` | STT inference OK |
| `STT model loaded successfully` / `STT model loaded: true` | STT load OK |
| `Speech generation complete` / `Synthesis complete` | TTS OK |
| `VLM streaming completed` / `VLM processing complete` | VLM OK |
| `Phase 1 complete` / `[App] All models registered` (post relaunch) | TC-03 persistence OK |
| `Document loaded successfully` / `Embedding generation complete` | RAG ingest OK |
| `Batch transcription complete` | STT batch inference OK |
| `LLM models registered` | Swift catalog bootstrap (TC-04 fallback) |
| `System TTS started` | Android system TTS path |
| `Model states synced` | Voice agent components (TC-12) |
| `ConversationStore` / `Created conversation` | RN chat stream fallback (TC-05) |
| `regrade §7.0: PASS-WHEN-UI-PROVES` | Harness regrade when action+screenshot prove UI, no fatal/counter-evidence |
| `ragIngest` / `ragQuery` / `RAG` | RAG pipeline |
| `proto decode failed` / `encode failed` | Proto bridge error |
| `[RN_VALIDATION_ACTION]` | RN validation JSONL |
| `[RunAnywhere] hydrated` | Web OPFS restore |
| `Hermes` + `proto` (RN) | RN bridge issues |

---

## 11. Appendix: feature parity matrix

| Screen / feature | Kotlin | Swift | Flutter | RN | Web |
| --- | --- | --- | --- | --- | --- |
| Chat | Tab | Tab | Tab | Tab | Tab |
| VAD UI | More | More | — | Validation | — |
| STT | More | More | STT tab | Transcribe | Transcribe |
| TTS | More | More | Speak tab | Speak | Speak |
| Voice agent | Tab | Tab | Tab | Tab | Tab |
| VLM | Vision | Vision | Vision | Vision | Vision |
| RAG | More | More | Chat→Docs | RAG tab | Docs |
| Tools | Settings | Settings | Tools+Settings | Settings | Settings |
| Storage | Settings | More | Settings | Settings | Storage tab |
| Benchmarks | More | Settings | — | — | — |
| LoRA | More | Chat sheet | — | Validation | — |
| Solutions | More (deferred) | More (deferred) | Tab (deferred) | Tab (deferred) | Tab (deferred) |
| Validation | — | — | — | Tab | — |

---

*Catalog version: 2026-05-25 (§10 CLUSTER-26c marker alignment + §7.0 UI-proves regrade). UI strings sourced from example apps; drift → grep `examples/*/RunAnywhereAI`.*
