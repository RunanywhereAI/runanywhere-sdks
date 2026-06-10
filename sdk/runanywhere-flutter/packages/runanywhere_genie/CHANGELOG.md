## 0.19.13

### Changed
- Kept the experimental Qualcomm Genie backend shell aligned with the
  RunAnywhere Flutter SDK 0.19.13 release.
- Clarified that functional routing still requires Qualcomm Genie SDK-backed
  native binaries on supported Android/Snapdragon devices.

## 0.16.0

### Added
- Initial experimental Android-only Qualcomm Genie backend shell for RunAnywhere Flutter SDK
- `Genie.register()` / `Genie.unregister()` for C++ backend registration when Qualcomm Genie SDK-built binaries are present
- `Genie.addModel()` convenience method for NPU model registration
- `Genie.isAvailable` platform check (Android/Snapdragon only)
- `Genie.canHandle()` model compatibility check
