# S6 Sample HTTP Carve-Outs

Date: 2026-04-24
Branch: `feat/v2-architecture`
HEAD at start of remediation: `737bd781`

## Decision

The remaining direct HTTP calls in sample apps are external demo/tool traffic,
not SDK auth, model registry, or model download traffic. They are now explicitly
annotated as `SAMPLE_HTTP_CARVE_OUT`.

## Annotated Call Sites

- iOS LoRA adapter download:
  `examples/ios/RunAnywhereAI/.../LLMViewModel.swift`
- iOS weather tool:
  `examples/ios/RunAnywhereAI/.../ToolSettingsView.swift`
- Android weather tool:
  `examples/android/RunAnywhereAI/.../ToolSettingsViewModel.kt`
- Flutter weather tool:
  `examples/flutter/RunAnywhereAI/lib/features/settings/tool_settings_view_model.dart`
- React Native weather tool:
  `examples/react-native/RunAnywhereAI/src/screens/{ChatScreen,SettingsScreen}.tsx`
- Web weather tool:
  `examples/web/RunAnywhereAI/src/views/chat.ts`

## Verification

`rg "URLSession|HttpURLConnection|package:http|fetch\\(" examples` now shows
these demo-tool calls with nearby `SAMPLE_HTTP_CARVE_OUT` comments. Web's
COOP/COEP service worker fetches remain browser infrastructure and are outside
SDK/sample-tool HTTP migration scope.
