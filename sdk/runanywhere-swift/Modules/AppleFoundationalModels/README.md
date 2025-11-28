# AppleFoundationalModels Adapter

Apple's Foundation Models adapter for the RunAnywhere SDK.

> **Note:** Package is named `AppleFoundationalModels` to avoid conflict with Apple's native `FoundationModels` framework.

## Requirements

- **iOS 26.0+** / **macOS 26.0+**
- Apple Intelligence must be enabled on the device
- Device must be eligible for Apple Intelligence

## Installation

Add this package to your project's dependencies:

```swift
dependencies: [
    .package(path: "path/to/Modules/AppleFoundationalModels"),
]

// In your target:
.product(name: "AppleFoundationalModels", package: "AppleFoundationalModels")
```

## Usage

```swift
import RunAnywhere
import FoundationModelsAdapter  // Note: import the target name, not the package name

// Register the adapter (iOS 26+ / macOS 26+ only)
#if canImport(FoundationModelsAdapter)
if #available(iOS 26.0, macOS 26.0, *) {
    await RunAnywhere.registerFramework(FoundationModelsAdapter())
}
#endif
```

## Features

- **No Model Downloads Required**: Uses Apple's built-in on-device language model
- **Privacy-First**: All processing happens on-device
- **Native Performance**: Optimized for Apple Silicon and Neural Engine
- **Streaming Support**: Real-time token streaming for responsive UI

## Model Selection

The Foundation Models adapter provides a built-in model with ID `foundation-models-default` that appears in the model selection UI for text-to-text modality.

## Availability Checks

The adapter automatically checks for:
- Device eligibility for Apple Intelligence
- Whether Apple Intelligence is enabled in Settings
- Model readiness (may need to download on first use)

## Error Handling

The adapter provides clear error messages for common issues:
- Device not eligible for Apple Intelligence
- Apple Intelligence not enabled
- Model not ready (downloading or initializing)
