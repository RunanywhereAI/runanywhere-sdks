# E2E loop escalations (iter6 iOS)

## RN iOS — BLOCKED (build)

- **Symptom:** `yarn install` postinstall `pod-install.sh` fails (Bundler requires sudo for system Ruby gems).
- **Fallback:** `xcodebuild` fails compiling `HybridRunAnywhereCore.cpp:216` — C++ lambda assigned to `rac_assignment_http_get_fn` (capturing `[baseURL, apiKey]`).
- **Retries:** 2 (yarn install + xcodebuild).
- **Next:** Use static C callback + `user_data` context (or rely on `HTTPBridge::shared()` only) for `callbacks.http_get`; fix pod install path (bundler without sudo / use user gem home).

## Flutter iOS — remaining LIMITED TCs (timing / simctl UI)

- **Best run:** `20260522-045134-flutter-ios-iter6` (tc04 PASS via finalize; tc02/tc08/tc09/tc13 still LIMITED intermittently).
- **Root causes:** `Download accepted` often logged after tc02 snapshot; simctl `tap --label` does not always trigger Flutter `NavigationBar.onDestinationSelected` for modality markers.
- **Mitigations landed:** E2E bootstrap, finalize regrade, `_flutter_launch_app`, SDK `Download accepted` log, tab/bootstrap markers.

## Swift iOS — tc04 LIMITED

- **Run:** `20260522-050635-swift-verify-iter6` — all other applicable TCs PASS/N/A; **tc04** missing `LLM model loaded` / `Model load succeeded` in captured logs (same as iter5).
