# React Native SDK Lanes

SDK path: `sdk/runanywhere-react-native`

Example app path: `examples/react-native/RunAnywhereAI`

React Native has two runtime targets:

- `03_react_native_android`: see `android.md`
- `04_react_native_ios`: see `ios.md`

## Shared React Native Preflight

```bash
cd sdk/runanywhere-react-native
yarn install
yarn workspace @runanywhere/core typecheck
yarn workspace @runanywhere/llamacpp typecheck
yarn workspace @runanywhere/onnx typecheck

cd ../../examples/react-native/RunAnywhereAI
yarn install
yarn typecheck
```

If Metro is needed, start it in a logged shell and record whether it was already
running:

```bash
yarn start --reset-cache
```

## Shared Runtime Requirements

For both Android and iOS:

- uninstall the existing app first
- install the freshly built app
- start continuous native logs before launch
- capture Metro logs for the entire session
- use Mobile MCP for every tap/input/screenshot
- download, load, and run inference for every exposed modality
- inspect native logs and Metro logs after every action group

Do not mark React Native as `PASS` if the app only launches. A launch with a
debugger banner, redbox, Android compatibility dialog, or Metro warning that
blocks interaction is `FAIL` or `BLOCKED`.

## React Native-Specific Checks

Every lane report must inspect:

- React Native redboxes
- Metro bundling errors
- Nitro module install/dispatcher warnings
- duplicate native module registration
- stale `registerModelProto` or old API usage
- C++ bridge errors
- proto encode/decode errors
- model registry/storage initialization
- Android/iOS native library load failures
- whether business logic stayed in C++ instead of JS

## Validation Harness Evidence

The example app exposes a deterministic `Validation` tab for missing modality
evidence that is awkward to capture from normal chat/voice flows. The tab has
stable Mobile MCP targets named `validation-action-<action-id>` and emits one
Metro JSON line per tap with this prefix:

```text
[RN_VALIDATION_ACTION]
```

Capture screenshots of `validation-harness-screen`, the tapped action, and
`validation-latest-record`, then copy the matching Metro line into the lane's
`actions.jsonl`. Required actions:

- `structured.extract_fixture`
- `structured.generate_fixture`
- `tools.get_device_label`
- `vad.synthetic_silence`
- `vad.synthetic_tone`
- `lora.list`
- `lora.compatibility`
- `lora.apply_fixture`
- `lora.remove_fixture`
- `pluginloader.snapshot`
- `pluginloader.load_empty_error`

`pluginloader.load_empty_error` is expected to produce an error record; count it
as evidence only when the record status is `EXPECTED_ERROR`. Other failures are
lane findings, not passes.
