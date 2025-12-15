# SwiftLint Report - RunAnywhere Swift SDK

**Generated:** 2025-12-14
**Total Issues:** 62 active violations + 67 inline suppressions

---

## Summary

| Severity | Count | Status |
|----------|-------|--------|
| **ERRORS** | 4 | Must Fix |
| **WARNINGS** | 58 | Should Fix |
| **DISABLED RULES** | 67 | Review Required |

---

## ERRORS (P0 - Must Fix Immediately)

### 1. Line Length Errors (2)

| # | File | Line | Current | Max | Status |
|---|------|------|---------|-----|--------|
| 1 | `Sources/RunAnywhere/Infrastructure/Download/Utilities/ArchiveUtility.swift` | 65 | 231 | 200 | [ ] |
| 2 | `Sources/RunAnywhere/Infrastructure/Download/Utilities/ArchiveUtility.swift` | 122 | 231 | 200 | [ ] |

**Issue:** Log messages with multiple interpolated values exceeding 200 characters.

**Fix:** Break the log string into multiple lines or use a helper function.

### 2. Identifier Name Errors (2)

| # | File | Line | Identifier | Issue | Status |
|---|------|------|------------|-------|--------|
| 3 | `Sources/RunAnywhere/Foundation/DependencyInjection/ServiceContainer.swift` | 110 | `_configurationService` | Leading underscore | [ ] |
| 4 | `Sources/RunAnywhere/Foundation/DependencyInjection/ServiceContainer.swift` | 123 | `_modelInfoService` | Leading underscore | [ ] |

**Issue:** Variable names starting with underscore violate identifier naming rules.

**Fix:** Rename to `backingConfigurationService` and `backingModelInfoService` or add to excluded identifiers in `.swiftlint.yml`.

---

## WARNINGS - Superfluous Disable Commands (19)

These `swiftlint:disable` comments are **no longer needed** because the code no longer triggers the rule.

| # | File | Line | Disabled Rule | Status |
|---|------|------|---------------|--------|
| 1 | `Sources/WhisperKitTranscription/WhisperKitStorageStrategy.swift` | 209 | `function_parameter_count` | [ ] |
| 2 | `Sources/WhisperKitTranscription/WhisperKitStorageStrategy.swift` | 260 | `function_parameter_count` | [ ] |
| 3 | `Sources/WhisperKitTranscription/WhisperKitStorageStrategy.swift` | 317 | `function_parameter_count` | [ ] |
| 4 | `Sources/ONNXRuntime/ONNXSTTService.swift` | 1 | `file_length` | [ ] |
| 5 | `Sources/ONNXRuntime/ONNXSTTService.swift` | 8 | `type_body_length` | [ ] |
| 6 | `Sources/RunAnywhere/Features/VAD/Services/SimpleEnergyVADService.swift` | 1 | `file_length` | [ ] |
| 7 | `Sources/RunAnywhere/Features/VAD/Services/SimpleEnergyVADService.swift` | 15 | `type_body_length` | [ ] |
| 8 | `Sources/RunAnywhere/Public/RunAnywhere.swift` | 1 | `file_length` | [ ] |
| 9 | `Sources/RunAnywhere/Public/RunAnywhere.swift` | 10 | `type_body_length` | [ ] |
| 10 | `Sources/RunAnywhere/Public/RunAnywhere.swift` | 355 | `function_parameter_count` | [ ] |
| 11 | `Sources/RunAnywhere/Foundation/DependencyInjection/ServiceContainer.swift` | 1 | `file_length` | [ ] |
| 12 | `Sources/RunAnywhere/Foundation/DependencyInjection/ServiceContainer.swift` | 7 | `type_body_length` | [ ] |
| 13 | `Sources/RunAnywhere/Infrastructure/Download/Services/AlamofireDownloadService.swift` | 1 | `file_length` | [ ] |
| 14 | `Sources/RunAnywhere/Infrastructure/Download/Services/AlamofireDownloadService.swift` | 59 | `function_body_length` | [ ] |
| 15 | `Sources/RunAnywhere/Infrastructure/Logging/SDKLogger.swift` | 62 | `function_body_length` | [ ] |
| 16 | `Sources/RunAnywhere/Infrastructure/Analytics/Services/DevAnalyticsSubmissionService.swift` | 75 | `function_parameter_count` | [ ] |
| 17 | `Sources/RunAnywhere/Infrastructure/Logging/Services/DefaultLoggingService.swift` | 151 | `prefer_concrete_types` | [ ] |

**Action:** Remove these disable comments entirely.

---

## WARNINGS - Force Unwrapping (6)

