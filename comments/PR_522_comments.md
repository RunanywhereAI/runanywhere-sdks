# PR #522 - Comment Triage

- Repo: RunanywhereAI/runanywhere-sdks
- PR Title: Add logical QHexRT HNPU catalog resolution
- PR URL: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522
- API comment count verified: 3 issue comments + 4 inline review comments = 7
- Review bodies inspected: 2 CodeRabbit reviews with additional actionable bullets
- Source commands:
  - `gh api repos/RunanywhereAI/runanywhere-sdks/pulls/522`
  - `gh api repos/RunanywhereAI/runanywhere-sdks/pulls/522/comments --paginate`
  - `gh api repos/RunanywhereAI/runanywhere-sdks/issues/522/comments --paginate`
  - `gh api repos/RunanywhereAI/runanywhere-sdks/pulls/522/reviews --paginate`

## PR Description

Adds logical QHexRT/HNPU model registration across commons and the Android,
Flutter, and React Native example apps. Example apps register parent Hugging
Face bundle refs while commons resolves the current Hexagon arch and rewrites
logical refs to the matching arch folder at registration time.

Also adds HF token save/clear flows for private HNPU repos, re-seeds NPU catalog
rows after token changes, and tightens Android NPU E2E model resolution/report
collection.

---

## Section 1 - Quick & Easy Fixes

### QEF-1 - Fill PR title and description

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#issuecomment-4887211480
- Author: coderabbitai[bot]
- File / location: PR metadata
- LUS: 3
- CS: 1
- Type: docs

Original comment:
> Description check warned that the PR body was still template text. Title check said the title "npu support" was too vague.

Status: Fixed. PR title/body now describe logical QHexRT HNPU catalog resolution, validation, labels, and #523 follow-up.

### QEF-2 - Mark reasoning HNPU models as thinking-capable

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#discussion_r3525478043
- Author: coderabbitai[bot]
- File / location: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/ModelCatalog.kt:82`
- LUS: 4
- CS: 1
- Type: bug

Original comment:
> Set `supportsThinking = true` on `deepseek_r1_distill_qwen_1_5b`, `deepseek_r1_distill_qwen_7b`, and `qwen3_5_0_8b`.

Status: Fixed.

### QEF-3 - Store Flutter HF token in secure storage

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#discussion_r3525478045
- Author: coderabbitai[bot]
- File / location: `examples/flutter/RunAnywhereAI/lib/features/settings/combined_settings_view.dart:146`
- LUS: 5
- CS: 2
- Type: security

Original comment:
> HF token was saved and loaded through plaintext SharedPreferences; switch to the secure KeychainHelper path.

Status: Fixed. Save/load/clear use `KeychainHelper`; legacy SharedPreferences token is migrated and removed. Startup/bootstrap also reads the secure key.

### QEF-4 - Guard Android NPU registry refresh failures

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#discussion_r3525486804
- Author: coderabbitai[bot]
- File / location: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/data/ModelBootstrap.kt:67`
- LUS: 4
- CS: 1
- Type: bug

Original comment:
> `RunAnywhere.refreshModelRegistry()` still runs uncaught after the per-model loop; catch cancellation separately and log other failures.

Status: Fixed.

