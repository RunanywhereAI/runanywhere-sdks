# Kotlin Android — lane deltas

**Lane:** `01_kotlin_android`
**Full TC steps:** [`../cross-platform-e2e-test-catalog.md` §4](../cross-platform-e2e-test-catalog.md#4-android-kotlin-lane-01_android_kotlin)
**Executor sub-prompt (modality keyframes 007–014):** [`executor-sub-prompt.md`](executor-sub-prompt.md)
**Automated driver:** `test_workflows/scripts/kotlin/run-kotlin-executor.sh`
**MCP runbook:** [`../mcp-agent-runbook.md`](../mcp-agent-runbook.md)

> ⚠️ **Mandatory fresh install for every executor run** — see [`../reusable-full-matrix-e2e-loop-prompt.md` §7.3](../reusable-full-matrix-e2e-loop-prompt.md#73-universal-lane-executor-sub-prompt) step 5. Each invocation (first attempt, resumed continuation, or Phase 9 re-verification) MUST `adb shell am force-stop`, `adb uninstall` (retry once if first call returns `DELETE_FAILED_INTERNAL_ERROR`), rebuild APK from worktree, `adb install -r`, grant runtime permissions, and `adb shell am start` the MainActivity. No "resume on existing install" mode. Pre-sweep stale processes: `pkill -9 -f 'logcat.*RunAnywhere'`.

## Identifiers

| Field | Value |
| --- | --- |
| SDK | `sdk/runanywhere-kotlin` |
| Example | `examples/android/RunAnywhereAI` |
| Debug package | `com.runanywhere.runanywhereai.debug` |
| APK | `app/build/outputs/apk/debug/app-debug.apk` |
| Tabs | **Chat**, **Vision**, **Voice**, **More**, **Settings** |

## Preflight

```bash
scripts/validation/e2e/run_global_source_checks.sh
scripts/validation/commons/run_commons_proto_checks.sh
cd examples/android/RunAnywhereAI
./gradlew :app:assembleDebug -Prunanywhere.useLocalNatives=false
```

## Log capture (mandatory — start before install/launch)

```bash
RUN_ID=$(test_workflows/scripts/run-manage.sh new kotlin-android)
export RAC_RUN_ID="$RUN_ID"
export ANDROID_PACKAGE=com.runanywhere.runanywhereai.debug

test_workflows/scripts/session-manage.sh lane kotlin
test_workflows/scripts/kotlin/capture-kotlin-logs.sh start "$RUN_ID"

adb uninstall "$ANDROID_PACKAGE" || true
adb install -r app/build/outputs/apk/debug/app-debug.apk
adb shell pm grant "$ANDROID_PACKAGE" android.permission.RECORD_AUDIO
adb shell pm grant "$ANDROID_PACKAGE" android.permission.CAMERA
test_workflows/scripts/kotlin/capture-kotlin-logs.sh snapshot "$RUN_ID" tc01_init
```

**STT fixture (TC-07 / catalog §2):** The executor injects `test_workflows/fixtures/stt-phrase.wav` (16 kHz mono, phrase *RunAnywhere runs models on device.*) via `test_workflows/scripts/android/inject-stt-audio.sh` — emulator `avd attachmic`, host-mic + `afplay`, or device speaker fallback — before batch record.

```bash
# Optional: regenerate fixture locally
say -v Samantha -r 160 -o /tmp/stt.aiff "RunAnywhere runs models on device."
ffmpeg -y -i /tmp/stt.aiff -ar 16000 -ac 1 -sample_fmt s16 test_workflows/fixtures/stt-phrase.wav
```

```bash
test_workflows/scripts/kotlin/capture-kotlin-logs.sh stop "$RUN_ID"
# Analyzer → test_workflows/logs/runs/$RUN_ID/lanes/01_kotlin_android/modality_report.md
```

Lane root: `test_workflows/logs/runs/<run-id>/lanes/01_kotlin_android/` — [`../../logs/README.md`](../../logs/README.md).

## Lifecycle commands (TC-03c / TC-03d)

```bash
adb uninstall com.runanywhere.runanywhereai.debug
adb shell pm clear com.runanywhere.runanywhereai.debug
adb shell am force-stop com.runanywhere.runanywhereai.debug
```