| # | File | Line | Code Pattern | Status |
|---|------|------|--------------|--------|
| 1 | `Sources/RunAnywhere/Features/LLM/Analytics/GenerationAnalyticsService.swift` | 70 | Force unwrap | [ ] |
| 2 | `Sources/RunAnywhere/Features/TTS/Models/TTSOutput.swift` | 62 | Force unwrap | [ ] |
| 3 | `Sources/RunAnywhere/Public/Extensions/RunAnywhere+VoiceAgent.swift` | 48 | `sttId!` | [ ] |
| 4 | `Sources/RunAnywhere/Public/Extensions/RunAnywhere+VoiceAgent.swift` | 52 | `llmId!` | [ ] |
| 5 | `Sources/RunAnywhere/Public/Extensions/RunAnywhere+VoiceAgent.swift` | 56 | `ttsId!` | [ ] |

**Note:** Items 3-5 also have `avoid_implicitly_unwrapped_optionals` warnings on the same lines.

**Fix:** Use optional binding (`if let` / `guard let`) or nil-coalescing operator (`??`).

---

## WARNINGS - Line Length (10)

| # | File | Line | Current | Max | Status |
|---|------|------|---------|-----|--------|
| 1 | `Sources/FoundationModelsAdapter/FoundationModelsServiceProvider.swift` | 90 | 163 | 150 | [ ] |
| 2 | `Sources/RunAnywhere/Features/LLM/Analytics/LLMEvent.swift` | 125 | 152 | 150 | [ ] |
| 3 | `Sources/RunAnywhere/Infrastructure/FileManagement/Services/SimplifiedFileManager.swift` | 91 | 156 | 150 | [ ] |
| 4 | `Sources/RunAnywhere/Infrastructure/ModelManagement/Services/RegistryService.swift` | 321 | 157 | 150 | [ ] |
| 5 | `Sources/RunAnywhere/Infrastructure/Device/Services/DeviceRegistrationService.swift` | 198 | 154 | 150 | [ ] |
| 6 | `Sources/RunAnywhere/Infrastructure/Download/Utilities/ArchiveUtility.swift` | 512 | 174 | 150 | [ ] |
| 7 | `Sources/FoundationModelsAdapter/FoundationModelsService.swift` | 141 | 169 | 150 | [ ] |
| 8 | `Sources/FoundationModelsAdapter/FoundationModelsService.swift` | 188 | 169 | 150 | [ ] |

**Fix:** Break long lines using line continuation or extract into variables.

---

## WARNINGS - Function/Type Complexity (6)

### Function Body Length

| # | File | Line | Current | Max | Status |
|---|------|------|---------|-----|--------|
| 1 | `Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift` | 73 | 94 lines | 80 | [ ] |
| 2 | `Sources/RunAnywhere/Public/RunAnywhere.swift` | 169 | 120 lines | 80 | [ ] |
| 3 | `Sources/RunAnywhere/Infrastructure/Download/Services/AlamofireDownloadService.swift` | 85 | 93 lines | 80 | [ ] |

### Cyclomatic Complexity

| # | File | Line | Current | Max | Status |
|---|------|------|---------|-----|--------|
| 4 | `Sources/RunAnywhere/Features/VoiceAgent/VoiceAgentCapability.swift` | 73 | 16 | 15 | [ ] |

### Type Body Length

| # | File | Line | Current | Max | Status |
|---|------|------|---------|-----|--------|
| 5 | `Sources/RunAnywhere/Infrastructure/Download/Services/AlamofireDownloadService.swift` | 8 | 425 lines | 400 | [ ] |

### Function Parameter Count

| # | File | Line | Current | Max | Status |
|---|------|------|---------|-----|--------|
| 6 | `Sources/RunAnywhere/Infrastructure/Analytics/Services/DevAnalyticsSubmissionService.swift` | 149 | 9 params | 8 | [ ] |

**Fix:** Extract helper methods, use configuration objects, or split into smaller components.

---

## WARNINGS - Any/AnyObject Type Usage (12)

### avoid_any_type

| # | File | Line | Status |
|---|------|------|--------|
| 1 | `Sources/LlamaCPPRuntime/LlamaCPPService.swift` | 225 | [ ] |
| 2 | `Sources/RunAnywhere/Core/Capabilities/ModelLifecycleManager.swift` | 28 | [ ] |
| 3 | `Sources/RunAnywhere/Core/Capabilities/ModelLifecycleManager.swift` | 84 | [ ] |
| 4 | `Sources/RunAnywhere/Core/Capabilities/ManagedLifecycle.swift` | 62 | [ ] |
| 5 | `Sources/RunAnywhere/Infrastructure/FileManagement/Utilities/FileOperationsUtilities.swift` | 123 | [ ] |
| 6 | `Sources/RunAnywhere/Infrastructure/Device/Services/DeviceRegistrationService.swift` | 260 | [ ] |
| 7 | `Sources/RunAnywhere/Infrastructure/Analytics/Services/DevAnalyticsSubmissionService.swift` | 224 | [ ] |

