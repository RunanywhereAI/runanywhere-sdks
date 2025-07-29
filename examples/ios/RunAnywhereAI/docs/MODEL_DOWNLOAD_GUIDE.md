# Model Download Guide

This guide explains how to use the on-demand model download feature in the RunAnywhereAI iOS app.

> **Note**: For bundled models that ship with the app, see [BUNDLED_MODELS_GUIDE.md](../RunAnywhereAI/docs/BUNDLED_MODELS_GUIDE.md)

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
    ModelInfo(
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

#### Understanding .mlpackage Files

A `.mlpackage` is **not a single file** - it's actually a **directory structure** that contains all the components of a Core ML model. This format was introduced in Core ML 4 and is now the preferred format for newer models.

##### Structure of a .mlpackage:
```
ModelName.mlpackage/
├── Manifest.json                          # Package metadata
└── Data/
    └── com.apple.CoreML/
        ├── model.mlmodel                  # Model architecture (graph)
        └── weights/
            └── weight.bin                 # Trained parameters
```

##### Components explained:
1. **Manifest.json** - Contains metadata about the package version and format
2. **model.mlmodel** - The computational graph defining layers and operations
3. **weight.bin** - The actual trained weights/parameters (usually the largest file)

##### Downloading .mlpackage Models from Hugging Face:
When downloading .mlpackage models from Hugging Face, the app automatically:
1. Detects that the URL points to a .mlpackage directory
2. Lists all files within the directory structure using the HuggingFace Files API
3. Downloads each file while preserving the folder hierarchy
4. Creates the complete .mlpackage folder on device

This is why a model like OpenELM-270M shows multiple files in the download progress - it's downloading the entire directory structure, not just a single file.

##### Implementation Details:
The app uses a dedicated `HuggingFaceDirectoryDownloader` service that:
- Calls the HF API endpoint: `https://huggingface.co/api/models/{repo}/tree/main/{path}`
- Recursively lists all files and subdirectories
- Downloads each file using the resolve URL: `https://huggingface.co/{repo}/resolve/main/{path}`
- Preserves the exact directory structure locally
- Supports authentication for private repositories
- Shows progress for each individual file download

Example for OpenELM-270M-Instruct:
```
Downloading: OpenELM-270M-Instruct-128-float32.mlpackage/
├── Manifest.json (1 KB)
└── Data/
    └── com.apple.CoreML/
        ├── model.mlmodel (24 KB)
        └── weights/
            └── weight.bin (1.09 GB)
```

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

### Swift Transformers Specific Issues
Swift Transformers has very specific requirements:
- **Generic Core ML models will NOT work**
- Models must have `input_ids` and `attention_mask` inputs
- Models need embedded tokenizer configuration
- Models require Hub metadata for proper loading

To use Swift Transformers, you need models that were:
1. Converted using the `transformers-to-coreml` Space on Hugging Face
2. Exported with the `exporters` Python package with Swift Transformers support
3. Available from specialized repositories like `huggingface.co/apple/` or `huggingface.co/pcuenq/`

If you're getting array bounds crashes or initialization errors, the model is likely a generic Core ML model. Use the Core ML service instead for such models.

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

#MORE INFO

# iOS Small Language Model Download Links and Framework Guide

This comprehensive guide provides download links and deployment information for small language models across four major iOS frameworks: Core ML, MLX, ONNX Runtime, and TensorFlow Lite.

## Core ML Framework

Core ML is Apple's native machine learning framework optimized for on-device performance on Apple Silicon devices[1][2]. The framework leverages Apple's unified memory architecture and provides hardware acceleration through CPU, GPU, and Neural Engine[1][2].

### Apple's OpenELM Models

Apple has released eight small language models specifically designed for on-device use[3]. These models are available in four sizes with both pre-trained and instruction-tuned versions:

| Model Size | Parameters | Download Link | File Size |
|------------|------------|---------------|-----------|
| OpenELM-270M | 270 million | [https://huggingface.co/apple/OpenELM-270M](https://huggingface.co/apple/OpenELM-270M)[3] | 1.09 GB |
| OpenELM-450M | 450 million | [https://huggingface.co/apple/OpenELM-450M](https://huggingface.co/apple/OpenELM-450M)[3] | ~1.8 GB |
| OpenELM-1.1B | 1.1 billion | [https://huggingface.co/apple/OpenELM-1_1B](https://huggingface.co/apple/OpenELM-1_1B)[3] | ~4.3 GB |
| OpenELM-3B | 3 billion | [https://huggingface.co/apple/OpenELM-3B](https://huggingface.co/apple/OpenELM-3B)[3] | ~12 GB |

#### Instruction-Tuned Versions

All models also have instruction-tuned variants for chat applications:

- [OpenELM-270M-Instruct](https://huggingface.co/apple/OpenELM-270M-Instruct)[3]
- [OpenELM-450M-Instruct](https://huggingface.co/apple/OpenELM-450M-Instruct)[3]
- [OpenELM-1.1B-Instruct](https://huggingface.co/apple/OpenELM-1_1B-Instruct)[3]
- [OpenELM-3B-Instruct](https://huggingface.co/apple/OpenELM-3B-Instruct)[3]

### Core ML Model Gallery

Apple's official Core ML model gallery provides additional models[4]:

- **FastViT Core ML**: State-of-the-art image classification optimized for mobile deployment[4]
- **Stable Diffusion Core ML**: Image generation models converted for Apple Silicon[5]
- **Depth Anything V2 Core ML**: Advanced depth estimation models[6]

**Download Location**: [https://developer.apple.com/machine-learning/models/](https://developer.apple.com/machine-learning/models/)[4]

### Converting Models to Core ML

To convert existing models to Core ML format, use Core ML Tools[7]:

```python
pip install coremltools
```

The framework supports conversion from TensorFlow, PyTorch, scikit-learn, and other popular frameworks[7][8].

## MLX Framework

MLX is Apple's array framework designed specifically for machine learning on Apple Silicon[9][10]. It provides unified memory support and leverages Metal for GPU acceleration[11][9].

### MLX Community Models

The MLX Community on Hugging Face hosts ready-to-run models optimized for Apple Silicon:

**Main Repository**: [https://huggingface.co/mlx-community](https://huggingface.co/mlx-community)[12]

### Popular MLX Language Models

| Model Name | Size | Download Command |
|------------|------|------------------|
| Mistral-7B-Instruct | 4-bit quantized | `mlx_lm.generate --model mlx-community/Mistral-7B-Instruct-v0.3-4bit`[12] |
| Phi-3-mini | Various sizes | Available in MLX-compatible format[13][14] |
| Gemma-2B | 2 billion parameters | Available through MLX Swift examples[14] |
| Qwen models | Multiple sizes | Supported in MLX framework[14] |

### MLX Swift Integration

For iOS development, use the MLX Swift package:

**Repository**: [https://github.com/ml-explore/mlx-swift](https://github.com/ml-explore/mlx-swift)[15]

**Swift Examples**: [https://github.com/ml-explore/mlx-swift-examples](https://github.com/ml-explore/mlx-swift-examples)[16]

### Installation for iOS

Add to your Xcode project via Swift Package Manager:

```swift
dependencies: [
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.10.0")
]
```

### Example iOS Implementation

The EdgeLLM library provides a simple interface for running LLMs on iOS:

**Repository**: [https://github.com/john-rocky/EdgeLLM](https://github.com/john-rocky/EdgeLLM)[17]

```swift
import EdgeLLM

let response = try await EdgeLLM.chat("Hello, world!")
```

## TensorFlow Lite Framework

TensorFlow Lite (now called LiteRT) is Google's solution for on-device machine learning[18][19]. It supports iOS deployment with optimized performance for mobile devices[20][18].

### TensorFlow Lite Language Models

#### MediaPipe LLM Models

Google provides LLM support through MediaPipe and TensorFlow Lite[21]:

- **Gemma**: Google's small language model[21]
- **Phi-2**: Microsoft's 2.7B parameter model[21]
- **Falcon**: Efficient language model variants[21]
- **Stable LM**: Stability AI's language models[21]

**Documentation**: [https://developers.googleblog.com/en/large-language-models-on-device-with-mediapipe-and-tensorflow-lite/](https://developers.googleblog.com/en/large-language-models-on-device-with-mediapipe-and-tensorflow-lite/)[21]

### iOS Installation

Add TensorFlow Lite to your iOS project using CocoaPods[19]:

#### Swift
```ruby
pod 'TensorFlowLiteSwift'
```

#### Objective-C
```ruby
pod 'TensorFlowLiteObjC'
```

### Model Conversion

Convert existing models to TensorFlow Lite format[22]:

```python
import tensorflow as tf

# Convert from saved model
converter = tf.lite.TFLiteConverter.from_saved_model(MODEL_DIR)
tflite_model = converter.convert()

# Convert from Keras model
converter = tf.lite.TFLiteConverter.from_keras_model(model)
tflite_model = converter.convert()
```

### Pre-trained TensorFlow Lite Models

**Model Repository**: [https://github.com/iglaweb/awesome-tflite](https://github.com/iglaweb/awesome-tflite)[23]

Popular lightweight models include[24]:
- **MobileNetV2**: ~14MB, image classification[24]
- **DistilBERT**: Distilled version for text processing[24]
- **SqueezeNet**: ~5MB, image classification[24]

## ONNX Runtime Framework

ONNX Runtime provides cross-platform model deployment with iOS support[25][26]. Microsoft has optimized it for mobile deployment with ONNX Runtime Mobile[27].

### Installation for iOS

Add ONNX Runtime to your iOS project using CocoaPods[26]:

#### C/C++
```ruby
pod 'onnxruntime-c'
```

#### Objective-C
```ruby
pod 'onnxruntime-objc'
```

### Language Model Support

ONNX Runtime supports various language models optimized for mobile deployment[28][29]:

- **Phi-3-mini**: Microsoft's 3.8B parameter model with 4-bit quantization[30][28]
- **CodeLlama**: Code generation models[29]
- **Gemma**: Google's compact language models[29]
- **Mistral**: Efficient transformer models[29]

### Pre-built iOS Libraries

Ready-to-use ONNX Runtime libraries for iOS:

**Repository**: [https://huggingface.co/w11wo/ios-onnxruntime](https://huggingface.co/w11wo/ios-onnxruntime)[31]

This contains pre-built static libraries including:
- Headers for C/C++ APIs[31]
- iOS ARM64 libraries[31]
- iOS Simulator libraries[31]

### Model Conversion to ONNX

Convert models from PyTorch or TensorFlow[32]:

```python
import torch.onnx

# PyTorch to ONNX
torch.onnx.export(
    model,
    dummy_input,
    "model.onnx",
    input_names=["input"],
    output_names=["output"]
)
```

### ONNX Model Zoo

Access pre-trained models in ONNX format:

**Repository**: [https://github.com/onnx/models](https://github.com/onnx/models)[33]

## Additional Small Language Models

### Hugging Face Models

Several small language models are available for mobile deployment:

| Model | Parameters | Repository | Framework Support |
|-------|------------|------------|-------------------|
| TinyLlama | 1.1B | [GitHub](https://github.com/jzhang38/TinyLlama)[34] | Multiple |
| SmolLM | 135M-1.7B | [Ollama](https://ollama.com/library/smollm)[35] | Multiple |
| MiniCPM | 1B-4B | Various sizes[36] | Multiple |
| PhoneLM | 0.5B-1.5B | Optimized for mobile[37][38] | Multiple |

### Model Performance Comparison

For iOS deployment, consider these factors:

| Framework | Memory Usage | Performance | iOS Integration | Hardware Acceleration |
|-----------|--------------|-------------|-----------------|----------------------|
| Core ML | Optimized | Excellent | Native | Neural Engine, GPU, CPU[1] |
| MLX | Very Low | Excellent | Swift Package | Metal GPU[11] |
| TensorFlow Lite | Low | Good | CocoaPods | CoreML Delegate[19] |
| ONNX Runtime | Moderate | Good | CocoaPods | CoreML Provider[25] |

## Deployment Considerations

### Memory Requirements

Small language models for iOS typically require:
- **270M parameters**: ~1GB RAM[3]
- **450M parameters**: ~2GB RAM[3]
- **1B parameters**: ~4GB RAM[3]
- **3B parameters**: ~12GB RAM[3]

### Device Compatibility

Modern iOS devices with Apple Silicon (A14+) are recommended for optimal performance[1][11]. The Neural Engine in these devices provides hardware acceleration for ML workloads[1].

### Privacy and Security

All frameworks support on-device inference, ensuring user data privacy by avoiding cloud dependencies[1][11][18][39]. This is particularly important for applications handling sensitive information.

This comprehensive guide provides the necessary resources and download links to deploy small language models on iOS using any of the four major frameworks. Choose the framework that best fits your application's requirements for performance, integration complexity, and device compatibility.

[1] https://machinelearning.apple.com/research/core-ml-on-device-llama
[2] https://developer.apple.com/machine-learning/core-ml/
[3] https://huggingface.co/apple/OpenELM-270M
[4] https://developer.apple.com/machine-learning/models/
[5] https://github.com/apple/ml-stable-diffusion
[6] https://huggingface.co/apple
[7] https://apple.github.io/coremltools/docs-guides/source/overview-coremltools.html
[8] https://apple.github.io/coremltools/v3.4/index.html
[9] https://github.com/ml-explore/mlx
[10] https://github.com/ml-explore/mlx?tab=readme-ov-file
[11] https://opensource.apple.com/projects/mlx
[12] https://huggingface.co/mlx-community
[13] https://www.strathweb.com/2025/03/running-phi-models-on-ios-with-apple-mlx-framework/
[14] https://compiledthoughts.pages.dev/blog/integrating-mlx-local-llms-ios-apps/
[15] https://github.com/ml-explore/mlx-swift
[16] https://github.com/ml-explore/mlx-swift-examples
[17] https://github.com/john-rocky/EdgeLLM
[18] https://ai.google.dev/edge/litert
[19] https://ai.google.dev/edge/litert/ios/quickstart
[20] https://www.youtube.com/watch?v=Y2F99M0PUhE
[21] https://developers.googleblog.com/en/large-language-models-on-device-with-mediapipe-and-tensorflow-lite/
[22] https://dev.to/emmarex/deploying-machine-learning-models-on-mobile-with-tensorflow-lite-and-firebase-m-l-kit-4647
[23] https://github.com/iglaweb/awesome-tflite
[24] https://www.kaggle.com/discussions/getting-started/584414
[25] https://onnxruntime.ai/docs/build/ios.html
[26] https://onnxruntime.ai/docs/install/
[27] https://opensource.microsoft.com/blog/2020/10/12/introducing-onnx-runtime-mobile-reduced-size-high-performance-package-edge-devices/
[28] https://huggingface.co/blog/Emma-N/enjoy-the-power-of-phi-3-with-onnx-runtime
[29] https://onnxruntime.ai/blogs/accelerating-phi-2
[30] https://techcommunity.microsoft.com/blog/azuredevcommunityblog/getting-started-with-microsoft-phi-3-mini---try-running-the-phi-3-mini-on-iphone/4131885
[31] https://huggingface.co/w11wo/ios-onnxruntime
[32] https://dev.to/nareshnishad/day-49-serving-llms-with-onnx-runtime-3828
[33] https://github.com/onnx/models
[34] https://paperswithcode.com/paper/tinyllama-an-open-source-small-language-model
[35] https://ollama.com/library/smollm
[36] https://www.datacamp.com/blog/top-small-language-models
[37] https://arxiv.org/html/2411.05046v1
[38] https://techxplore.com/news/2024-11-ai-personal-devices-efficient-small.html
[39] https://onnxruntime.ai
[40] https://www.willowtreeapps.com/craft/integrating-trained-models-into-your-ios-app-using-core-ml
[41] https://developer.apple.com/videos/play/wwdc2024/10159/
[42] https://github.com/likedan/Awesome-CoreML-Models
[43] https://statusneo.com/how-to-use-apples-ai-tools-like-core-ml-create-ml-and-more-in-your-ios-apps/
[44] https://pyimagesearch.com/2018/04/23/running-keras-models-on-ios-with-coreml/
[45] https://huggingface.co/coreml-projects
[46] https://huggingface.co/blog/swift-coreml-llm
[47] https://www.youtube.com/watch?v=aawk4l9W9YU
[48] https://developer.apple.com/videos/play/wwdc2020/10153/
[49] https://developer.apple.com/videos/play/wwdc2024/10161/
[50] https://www.reddit.com/r/LocalLLaMA/comments/16igu6g/apple_coreml/
[51] https://docs.ultralytics.com/integrations/coreml/
[52] https://www.youtube.com/watch?v=g3yj9_DHrME
[53] https://www.techrepublic.com/article/apple-mlx-framework-machine-learning/
[54] https://the-decoder.com/run-llms-on-your-m-series-with-apples-new-mlx-machine-learning-framework/
[55] https://developer.apple.com/cn/videos/play/wwdc2025/298/
[56] https://heidloff.net/article/apple-mlx-fine-tuning/
[57] https://www.youtube.com/watch?v=BCfCdTp-fdM
[58] https://developer.apple.com/machine-learning/whats-new/
[59] https://dev.to/arshtechpro/wwdc-2025-explore-llm-on-apple-silicon-with-mlx-1if7
[60] https://www.reddit.com/r/LocalLLaMA/comments/1l7yrni/everything_you_wanted_to_know_about_apples_mlx/
[61] https://github.com/ml-explore/mlx-lm
[62] https://developer.apple.com/machine-learning/
[63] https://github.com/RahulBhalley/mlx-models
[64] https://gist.github.com/awni/fe4f96c21ead68e60191190cbc1c129b
[65] https://firebase.google.com/docs/ml/ios/use-custom-models
[66] https://www.slideshare.net/slideshow/running-tflite-on-your-mobile-devices-2020/237452660
[67] https://www.tensorflow.org
[68] https://hackernoon.com/how-to-deploy-large-language-models-on-android-with-tensorflow-lite
[69] https://medium.datadriveninvestor.com/how-to-deploy-a-tensorflow-lite-model-to-ios-4b230bb91ac0?gi=a7fb60c556cf
[70] https://android.googlesource.com/platform/external/tensorflow/+/ec63214f098a2bfc87b628219ad0718750d4e930/tensorflow/lite/g3doc/guide/get_started.md
[71] https://wiki.seeedstudio.com/reTerminal_ML_TFLite/
[72] https://www.tensorflow.org/lite?hl=fr
[73] https://learnopencv.com/tensorflow-lite-model-optimization-for-on-device-machine-learning/
[74] https://developers.google.com/learn/pathways/llm-on-android
[75] https://blog.tensorflow.org/2020/09/whats-new-in-tensorflow-lite-for-nlp.html
[76] https://github.com/margaretmz/awesome-tensorflow-lite
[77] https://developers.googleblog.com/large-language-models-on-device-with-mediapipe-and-tensorflow-lite/
[78] https://www.youtube.com/watch?v=WDww8ce12Mc
[79] https://iot-robotics.github.io/ONNXRuntime/docs/tutorials/mobile/deploy-ios.html
[80] https://onnxruntime.ai/docs/tutorials/mobile/deploy-ios.html
[81] https://www.linkedin.com/pulse/small-llms-mobile-devices-muhammad-imran-shad-hj8af
[82] https://skottmckay.github.io/onnxruntime/docs/how-to/mobile/
[83] https://www.packtpub.com/en-MY/product/net-maui-cookbook-9781835461129/chapter/chapter-6-real-life-scenarios-ai-signalr-and-more-6/section/detecting-with-a-local-onnx-model-deployed-on-the-device-ch06lvl1sec53
[84] https://onnxruntime.ai/docs/tutorials/mobile/
[85] https://onnxruntime.ai/docs/tutorials/on-device-training/ios-app.html
[86] https://huggingface.co/csukuangfj/ios-onnxruntime
[87] https://www.reddit.com/r/LocalLLaMA/comments/14q24n7/onnx_to_run_llm/
[88] https://huggingface.co/blog/jjokah/small-language-model
[89] https://www.youtube.com/watch?v=obHDI9-VBj8
[90] https://github.com/eugeneyan/open-llms
[91] https://www.arxiv.org/pdf/2502.20421.pdf
[92] https://www.business-standard.com/technology/tech-news/apple-s-new-ai-models-could-power-on-device-features-on-ios-18-for-iphones-124042500463_1.html
[93] https://www.tnnsupport.com/uncategorized/apple-releases-eight-small-ai-language-models-aimed-at-on-device-use/
[94] https://www.reddit.com/r/ChatGPT/comments/12f8ddo/how_do_i_download_a_language_model_to_run_locally/
[95] https://openreview.net/forum?id=hlin7nZLD3
[96] https://www.computing.co.uk/news/4202434/apple-releases-openelm-ai-small-language-models-device
[97] https://huggingface.co/codebyam/SmallLM
[98] https://www.reddit.com/r/LocalLLaMA/comments/17u848q/are_there_any_super_tiny_llm_models_which_we_can/
[99] https://www.theinformation.com/briefings/apple-releases-small-open-source-ai-models-for-on-device-applications
[100] https://www.e2enetworks.com/blog/comprehensive-list-of-small-llms-the-mini-giants-of-the-llm-world
[101] https://github.com/stevelaskaridis/awesome-mobile-llm
[102] https://huggingface.co/apple/OpenELM-450M
[103] https://huggingface.co/apple/OpenELM-1_1B
[104] https://huggingface.co/apple/OpenELM-3B
[105] https://huggingface.co/apple/OpenELM-270M-Instruct
[106] https://huggingface.co/apple/OpenELM-450M-Instruct
[107] https://huggingface.co/apple/OpenELM-1_1B-Instruct
[108] https://huggingface.co/apple/OpenELM-3B-Instruct
[109] https://huggingface.co/apple/OpenELM-270M/tree/main
[110] https://huggingface.co/collections/apple/openelm-pretrained-models-6619ac6ca12a10bd0d0df89e
[111] https://huggingface.co/collections/apple/openelm-instruct-models-6619ad295d7ae9f868b759ca