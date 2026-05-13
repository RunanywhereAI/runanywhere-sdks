# React Native Android Lane

Lane: `03_react_native_android`

Package ID: `com.runanywhereaI`

## Build And Fresh Install

```bash
RUN_DIR="test_workflows/logs/<run-id>"
LANE="03_react_native_android"
PACKAGE="com.runanywhereaI"

mkdir -p "$RUN_DIR/$LANE/logs" "$RUN_DIR/$LANE/screenshots" "$RUN_DIR/$LANE/videos"

cd examples/react-native/RunAnywhereAI
yarn install
yarn typecheck
adb devices -l | tee "../../$RUN_DIR/$LANE/logs/adb_devices.log"
adb uninstall "$PACKAGE" > "../../$RUN_DIR/$LANE/logs/adb_uninstall.log" 2>&1 || true
```

Start Metro in a captured log if it is not already running:

```bash
yarn start --reset-cache > "../../$RUN_DIR/$LANE/logs/metro.log" 2>&1 &
echo $! > "../../$RUN_DIR/$LANE/logs/metro.pid"
```

Build/install/run:

```bash
test_workflows/instructions/logging/capture_logs.sh start android "$RUN_DIR" "$LANE" "$PACKAGE"

cd examples/react-native/RunAnywhereAI
yarn android > "../../$RUN_DIR/$LANE/logs/rn_android_run.log" 2>&1
test_workflows/instructions/logging/capture_logs.sh snapshot android "$RUN_DIR" "$LANE" "000_after_launch" "$PACKAGE"
```

Capture `screenshots/000_launch.png` with Mobile MCP.

## Required Launch Checks

- app is foreground
- no Android 16 KB compatibility dialog
- no redbox
- no blank screen
- no blocked Metro connection error
- no stale state from previous install

If the Android compatibility dialog appears, mark `FAIL` and list every library
shown in the screenshot.

## Required Modality Workflow

For each exposed RN Android feature:

1. Open the tab/screen.
2. Capture screenshot.
3. Select model.
4. Download model through the app UI.
5. Capture download start/progress/completion.
6. Tap/open the downloaded model to load it.
7. Capture loaded state.
8. Run inference with fixed input from `../common/modality_matrix.md`.
9. Capture final output and logs.
10. Inspect both logcat and Metro logs.

Snapshot logs after each modality:

```bash
test_workflows/instructions/logging/capture_logs.sh snapshot android "$RUN_DIR" "$LANE" "<modality>_after_inference" "$PACKAGE"
```

## Modalities To Attempt

- LLM chat
- STT / ASR
- TTS
- VAD
- voice agent
- VLM
- RAG
- tool calling
- structured output
- embeddings/search
- Solutions if exposed
- hardware/profile/settings
- model download/storage/load/unload lifecycle

## Validation Harness Sweep

After the normal feature tabs, open the `Validation` tab and tap each harness
button from `README.md`. Snapshot logs after the group:

```bash
test_workflows/instructions/logging/capture_logs.sh snapshot android "$RUN_DIR" "$LANE" "validation_harness_after_actions" "$PACKAGE"
```

Copy every Metro line prefixed with `[RN_VALIDATION_ACTION]` into
`$RUN_DIR/$LANE/actions.jsonl`. The report must call out structured output,
deterministic `get_device_label` tool calling, standalone VAD silence/tone,
LoRA list/compatibility/apply/remove, and PluginLoader success/error evidence.

## Required Report Details

The lane report must include:

- Android device/API level
- package uninstalled
- build/install command
- Metro log path
- all downloaded model IDs
- all loaded model IDs
- inference input/output for every modality
- log findings after every action
- whether JS only wrapped C++/proto behavior or duplicated business logic

Stop logs:

```bash
test_workflows/instructions/logging/capture_logs.sh stop android "$RUN_DIR" "$LANE"
```
