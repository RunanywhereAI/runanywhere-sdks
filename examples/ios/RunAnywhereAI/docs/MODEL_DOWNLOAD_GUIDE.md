# Model Download Guide

This guide explains how to use the on-demand model download feature in the RunAnywhereAI iOS app.

## Overview

The app implements Method 2 from the Model Integration Guide: **On-Demand Download**. All model URLs are centrally managed in `ModelURLRegistry.swift`, making it easy to update or add new models.

## Features

### 1. Centralized Model URL Registry

All model download URLs are stored in a single location:
- **Location**: `Services/ModelManagement/ModelURLRegistry.swift`
- **Organized by Framework**: Core ML, MLX, ONNX Runtime, TensorFlow Lite, llama.cpp
- **Easy to Update**: Simply modify the arrays in ModelURLRegistry to add/update URLs

### 2. Model Download Manager

The `ModelDownloadManager` provides:
- Progress tracking with speed and time remaining
- Pause/Resume functionality
- Background download support
- Automatic unzipping for compressed models
- Checksum verification (when SHA256 provided)
- Storage space checking
- Concurrent downloads support

### 3. User Interface

Access model downloads through:
1. **Settings → Model Management → Download Models**
2. **Models Tab → + Button**

## How to Use

### Download a Model

1. Open the app and go to Settings
2. Tap "Model Management" → "Download Models"
3. Select a framework (Core ML, MLX, etc.)
4. Choose a model from the list
5. Tap "Download Model"

### Monitor Downloads

1. Go to Settings → "Download Manager"
2. View active downloads with:
   - Progress percentage
   - Download speed
   - Time remaining
   - Pause/Resume/Cancel options

### Manage Model URLs

1. Go to Settings → "Model URLs"
2. View all available models by framework
3. Add custom model URLs
4. Export/Import URL configurations

## Adding New Models

### Method 1: Edit ModelURLRegistry.swift

```swift
// In ModelURLRegistry.swift, add to the appropriate array:

let coreMLModels = [
    // ... existing models ...
    ModelDownloadInfo(
        id: "new-model-id",
        name: "NewModel.mlpackage",
        url: URL(string: "https://example.com/model.zip")!,
        sha256: "optional-sha256-hash",
        requiresUnzip: true
    )
]
```

### Method 2: Add Custom URLs in App

1. Go to Settings → Model URLs
2. Tap "Add Custom Model URL"
3. Enter:
   - Model ID (unique identifier)
   - Model Name (with file extension)
   - Download URL (direct link)
4. Save

### Method 3: Import URL Configuration

Create a JSON file with custom models:

```json
{
    "custom": [
        {
            "id": "custom-model-1",
            "name": "CustomModel.gguf",
            "url": "https://example.com/model.gguf",
            "sha256": null,
            "requiresUnzip": false,
            "requiresAuth": false,
            "alternativeURLs": []
        }
    ]
}
```

Then import it through Settings → Model URLs → Import URL Registry.

## Supported Model Formats

### Core ML
- `.mlpackage` (preferred, usually zipped)
- `.mlmodel` (legacy format)

### MLX
- Directory with `.safetensors` files (tar.gz archive)
- Requires `config.json` and `tokenizer.json`

### ONNX Runtime
- `.onnx` files
- `.ort` optimized runtime format

### TensorFlow Lite
- `.tflite` files

### llama.cpp
- `.gguf` files (GGUF format)
- Direct download, no unzipping needed

## Download Storage

Models are stored in:
```
Documents/Models/{Framework}/
├── Core ML/
│   └── GPT2.mlpackage/
├── MLX/
│   └── mistral-7b/
├── ONNX Runtime/
│   └── phi3.onnx
└── ...
```

## Tokenizer Downloads

For models that require separate tokenizer files, the download manager automatically:
1. Downloads the main model
2. Checks if tokenizers are needed
3. Downloads tokenizer files to the same directory

## Error Handling

The download manager handles:
- **Insufficient Storage**: Checks available space before download
- **Network Errors**: Shows user-friendly error messages
- **Corrupted Downloads**: Verifies checksums when available
- **Resume Failed Downloads**: Supports resuming interrupted downloads

## Best Practices

1. **WiFi Only**: Large model downloads use WiFi only by default
2. **Storage Management**: Requires 2x model size in free space
3. **Background Downloads**: Continue even if app is backgrounded
4. **Verification**: Add SHA256 hashes for security

## Troubleshooting

### "Insufficient Storage"
- Free up space (need 2x model size)
- Delete unused models from Models tab

### "Download Failed"
- Check internet connection
- Try alternative URL if available
- Verify URL is direct download link

### "Unzip Failed"
- Ensure downloaded file is complete
- Check file format matches expected type

### "Model Not Compatible"
- Verify model format matches framework
- Check model architecture compatibility

## Currently Available Models

Based on verification, here are the models with working download URLs:

### ONNX Runtime
- **Phi-3 Mini** (CPU INT4 optimized)
  - ID: `phi-3-mini-onnx`
  - Size: ~236MB
  - Direct download available

### GGUF (llama.cpp) - All verified working
- **TinyLlama 1.1B** - Compact model perfect for testing
- **Phi-3 Mini** - Microsoft's efficient model in GGUF format
- **Llama 3.2 3B** - Meta's latest small language model
- **Mistral 7B** - Popular open-source model

### Tokenizers (Working)
- **GPT-2** tokenizer files (tokenizer.json, vocab.json, merges.txt)
- **BERT** tokenizer files (tokenizer.json, vocab.txt)

## Important Notes

### Authentication Required
Many models on HuggingFace now require authentication:
- Core ML models from `coreml-community`
- MLX models (distributed as git repositories)
- Meta's Llama models
- Some ONNX and TensorFlow Lite models

### Recommended Approach

1. **For GGUF models**: Use the pre-configured URLs (all verified working)
2. **For Core ML/MLX models**: 
   - Clone the repository: `git clone https://huggingface.co/mlx-community/model-name`
   - Use the Model Import feature to add the downloaded directory
3. **For authenticated models**:
   - Download manually after logging into HuggingFace
   - Add via Custom URLs in Settings → Model URLs

### Adding Custom Models

1. Go to Settings → Model URLs
2. Tap "Add Custom Model URL"
3. Enter:
   - Model ID (unique)
   - Model Name (with extension)
   - Direct download URL
4. Save

The app will handle downloading, unzipping (if needed), and organizing the files.

## Security

- All downloads use HTTPS
- Optional SHA256 verification
- Models are sandboxed in app container
- No execution of downloaded code

## Future Enhancements

- [ ] Delta updates for model versions
- [ ] P2P model sharing between devices
- [ ] Automatic model recommendations
- [ ] Cloud backup/sync of downloaded models
- [ ] Torrent-based downloads for large models