### avoid_any_object

| # | File | Line | Status |
|---|------|------|--------|
| 8 | `Sources/RunAnywhere/Features/SpeakerDiarization/Protocol/SpeakerDiarizationService.swift` | 14 | [ ] |
| 9 | `Sources/RunAnywhere/Features/LLM/Protocol/LLMService.swift` | 11 | [ ] |
| 10 | `Sources/RunAnywhere/Infrastructure/FileManagement/Protocol/FileManagementService.swift` | 19 | [ ] |
| 11 | `Sources/RunAnywhere/Infrastructure/Logging/Protocol/LoggingService.swift` | 13 | [ ] |
| 12 | `Sources/RunAnywhere/Infrastructure/Logging/Protocol/LogDestination.swift` | 12 | [ ] |

**Fix:** Define concrete types or protocols. For protocol class constraints, this may be necessary.

---

## WARNINGS - Miscellaneous (11)

### for_where (3)

| # | File | Line | Status |
|---|------|------|--------|
| 1 | `Sources/RunAnywhere/Core/Module/ModuleRegistry.swift` | 119 | [ ] |
| 2 | `Sources/RunAnywhere/Public/Extensions/RunAnywhere+Frameworks.swift` | 76 | [ ] |
| 3 | `Sources/RunAnywhere/Infrastructure/ModelManagement/Services/ModelExtractionService.swift` | 183 | [ ] |

**Fix:** Change `for item in collection { if condition { ... } }` to `for item in collection where condition { ... }`

### redundant_discardable_let (3)

| # | File | Line | Status |
|---|------|------|--------|
| 4 | `Sources/RunAnywhere/Public/RunAnywhere.swift` | 251 | [ ] |
| 5 | `Sources/RunAnywhere/Public/RunAnywhere.swift` | 325 | [ ] |
| 6 | `Sources/RunAnywhere/Data/Network/Services/AuthenticationService.swift` | 38 | [ ] |

**Fix:** Change `let _ = foo()` to `_ = foo()`

### attributes (2)

| # | File | Line | Status |
|---|------|------|--------|
| 7 | `Sources/RunAnywhere/Core/Module/ModuleRegistry.swift` | 281 | [ ] |
| 8 | `Sources/RunAnywhere/Infrastructure/FileManagement/Protocol/FileManagementService.swift` | 39 | [ ] |

**Fix:** Move attributes to their own lines for functions/types.

### sorted_imports (2)

| # | File | Line | Status |
|---|------|------|--------|
| 9 | `Sources/RunAnywhere/Infrastructure/FileManagement/Protocol/FileManagementService.swift` | 16 | [ ] |
| 10 | `Sources/RunAnywhere/Infrastructure/Download/Utilities/ArchiveUtility.swift` | 2 | [ ] |

**Fix:** Sort import statements alphabetically.

### orphaned_doc_comment (1)

| # | File | Line | Status |
|---|------|------|--------|
| 11 | `Sources/RunAnywhere/Infrastructure/Logging/Models/Domain/LogEntry.swift` | 30 | [ ] |

**Fix:** Attach the doc comment to a declaration or remove it.

---

## DISABLED RULES IN CODE (67 Total)

### Superfluous - Should Remove (19)

*Listed in "Superfluous Disable Commands" section above*

### Legitimate - API Requirements (12)

These are **acceptable** suppressions for Swift API requirements:

| File | Line | Rule | Reason |
|------|------|------|--------|
| `STTService.swift` | 13 | `avoid_any_object` | Protocol class constraint required |
| `VADService.swift` | 12 | `avoid_any_object` | Protocol class constraint required |
| `TTSService.swift` | 11 | `avoid_any_object` | Protocol class constraint required |
| `KeychainManager.swift` | 164 | `avoid_any_object` | Keychain API requirement |
| `KeychainManager.swift` | 204, 205 | `prefer_concrete_types`, `avoid_any_type` | Keychain API requirement |

### Legitimate - JSON/API Work (15)

These handle dynamic JSON data where `[String: Any]` is necessary:

