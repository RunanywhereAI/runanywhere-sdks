# Local iOS Binaries

This directory is used for **local development mode** when testing with locally-built XCFrameworks.

## Usage

1. Set the `RA_TEST_LOCAL=1` environment variable or create a `.testlocal` file in the `packages/native/` directory
2. Copy the following XCFrameworks to this directory:
   - `RACommons.xcframework` (required)
   - `RABackendLlamaCPP.xcframework` (optional, for LLM)
   - `RABackendONNX.xcframework` (optional, for STT/TTS/VAD)
   - `onnxruntime.xcframework` (optional, required if using ONNX)

## Building Locally

To build the XCFrameworks locally from `runanywhere-commons`:

```bash
cd /path/to/runanywhere-commons
./scripts/build-ios.sh
```

Then copy the output from `runanywhere-commons/dist/ios/` to this directory.

## Remote Mode (Default)

When `RA_TEST_LOCAL` is not set, the podspec will automatically download the XCFrameworks from GitHub releases:
- RACommons: https://github.com/RunanywhereAI/runanywhere-sdks/releases
- Backend frameworks: Same repository
- onnxruntime: https://github.com/RunanywhereAI/runanywhere-binaries/releases
