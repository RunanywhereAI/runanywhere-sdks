## 0.16.0

### Added
- Initial experimental Android-only Qualcomm Genie backend shell for RunAnywhere Flutter SDK
- `Genie.register()` / `Genie.unregister()` for C++ backend registration when Qualcomm Genie SDK-built binaries are present
- `Genie.addModel()` convenience method for NPU model registration
- `Genie.isAvailable` platform check (Android/Snapdragon only)
- `Genie.canHandle()` model compatibility check
