# Bundled Models Guide

This guide explains how to add pre-trained models directly to your app bundle for instant availability without downloads.

## Overview

Bundled models are ML models that ship with your app, providing:
- **Instant availability** - No download required
- **Offline access** - Works without internet
- **Predictable performance** - Model is always available
- **Reduced bandwidth** - No need to download large files

## Adding a Bundled Model

### Step 1: Prepare Your Model

1. Download or obtain your `.mlpackage` or `.mlmodel` file
2. Ensure the model is compatible with your target framework
3. Test the model locally to verify it works

### Step 2: Add Model to Xcode Project

1. **Open your project** in Xcode (`RunAnywhereAI.xcworkspace`)
2. **Right-click** on `RunAnywhereAI/Models` folder in the navigator
3. Select **"Add Files to 'RunAnywhereAI'..."**
4. Navigate to and select your model file/folder
5. **Important settings**:
   - ✅ **Create folder references** (for .mlpackage)
   - ✅ **Add to targets: RunAnywhereAI**
6. Click **Add**

### Step 3: Register Model in BundledModelsService

Edit `Services/BundledModelsService.swift`:

```swift
var bundledModels: [ModelInfo] {
    var models: [ModelInfo] = []
    
    // Example: OpenELM Model
    if let openELMPath = Bundle.main.path(forResource: "OpenELM-270M-Instruct-128-float32", ofType: "mlpackage") {
        models.append(ModelInfo(
            id: "openelm-270m-bundled-st",
            name: "OpenELM-270M-Instruct-128-float32",
            path: openELMPath,
            format: .mlPackage,
            size: "540 MB",
            framework: .swiftTransformers,
            quantization: "Float32",
            contextLength: 2048,
            isLocal: true,
            description: "Your model description"
        ))
    }
    
    // Add your new model here
    if let yourModelPath = Bundle.main.path(forResource: "YourModelName", ofType: "mlpackage") {
        models.append(ModelInfo(
            id: "your-model-id",
            name: "Your Model Name",
            path: yourModelPath,
            format: .mlPackage,  // or .coreML, .mlx, etc.
            size: "XXX MB",
            framework: .coreML,  // or .swiftTransformers, .mlx, etc.
            quantization: "FP16", // or appropriate quantization
            contextLength: 2048,
            isLocal: true,
            description: "Description of your model"
        ))
    }
    
    return models
}
```

### Step 4: Build and Test

1. **Clean Build Folder**: Product → Clean Build Folder (⇧⌘K)
2. **Build**: Product → Build (⌘B)
3. **Run** the app and verify your model appears

## Model Formats and Frameworks

### Supported Formats
- `.mlpackage` - Modern Core ML package format (recommended)
- `.mlmodel` - Legacy Core ML format
- `.mlmodelc` - Compiled Core ML model
- `.gguf` - GGML format for llama.cpp
- `.onnx` - ONNX Runtime format

### Framework Compatibility
- **Core ML**: `.mlpackage`, `.mlmodel`, `.mlmodelc`
- **Swift Transformers**: `.mlpackage` with proper metadata
- **MLX**: Directory with weights and config
- **ONNX Runtime**: `.onnx` files
- **llama.cpp**: `.gguf` files

## Managing Large Files with Git

### Excluding Model Weights

The `.gitignore` is configured to exclude large weight files:
```
# ML Model Weights
weight.bin
*/weight.bin
**/*.mlpackage/Data/com.apple.CoreML/weight.bin
*.mlmodelc/coremldata.bin
```

### Git LFS for Models (Optional)

If you want to track models in git, use Git LFS:
```bash
# Install Git LFS
brew install git-lfs
git lfs install

# Track model files
git lfs track "*.mlpackage/**"
git lfs track "*.mlmodel"
git lfs track "*.gguf"

# Add and commit
git add .gitattributes
git add YourModel.mlpackage
git commit -m "Add bundled model with Git LFS"
```

## Best Practices

### 1. Model Size Considerations
- Keep bundled models under 200MB when possible
- Consider app size limits (App Store has restrictions)
- Use quantization to reduce model size

### 2. Model Organization
```
RunAnywhereAI/
├── Models/
│   ├── OpenELM-270M-Instruct-128-float32.mlpackage/
│   ├── YourModel.mlpackage/
│   └── README.md (document your models)
```

### 3. Testing Bundled Models
- Test on actual devices (not just simulator)
- Verify models load correctly on first launch
- Test app size and installation time

### 4. Updating Bundled Models
To update a bundled model:
1. Replace the model file in Xcode
2. Update version/metadata in BundledModelsService
3. Clean build and test thoroughly

## Troubleshooting

### Model Not Showing Up
1. Check Xcode target membership
2. Verify Bundle.main.path returns non-nil
3. Check console logs for errors
4. Ensure model format matches framework

### Build Errors
1. Clean derived data: `rm -rf ~/Library/Developer/Xcode/DerivedData`
2. Clean build folder in Xcode
3. Restart Xcode

### Runtime Errors
1. Check model compatibility with framework
2. Verify model inputs/outputs match expectations
3. Check device capabilities (Neural Engine, memory)

## Example: Adding a New GGUF Model

```swift
// In BundledModelsService.swift
if let llamaPath = Bundle.main.path(forResource: "tinyllama-1.1b", ofType: "gguf") {
    models.append(ModelInfo(
        id: "tinyllama-bundled",
        name: "TinyLlama 1.1B",
        path: llamaPath,
        format: .gguf,
        size: "650 MB",
        framework: .llamaCpp,
        quantization: "Q4_K_M",
        contextLength: 2048,
        isLocal: true,
        description: "Compact but capable language model"
    ))
}
```

## Security Considerations

- Bundled models are part of your app binary
- They can be extracted by users
- Don't bundle proprietary/sensitive models
- Consider encryption for sensitive models

## Performance Tips

1. **Lazy Loading**: Models are loaded on-demand, not at app launch
2. **Memory Management**: Unload models when not in use
3. **Background Loading**: Load models asynchronously to avoid UI freezes

## Conclusion

Bundled models provide the best user experience for on-device AI by eliminating download times and ensuring models are always available. Follow this guide to add your own models to the app bundle.