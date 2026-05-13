# React Native iOS Lane

Lane: `04_react_native_ios`

Bundle ID: `com.runanywhere.runanywhereai`

## Build And Fresh Install

```bash
RUN_DIR="test_workflows/logs/<run-id>"
LANE="04_react_native_ios"
BUNDLE_ID="com.runanywhere.runanywhereai"

mkdir -p "$RUN_DIR/$LANE/logs" "$RUN_DIR/$LANE/screenshots" "$RUN_DIR/$LANE/videos"

cd examples/react-native/RunAnywhereAI
yarn install
bundle install || true
cd ios
pod install
cd ..
yarn typecheck
xcrun simctl list devices booted > "../../$RUN_DIR/$LANE/logs/simctl_booted_devices.log"
xcrun simctl uninstall booted "$BUNDLE_ID" > "../../$RUN_DIR/$LANE/logs/simctl_uninstall.log" 2>&1 || true
```

Start Metro in a captured log if it is not already running:

```bash
yarn start --reset-cache > "../../$RUN_DIR/$LANE/logs/metro.log" 2>&1 &
echo $! > "../../$RUN_DIR/$LANE/logs/metro.pid"
```

Start simulator logs before launch:

```bash
test_workflows/instructions/logging/capture_logs.sh start ios "$RUN_DIR" "$LANE" "RunAnywhereAI"
```

Build/install/run:

```bash
cd examples/react-native/RunAnywhereAI
yarn ios > "../../$RUN_DIR/$LANE/logs/rn_ios_run.log" 2>&1
test_workflows/instructions/logging/capture_logs.sh snapshot ios "$RUN_DIR" "$LANE" "000_after_launch" "RunAnywhereAI"
```

Capture `screenshots/000_launch.png` with Mobile MCP.

## Required Launch Checks

- app is foreground
- no redbox
- no "Open debugger to view warnings" banner
- no stuck blank screen
- no Metro connection blocker
- no stale state from previous install

If a debugger warning banner appears, open/inspect Metro and simulator logs,
record the warning, and mark the lane `FAIL` or `LIMITED` until resolved.

## Required Modality Workflow

For each exposed RN iOS feature:

1. Open the tab/screen.
2. Capture screenshot.
3. Select model.
4. Download model through the app UI.
5. Capture download start/progress/completion.
6. Tap/open the downloaded model to load it.
7. Capture loaded state.
8. Run inference with fixed input from `../common/modality_matrix.md`.
9. Capture final output and logs.
10. Inspect simulator and Metro logs.

Snapshot logs after each modality:

```bash
test_workflows/instructions/logging/capture_logs.sh snapshot ios "$RUN_DIR" "$LANE" "<modality>_after_inference" "RunAnywhereAI"
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
- microphone/camera/files permissions where exposed

## Validation Harness Sweep

After the normal feature tabs, open the `Validation` tab and tap each harness
button from `README.md`. Snapshot logs after the group:

```bash
test_workflows/instructions/logging/capture_logs.sh snapshot ios "$RUN_DIR" "$LANE" "validation_harness_after_actions" "RunAnywhereAI"
```

Copy every Metro line prefixed with `[RN_VALIDATION_ACTION]` into
`$RUN_DIR/$LANE/actions.jsonl`. The report must call out structured output,
deterministic `get_device_label` tool calling, standalone VAD silence/tone,
LoRA list/compatibility/apply/remove, and PluginLoader success/error evidence.

## Required Report Details

The lane report must include:

- simulator name/runtime/UDID
- bundle uninstalled
- Metro log path
- all downloaded model IDs
- all loaded model IDs
- inference input/output for every modality
- warning banners and their logs
- whether JS only wrapped C++/proto behavior or duplicated business logic

Stop logs:

```bash
test_workflows/instructions/logging/capture_logs.sh stop ios "$RUN_DIR" "$LANE"
```