| File | Lines | Rule | Reason |
|------|-------|------|--------|
| `APIClient.swift` | 84, 87, 136, 139 | `avoid_any_type` | JSON error parsing |
| `ConfigurationConstants.swift` | 89, 96, 99 | `avoid_any_type` | JSON config parsing |
| `RemoteTelemetryDataSource.swift` | 44 | `prefer_concrete_types`, `avoid_any_type` | API response handling |
| `RemoteModelInfoDataSource.swift` | 44 | `prefer_concrete_types`, `avoid_any_type` | API response handling |
| `RemoteConfigurationDataSource.swift` | 54 | `prefer_concrete_types`, `avoid_any_type` | API response handling |

### Legitimate - Logging API (10)

Logging metadata commonly uses `[String: Any]` for flexibility:

| File | Lines | Rule |
|------|-------|------|
| `SDKLogger.swift` | 23, 28, 33, 38, 43, 48, 74, 129 | `prefer_concrete_types`, `avoid_any_type` |
| `DefaultLoggingService.swift` | 70, 138, 141, 151 | `prefer_concrete_types`, `avoid_any_type` |
| `Logging.swift` | 79 | `prefer_concrete_types`, `avoid_any_type` |
| `LogEntry.swift` | 38 | `prefer_concrete_types`, `avoid_any_type` |
| `LoggingService.swift` | 36 | `prefer_concrete_types`, `avoid_any_type` |

### Legitimate - Database/Migrations (11)

| File | Lines | Rule | Reason |
|------|-------|------|--------|
| `Migration001_InitialSchema.swift` | 5 | `type_name` | Migration naming convention |
| `Migration001_InitialSchema.swift` | 7 | `function_body_length` | SQL schema requires long function |
| `Migration001_InitialSchema.swift` | 13, 42, 109, 126, 143, 176, 189 | `identifier_name` | SQL column/table names |
| `LocalModelInfoDataSource.swift` | 199 | `identifier_name` | Database field naming |
| `DataSource.swift` | 55 | `prefer_concrete_types`, `avoid_any_type` | Generic data source protocol |
| `SDKErrorProtocol.swift` | 105 | `prefer_concrete_types`, `avoid_any_type` | Error metadata |

---

## Recommended Actions

### Priority 1 - Fix Errors (4 items)
1. [ ] Fix line length errors in `ArchiveUtility.swift` (lines 65, 122)
2. [ ] Rename `_configurationService` in `ServiceContainer.swift`
3. [ ] Rename `_modelInfoService` in `ServiceContainer.swift`

### Priority 2 - Remove Superfluous Disables (19 items)
1. [ ] Remove all 19 superfluous disable commands listed above

### Priority 3 - Fix Force Unwrapping (6 items)
1. [ ] Fix force unwrapping in `GenerationAnalyticsService.swift`
2. [ ] Fix force unwrapping in `TTSOutput.swift`
3. [ ] Fix force unwrapping in `RunAnywhere+VoiceAgent.swift` (3 locations)

### Priority 4 - Fix Line Length Warnings (10 items)
1. [ ] Fix all 10 line length warnings

### Priority 5 - Fix Complexity Issues (6 items)
1. [ ] Refactor `VoiceAgentCapability.swift:73` - reduce complexity and length
2. [ ] Refactor `RunAnywhere.swift:169` - reduce function length
3. [ ] Consider splitting `AlamofireDownloadService` into smaller components

### Priority 6 - Fix Miscellaneous (11 items)
1. [ ] Convert 3 `for` loops to use `where` clause
2. [ ] Fix 3 redundant discardable let statements
3. [ ] Fix 2 attribute placement issues
4. [ ] Sort imports in 2 files
5. [ ] Fix orphaned doc comment in `LogEntry.swift`

### Priority 7 - Review Any/AnyObject Usage (12 items)
1. [ ] Review each `Any`/`AnyObject` usage and determine if a concrete type can be used
2. [ ] For protocol class constraints (`AnyObject`), these are likely necessary

---

## Configuration Reference

Current `.swiftlint.yml` thresholds:

```yaml
line_length:
  warning: 150
  error: 200

file_length:
  warning: 800
  error: 1500

function_body_length:
  warning: 80
  error: 300

function_parameter_count:
  warning: 8
  error: 15

type_body_length:
  warning: 400
  error: 600

cyclomatic_complexity:
  warning: 15
  error: 30
```

---

## Running SwiftLint

```bash
# Run lint check
cd sdk/runanywhere-swift
swiftlint lint

# Run with JSON output
swiftlint lint --reporter json

# Auto-fix correctable issues
swiftlint --fix

# Run analyzer (requires compilation log)
swiftlint analyze --compiler-log-path <path-to-xcodebuild-log>
```
