# Windows Vision Page Design

## Goal

Restore the Flutter example `Vision` page on Windows in the main workspace, while keeping the interaction model as close as possible to Android and iOS:

- camera preview
- single-frame capture and description
- live mode using repeated captures
- gallery photo selection and description

The implementation must be isolated so it does not introduce regressions to Android, iOS, or Web builds.

## Context

The current Flutter example already contains a complete Vision UI and VLM flow:

- [examples/flutter/RunAnywhereAI/lib/features/vision/vision_hub_view.dart](/d:/work/projects/runanywhere-sdks-new/examples/flutter/RunAnywhereAI/lib/features/vision/vision_hub_view.dart)
- [examples/flutter/RunAnywhereAI/lib/features/vision/vlm_camera_view.dart](/d:/work/projects/runanywhere-sdks-new/examples/flutter/RunAnywhereAI/lib/features/vision/vlm_camera_view.dart)
- [examples/flutter/RunAnywhereAI/lib/features/vision/vlm_view_model.dart](/d:/work/projects/runanywhere-sdks-new/examples/flutter/RunAnywhereAI/lib/features/vision/vlm_view_model.dart)

However, Windows is currently disabled at the capability layer:

- [examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart](/d:/work/projects/runanywhere-sdks-new/examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart)

The app already depends on `camera`, but the current `camera` package version only declares default implementations for Android, iOS, and Web. Windows camera support therefore needs an explicit Windows plugin dependency.

## Constraints

- Work must happen in the main workspace, not in a git worktree.
- Changes should stay inside the Flutter example unless a shared SDK change is strictly necessary.
- Windows behavior should remain as close as possible to the current mobile Vision UX.
- Any unavoidable Windows differences must be documented and surfaced clearly.

## Options Considered

### Option A: Add `camera_windows` beside `camera`

Add `camera_windows` as a direct dependency of the Flutter example and continue using the standard `camera` API in the Vision feature.

Pros:

- Best isolation: Windows-specific plugin only
- Minimal impact to Android/iOS code paths
- Continues to use the existing `camera` API already used by the Vision view model
- Maintained by `flutter.dev`

Cons:

- Windows implementation is not an endorsed default plugin for `camera`, so it must be declared explicitly
- Some mobile-style camera features remain unsupported on Windows

### Option B: Add `camera_desktop`

Add `camera_desktop` next to `camera` and let it cover desktop platforms.

Pros:

- Standard `camera` API
- Desktop support across Windows, macOS, and Linux

Cons:

- Broader blast radius because desktop platforms share the same implementation
- Weaker platform isolation than Option A
- Not necessary for the current user goal, which is Windows-only recovery

### Option C: Keep Windows gallery-only

Open the Vision page on Windows but use only `image_picker_windows`, skipping camera preview and live mode.

Pros:

- Lowest implementation risk
- No Windows camera integration needed

Cons:

- Does not satisfy the approved requirement for a near-mobile-complete Windows Vision page

## Chosen Approach

Use **Option A**.

The Flutter example will add `camera_windows` directly and keep the existing `camera` API usage in the Vision feature. This keeps Windows support local to the example app, avoids changing the shared Flutter SDK packages, and preserves the current Vision page structure instead of rebuilding the feature around a separate desktop-only camera stack.

## Architecture

### 1. Dependency Layer

Modify the Flutter example package only:

- add `camera_windows` to [examples/flutter/RunAnywhereAI/pubspec.yaml](/d:/work/projects/runanywhere-sdks-new/examples/flutter/RunAnywhereAI/pubspec.yaml)
- keep `camera` as the shared API package

Result:

- Android/iOS/Web continue using the existing `camera` plugin path
- Windows registers `camera_windows` explicitly

### 2. Capability Layer

Update [examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart](/d:/work/projects/runanywhere-sdks-new/examples/flutter/RunAnywhereAI/lib/core/services/platform_capability_service.dart) so `supportsVision` is no longer hard-disabled on Windows.

The page entry should be enabled once the Windows camera path is integrated.

### 3. Vision Feature Layer

Keep the existing page structure intact:

- `VisionHubView`
- `VLMCameraView`
- `VLMViewModel`

The goal is to preserve the same user-visible workflow:

- choose/load a VLM model
- initialize camera
- show preview
- tap to capture and describe
- toggle live mode
- pick a photo from gallery

Only Windows-specific adjustments should be introduced where they are actually needed, and those adjustments should be kept inside the Vision feature implementation.

### 4. SDK Boundary

Do not change the shared RunAnywhere Flutter SDK unless debugging proves a real Windows VLM issue in the SDK layer.

The current design assumes:

- model loading stays in `RunAnywhere.loadVLMModel`
- image inference stays in `RunAnywhere.processImageStream`
- Windows camera support is an example-app concern, not an SDK concern

## Isolation Strategy

To reduce cross-platform risk:

- keep all new dependency changes inside the Flutter example app
- avoid modifying `sdk/runanywhere-flutter/packages/*` for this task unless a proven SDK bug is found
- keep Windows-specific branching local to Vision-related files
- do not change Android/iOS camera flows
- do not alter non-Vision tabs as part of this work

If a small Windows-specific helper is needed, it should be added under the Vision feature rather than in shared application services.

## Expected Windows Differences

The goal is near parity, but these differences are expected and acceptable:

1. Live mode is still repeated still-image capture, not raw image streaming.
   This is already how the current Flutter Vision page behaves, so the user experience remains consistent with the existing Flutter example.

2. Some mobile-oriented camera controls are not expected to work on Windows.
   Examples: torch, focus point, exposure point, orientation-driven behavior.

3. Preview scaling or mirroring may differ slightly by Windows camera device.
   If that happens, UI fixes should be limited to the Windows Vision view and not generalized to all platforms.

4. Device availability differs more on Windows.
   External webcams, virtual cameras, or no-camera devices must be handled gracefully.

These differences should be called out in validation notes and, if needed, surfaced via friendly UI messaging instead of hard failures.

## Failure Handling

The Windows Vision page must fail safely in these cases:

- no camera devices available
- permission denied
- VLM model not loaded
- VLM model load failure
- image capture failure
- live mode capture failure

Expected behavior:

- the page still opens
- the user sees actionable error state or message
- the app does not crash
- other tabs remain unaffected

## Validation Plan

### Automated

Run from the example app:

```powershell
fvm flutter pub get
fvm flutter analyze lib/features/vision lib/core/services/platform_capability_service.dart
fvm flutter build windows
```

### Manual

On Windows:

1. Open `Vision` tab successfully.
2. Open model selector and load the VLM model.
3. Confirm camera preview appears.
4. Trigger single capture and receive a VLM description.
5. Trigger gallery selection and receive a VLM description.
6. Enable Live mode and confirm repeated updates without crashing.
7. Verify no-camera and permission-denied paths show safe UI behavior.

## Out of Scope

- image generation on Windows
- desktop-wide camera abstraction beyond this Flutter example
- replacing the current Vision UX with a Windows-specific redesign
- VLM backend changes unrelated to proven Windows issues

## Recommendation Summary

Implement Windows Vision recovery by adding `camera_windows` directly to the Flutter example and keeping the rest of the Vision flow aligned with the current mobile structure. This provides the best balance of parity, low blast radius, and implementation speed while keeping Windows-specific risk isolated to the example app.
