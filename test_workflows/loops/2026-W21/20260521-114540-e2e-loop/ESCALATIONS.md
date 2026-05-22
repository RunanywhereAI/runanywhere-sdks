# E2E loop escalations (iter6 iOS)

## RN iOS — UNBLOCKED build, lane runs but log capture is partial

- **Original symptom:** `xcodebuild` failed in `HybridRunAnywhereCore.cpp:216` because a capturing lambda (`[baseURL, apiKey]`) was being assigned to the C function pointer slot `rac_assignment_callbacks_t::http_get`.
- **Fix landed:** Made the lambda captureless and read URL/auth from `HTTPBridge::shared()` only (it is configured earlier in the same `initialize()` for non-Development environments). Build now succeeds against `iphonesimulator` and the app installs as `com.runanywhere.runanywhereai`.
- **Iter5 verify run:** `20260522-055426-rn-ios-verify-iter5` — analyzer verdict `PASS` (7 PASS, 0 FAIL/BLOCKED), but 11 TCs land **LIMITED**: tc02/tc03/tc04/tc07/tc08/tc09/tc10/tc13/tc14/tc16/tc21.
- **Root cause for the LIMITEDs:** The RN example app emits most modality markers from JavaScript (`console.log`), which only appear in Metro stdout. `ensure-metro.sh` short-circuits when Metro is already listening on `:8081`, so no `metro.log` is written into the lane folder and the iOS `log stream` filter (`subsystem CONTAINS 'com.runanywhere'` / process `RunAnywhereAI`) never sees JS-side markers. Native-side markers (Model load succeeded) come through, but app-level JS markers are missing.
- **Harness fixes landed:** `run-rn-ios-executor.sh` now uses `RAC_RN_SCRIPT_DIR` for sourcing `_rn_tc_flows.sh` (was being overwritten by `_tc_helper.sh`'s `SCRIPT_DIR=`); `RAC_MCP_KILL_CMD` / `RAC_MCP_LAUNCH_CMD` now end with `>/dev/null 2>&1 || true` so `simctl terminate` failures during tc03 lifecycle don't trip `set -e`.
- **Next:** Either teach `ensure-metro.sh` to copy/symlink an existing Metro process's stdout into the lane log root (or always restart Metro with the lane log file when a fresh run begins), or move the JS-side modality markers into native OSLog so the existing `log stream` predicate captures them.

## Flutter iOS — remaining LIMITED TCs (timing / simctl UI)

- **Best run:** `20260522-045134-flutter-ios-iter6` (tc04 PASS via finalize; tc02/tc08/tc09/tc13 still LIMITED intermittently).
- **Root causes:** `Download accepted` often logged after tc02 snapshot; simctl `tap --label` does not always trigger Flutter `NavigationBar.onDestinationSelected` for modality markers.
- **Mitigations landed:** E2E bootstrap, finalize regrade, `_flutter_launch_app`, SDK `Download accepted` log, tab/bootstrap markers.

## Swift iOS — tc04 LIMITED

- **Run:** `20260522-050635-swift-verify-iter6` — all other applicable TCs PASS/N/A; **tc04** missing `LLM model loaded` / `Model load succeeded` in captured logs (same as iter5).

## Swift iOS — tc08/tc09/tc13 LIMITED (simctl UI automation)

- **Iter5 verify runs:** `20260522-003127-swift-verify-iter5`, `20260522-010326-swift-verify-iter5` (best, analyzer verdict PASS with LIMITED rows), and three killed/aborted retries.
- **Symptom:** Catalog drive PASSes; dedicated `_swift_drive_tc08_tts` / `_swift_drive_tc09_vlm` / `_swift_drive_tc13_rag` never observe `Speech generation complete` / `VLM streaming completed` / `Document loaded successfully` in simulator logs because coordinate-based simctl taps do not reliably navigate the **Speak** model picker (Piper download), the **Vision Chat** SmolVLM picker, or the **Document Q&A** file picker on iPhone 17 Pro / iOS 26.1.
- **Mitigations landed (commits `8b62541d0`, `a894f1424`, `bf2866e74`):** STT-style retry loop for Piper/SmolVLM model picks, RAG fixture also pushed to sim Downloads, iOS app `Registered tool calling enabled` + per-tool `Registered tool <name>` logs (tc14 now PASS in iter6), tc16 grading widened to `Download accepted for`, `lane-finalize` finds dedicated-flow screenshots correctly, `run-lane-analyzer.sh swift --run-id` arg parsing fixed.
- **Iter6 confirmation:** `20260522-050635-swift-verify-iter6` reached only tc07/tc10 (STT) before its parent orchestrator killed the executor at 12:29:45 UTC (signal 15, ~23min into dedicated flows), tc08/09/13 stay N/A from the deferred catalog. Same harness limitation, not a product issue.
- **Root cause (harness, not SDK):** Coordinate-only `simctl ui tap` is brittle for full-screen sheets and PhotosPicker/UIDocumentPicker presentations. Markers are present in the example app (`TTSViewModel.swift:113`, `VLMViewModel.swift:158`, `RAGViewModel.swift:131`) but never get triggered.
- **Next:** Move dedicated TTS/VLM/RAG flows onto an accessibility-first driver (mobile MCP HTTP tap or `RAC_MCP_TAP_HTTP`) so picker rows resolve by AX label rather than fixed XY; alternately gate on app-state markers (`Piper sheet shown`) instead of polling for the final-completion marker after a multi-tap chain.