### QEF-5 - Guard Android HF token commit path

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631865338
- Author: coderabbitai[bot]
- File / location: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/settings/SettingsViewModel.kt`
- LUS: 4
- CS: 1
- Type: bug

Original comment:
> `commitHfToken()` lacks the try/catch pattern used elsewhere and can crash from `setHfToken()` or `refreshNpuCatalog()`.

Status: Fixed.

### QEF-6 - Add Android HF token save/clear feedback

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `examples/android/RunAnywhereAI/app/src/main/java/com/runanywhere/runanywhereai/ui/screens/settings/SettingsScreen.kt`
- LUS: 2
- CS: 1
- Type: nit

Original comment:
> Add visible confirmation feedback for Android HF token Save/Clear actions to match Flutter/RN.

Status: Fixed.

### QEF-7 - Reuse trailing-slash helper in HF resolver

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `sdk/runanywhere-commons/src/infrastructure/model_management/hf_resolver.cpp`
- LUS: 2
- CS: 1
- Type: nit

Original comment:
> `resolve_repo_folder` hand-rolls the same trailing slash trim logic as `trim_trailing_slashes`.

Status: Fixed.

### QEF-8 - Share manifest leaf extension selection

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `sdk/runanywhere-commons/src/infrastructure/model_management/register_model_from_url.cpp`
- LUS: 2
- CS: 1
- Type: nit

Original comment:
> Extract the duplicated manifest leaf extension ternary into a helper.

Status: Fixed.

### QEF-9 - Keep QHexRT arch structured until rewrite

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `sdk/runanywhere-commons/src/infrastructure/model_management/register_model_from_url.cpp`
- LUS: 3
- CS: 2
- Type: refactor

Original comment:
> Preserve `rac_hexagon_arch_t` through `maybe_resolve_qhexrt_logical_ref` and remove redundant framework re-derivation.

Status: Fixed.

### QEF-10 - Add HF resolver edge-case tests

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `sdk/runanywhere-commons/tests/test_hf_resolver_folder.cpp`
- LUS: 3
- CS: 1
- Type: test

Original comment:
> Add coverage for `nullptr manifest_leaf_ext` and nested manifest paths.

Status: Fixed.

### QEF-11 - Use model framework in Android NPU E2E registration

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `examples/android/RunAnywhereAI/app/src/androidTest/java/com/runanywhere/runanywhereai/NpuModelE2ETest.kt`
- LUS: 2
- CS: 1
- Type: nit

Original comment:
> `register()` hardcodes QHEXRT instead of using `bundle.framework`.

Status: Fixed.

### QEF-12 - Clarify unknown Android NPU E2E model id

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `examples/android/RunAnywhereAI/app/src/androidTest/java/com/runanywhere/runanywhereai/NpuModelE2ETest.kt`
- LUS: 2
- CS: 1
- Type: nit

Original comment:
> If `-e modelId` is provided but unmatched, report unknown model id instead of missing args.

Status: Fixed.

### QEF-13 - Make React Native NPU registration data-driven

- Source review: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#pullrequestreview-4631857753
- Author: coderabbitai[bot]
- File / location: `examples/react-native/RunAnywhereAI/src/services/ModelCatalogBootstrap.ts`
- LUS: 3
- CS: 2
- Type: refactor

Original comment:
> Replace 40 near-identical `registerModel(...).catch(...)` blocks with a shared `NPU_BUNDLES` array and mapped registration.

Status: Fixed.

### QEF-14 - Centralize Flutter HF token migration

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#discussion_r3525518815
- Author: coderabbitai[bot]
- File / location: `examples/flutter/RunAnywhereAI/lib/features/settings/combined_settings_view.dart:145`
- LUS: 4
- CS: 1
- Type: refactor

Original comment:
> Token migration logic belongs in the SDK, not the example view.

Status: Fixed. Token read/write/migration now lives in shared `HfTokenStore`;
the settings view, app startup, and model catalog bootstrap all call the same
helper.

## Section 2 - Larger / Structural Issues

### ISSUE-CANDIDATE-1 - Move NPU catalog bootstrap into SDK APIs

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#discussion_r3525486804
- Author: coderabbitai[bot]
- File / location: Android, Flutter, and RN NPU catalog bootstrap helpers
- LUS: 4
- CS: 4

Original comment:
> Multi-step register+refresh bootstrap logic lives in the example app; consider exposing a single SDK API.

Why this should be an issue:
- It crosses native/shared SDK API design plus Kotlin, Flutter, and RN bindings.
- This PR already applies the stability fixes; moving API ownership is a broader design/refactor.

Draft Issue Title:
- Move NPU catalog refresh bootstrap into SDK APIs

Status:
- Created as https://github.com/RunanywhereAI/runanywhere-sdks/issues/523

## Non-Actionable / Informational Comments

### INFO-1 - User requested CodeRabbit review

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#issuecomment-4887214012
- Author: sanchitmonga22
- Type: discussion
- Status: Addressed. Review was triggered and CodeRabbit posted review comments.

### INFO-2 - CodeRabbit review invocation reply

- Source comment: https://github.com/RunanywhereAI/runanywhere-sdks/pull/522#issuecomment-4887215127
- Author: coderabbitai[bot]
- Type: informational
- Status: No code action needed.

## Summary & Status

- API comments fetched and counted: 7/7.
- Review bodies inspected: 2/2.
- Quick fixes identified: 14.
- Quick fixes fixed in this PR: 14.
- Larger issues identified: 1.
- Larger issues created: 1, https://github.com/RunanywhereAI/runanywhere-sdks/issues/523.
- Remaining TODOs: wait for final CI after pushing the comment-fix commit.
