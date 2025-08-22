# WhisperKit Module Extraction Plan

## Objective
Extract WhisperKitService and WhisperKitAdapter from the sample iOS app into a standalone Swift Package module, similar to FluidAudioDiarization module structure. The module should be self-contained and ready to use with minimal integration code.

## Current State Analysis

### Components to Extract
1. **WhisperKitService.swift** (504 lines)
   - Location: `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/WhisperKit/WhisperKitService.swift`
   - Core transcription service implementation
   - Implements VoiceService protocol
   - Contains VoiceError enum

2. **WhisperKitAdapter.swift** (144 lines)
   - Location: `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/WhisperKit/WhisperKitAdapter.swift`
   - Framework adapter for SDK integration
   - Implements UnifiedFrameworkAdapter protocol
   - Manages service caching and lifecycle

3. **WhisperKitDownloadStrategy.swift** (231 lines)
   - Location: `examples/ios/RunAnywhereAI/RunAnywhereAI/Core/Services/Downloading/WhisperKitDownloadStrategy.swift`
   - Custom download strategy for WhisperKit models
   - Handles multi-file model downloads from HuggingFace
   - Implements DownloadStrategy protocol

### Dependencies
- WhisperKit framework
- AVFoundation (system framework)
- RunAnywhereSDK (local package)
- os.log for logging

## Target Structure
Create a new module at: `sdk/runanywhere-swift/Modules/WhisperKitTranscription/`

## Implementation Steps

### 1. Create Module Structure
- [ ] Create directory structure at `sdk/runanywhere-swift/Modules/WhisperKitTranscription/`
- [ ] Create Package.swift with all dependencies
- [ ] Create Sources/WhisperKitTranscription directory
- [ ] Create Tests/WhisperKitTranscriptionTests directory
- [ ] Add README.md with usage instructions

### 2. Port All Components
- [ ] Move WhisperKitService.swift to the module
- [ ] Move WhisperKitAdapter.swift to the module
- [ ] Move WhisperKitDownloadStrategy.swift to the module
- [ ] Extract VoiceError enum to separate file for clarity
- [ ] Adjust all access modifiers to `public` for module boundary
- [ ] Ensure proper module exports in main file
- [ ] Create public initializers where needed

### 3. Configure Dependencies
```swift
// Package.swift dependencies
dependencies: [
    .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.10.2"),
    .package(path: "../../../sdk/runanywhere-swift"),
]
```

### 4. Simplify Sample App Integration
After extraction, the sample app will only need:
```swift
import WhisperKitTranscription

// In AppDelegate or initialization
RunAnywhereSDK.shared.registerFrameworkAdapter(WhisperKitAdapter.shared)
```

### 5. Module Enhancements
- [ ] Add configuration options for WhisperKit models
- [ ] Include default model mappings
- [ ] Add convenience initializers
- [ ] Ensure proper cleanup and memory management
- [ ] Add comprehensive error handling

### 6. Update Sample App
- [ ] Remove WhisperKit directory from sample app (`RunAnywhereAI/Core/Services/WhisperKit/`)
- [ ] Remove WhisperKitDownloadStrategy.swift from Downloading directory
- [ ] Update Xcode project file to add WhisperKitTranscription module dependency
  - Add local Swift Package dependency pointing to `sdk/runanywhere-swift/Modules/WhisperKitTranscription`
  - Remove references to deleted WhisperKit files from project navigator
- [ ] Update RunAnywhereAIApp.swift:
  - Change `import WhisperKit` to `import WhisperKitTranscription` if present
  - Ensure adapter registration remains: `RunAnywhereSDK.shared.registerFrameworkAdapter(WhisperKitAdapter.shared)`
  - Ensure download strategy registration: `RunAnywhereSDK.shared.registerDownloadStrategy(WhisperKitDownloadStrategy())`
- [ ] Remove any direct WhisperKit framework dependency from Xcode project
- [ ] Update any other files that import WhisperKit components
- [ ] Verify the app builds and runs with the module
- [ ] Ensure voice transcription still works in TranscriptionView
- [ ] Verify minimal integration code (just 2 lines in RunAnywhereAIApp.swift)

### 7. Testing & Validation
- [ ] Create unit tests for adapter
- [ ] Create integration tests for service
- [ ] Build module independently: `swift build`
- [ ] Test in sample app with all transcription scenarios
- [ ] Verify streaming transcription works
- [ ] Test model switching functionality

## Module Package Structure
```
WhisperKitTranscription/
├── Package.swift
├── README.md
├── Sources/
│   └── WhisperKitTranscription/
│       ├── WhisperKitTranscription.swift     // Main module exports
│       ├── WhisperKitService.swift           // Core service
│       ├── WhisperKitAdapter.swift           // SDK adapter
│       ├── WhisperKitDownloadStrategy.swift  // Model download handler
│       ├── VoiceError.swift                  // Error definitions
│       └── ModelConfiguration.swift          // Model mappings
└── Tests/
    └── WhisperKitTranscriptionTests/
        ├── WhisperKitServiceTests.swift
        ├── WhisperKitAdapterTests.swift
        ├── DownloadStrategyTests.swift
        └── IntegrationTests.swift
```

## Package.swift Template
```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "WhisperKitTranscription",
    platforms: [
        .iOS(.v13),
        .macOS(.v11),
    ],
    products: [
        .library(
            name: "WhisperKitTranscription",
            targets: ["WhisperKitTranscription"]
        ),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit", from: "0.10.2"),
        .package(path: "../../../"),  // RunAnywhereSDK
    ],
    targets: [
        .target(
            name: "WhisperKitTranscription",
            dependencies: [
                "WhisperKit",
                .product(name: "RunAnywhereSDK", package: "runanywhere-swift"),
            ]
        ),
        .testTarget(
            name: "WhisperKitTranscriptionTests",
            dependencies: ["WhisperKitTranscription"]
        ),
    ]
)
```

## Xcode Project Configuration Steps
After creating the module, the sample app's Xcode project needs to be updated:

1. **Add Local Package Dependency**:
   - Open RunAnywhereAI.xcodeproj in Xcode
   - File → Add Package Dependencies
   - Click "Add Local..." button
   - Navigate to `sdk/runanywhere-swift/Modules/WhisperKitTranscription`
   - Add to RunAnywhereAI target

2. **Remove Old Files**:
   - Delete WhisperKit group from project navigator
   - Delete WhisperKitDownloadStrategy.swift from Downloading group
   - Remove WhisperKit package dependency if added directly

3. **Update Build Settings**:
   - Ensure module is linked to app target
   - Verify framework search paths don't include old WhisperKit paths

## Sample App Integration (After Extraction)
```swift
// AppDelegate.swift or App initialization
import RunAnywhereSDK
import WhisperKitTranscription

// Register the adapter (handles transcription)
RunAnywhereSDK.shared.registerFrameworkAdapter(WhisperKitAdapter.shared)

// Register the download strategy (handles model downloads)
RunAnywhereSDK.shared.registerDownloadStrategy(WhisperKitDownloadStrategy())

// That's it! The SDK will automatically use WhisperKit for transcription
// and handle model downloads properly
```

## Success Criteria
- [ ] Module builds independently without errors
- [ ] Sample app integration requires only 2-3 lines of code
- [ ] All transcription functionality works as before
- [ ] Streaming transcription maintains performance
- [ ] Module is self-contained with all necessary components
- [ ] Clean separation of concerns achieved
- [ ] No duplicate code between module and sample app
- [ ] Module can be used in other projects easily

## Implementation Notes
- Maintain singleton pattern for WhisperKitAdapter for caching
- Preserve all garbled output detection logic (lines 435-477 in WhisperKitService)
- Keep audio processing optimizations (minAudioLength, contextOverlap)
- Ensure proper memory management and cleanup (forceCleanup method)
- Maintain compatibility with existing VoiceService protocol from SDK
- WhisperKitDownloadStrategy must have public initializer
- Ensure VoiceError enum is properly exported as public
- Model path mappings should be configurable (mapModelIdToWhisperKitName method)
- Download progress handling must be preserved
- Logger subsystem should be updated to module-specific identifier
- Cache timeout mechanism (5 minutes) must be preserved
- Memory warning handling integration point must be documented

## Files Currently Using WhisperKit
Based on analysis, these files in the sample app reference WhisperKit:
- RunAnywhereAIApp.swift (lines 51, 91, 96) - adapter registration
- WhisperKitService.swift - to be moved to module
- WhisperKitAdapter.swift - to be moved to module
- WhisperKitDownloadStrategy.swift - to be moved to module

No other files directly import WhisperKit, making the extraction clean and straightforward.
