# Model Integration & Distribution Guide for RunAnywhereAI

This guide provides comprehensive instructions for adding model files to the RunAnywhereAI iOS app and distributing them in production.

## Table of Contents
1. [Overview](#overview)
2. [Model Files by Framework](#model-files-by-framework)
3. [Adding Models to the App](#adding-models-to-the-app)
4. [Production Distribution Strategies](#production-distribution-strategies)
5. [Security & Best Practices](#security--best-practices)
6. [Model Management](#model-management)

## Overview

The RunAnywhereAI app supports 5 core LLM frameworks, each requiring different model formats:

| Framework | Model Format | Typical Size | Distribution Method |
|-----------|-------------|--------------|-------------------|
| Foundation Models | System-managed | N/A | Built into iOS 18+ |
| Core ML | .mlpackage/.mlmodel | 200MB-2GB | Bundle/Download |
| MLX | Directory with .safetensors | 1GB-8GB | Download |
| ONNX Runtime | .onnxRuntime/.ort | 500MB-4GB | Download |
| TensorFlow Lite | .tflite | 200MB-2GB | Bundle/Download |

## Model Files by Framework

### 1. Foundation Models (Apple)
**No external models needed** - Models are managed by iOS system
```swift
// Automatically available on iOS 18+ devices with A17 Pro or newer
// No download or distribution required
```

### 2. Core ML

#### Getting Models
```bash
# Example: Download GPT-2 Core ML model
curl -L "https://huggingface.co/coreml-community/gpt2-coreml/resolve/main/GPT2.mlpackage.zip" -o GPT2.mlpackage.zip
unzip GPT2.mlpackage.zip

# Example: Download DistilGPT2
curl -L "https://huggingface.co/coreml-community/distilgpt2-coreml/resolve/main/DistilGPT2.mlpackage.zip" -o DistilGPT2.mlpackage.zip

# Example: Download OpenELM
curl -L "https://huggingface.co/apple/OpenELM-270M-Instruct/resolve/main/OpenELM-270M-Instruct-coreml.zip" -o OpenELM.zip
```

#### Model Structure
```
GPT2.mlpackage/
├── Data/
│   └── com.apple.CoreML/
│       └── model.mlmodel
├── Manifest.json
└── coremldata.bin
```

#### Adding to Xcode
1. Drag the `.mlpackage` folder into Xcode project navigator
2. Select "Copy items if needed"
3. Add to target "RunAnywhereAI"
4. Ensure it appears in "Copy Bundle Resources" build phase

### 3. MLX (Apple Silicon Optimized)

#### Getting Models
```bash
# Download Mistral 7B 4-bit quantized
curl -L "https://huggingface.co/mlx-community/Mistral-7B-Instruct-v0.2-4bit/resolve/main/mistral-7b-instruct-v0.2-4bit.tar.gz" -o mistral-mlx.tar.gz
tar -xzf mistral-mlx.tar.gz

# Download Llama 3.2 3B
curl -L "https://huggingface.co/mlx-community/Llama-3.2-3B-Instruct-4bit/resolve/main/llama-3.2-3b-instruct-4bit.tar.gz" -o llama-mlx.tar.gz

# Download Gemma 2B
curl -L "https://huggingface.co/mlx-community/gemma-2b-it-4bit/resolve/main/gemma-2b-it-4bit.tar.gz" -o gemma-mlx.tar.gz
```

#### Required Files in MLX Model Directory
```
model-directory/
├── config.json          # Model architecture configuration
├── weights.safetensors  # Model weights in safetensors format
├── tokenizer.json       # Tokenizer configuration
├── tokenizer_config.json
└── special_tokens_map.json
```

#### Loading in App
```swift
let modelPath = documentsDirectory.appendingPathComponent("Models/MLX/mistral-7b")
try await mlxService.initialize(modelPath: modelPath.path)
```

### 4. ONNX Runtime

#### Getting Models
```bash
# Download Phi-3 mini (optimized for mobile)
curl -L "https://huggingface.co/microsoft/Phi-3-mini-4k-instruct-onnx/resolve/main/cpu-int4-rtn-block-32/phi3-mini-4k-instruct-cpu-int4-rtn-block-32.onnxRuntime" -o phi3.onnxRuntime

# Download Llama 2 7B INT8 quantized
curl -L "https://huggingface.co/microsoft/Llama-2-7b-chat-hf-onnx/resolve/main/Llama-2-7b-chat-hf-int8.onnxRuntime" -o llama2.onnxRuntime

# Download GPT-2
curl -L "https://huggingface.co/onnx-community/gpt2/resolve/main/onnx/model.onnxRuntime" -o gpt2.onnxRuntime
```

#### ONNX Model Types
- `.onnxRuntime` - Optimized runtime format
- `.ort` - Alternative extension
- `.onnx` - Standard ONNX (needs conversion)

### 5. TensorFlow Lite

#### Getting Models
```bash
# Download Gemma 2B INT8 quantized
curl -L "https://www.kaggle.com/models/google/gemma/tfLite/gemma-2b-it-gpu-int4/1/gemma-2b-it-gpu-int4.tflite" -o gemma-2b.tflite

# Download MobileBERT
curl -L "https://tfhub.dev/tensorflow/lite-model/mobilebert/1/default/1?lite-format=tflite" -o mobilebert.tflite
```

#### TFLite Optimization
```python
# Convert and optimize models for mobile
import tensorflow as tf

converter = tf.lite.TFLiteConverter.from_saved_model(saved_model_dir)
converter.optimizations = [tf.lite.Optimize.DEFAULT]
converter.representative_dataset = representative_dataset_gen
converter.target_spec.supported_ops = [tf.lite.OpsSet.TFLITE_BUILTINS_INT8]
tflite_model = converter.convert()
```

## Adding Models to the App

### Method 1: Bundle with App (Recommended for models < 200MB)

1. **Add to Xcode Project**
   ```
   RunAnywhereAI/
   └── Models/
       ├── CoreML/
       │   └── GPT2.mlpackage
       ├── TFLite/
       │   └── gemma-2b.tflite
       └── ONNX/
           └── phi3.onnxRuntime
   ```

2. **Access in Code**
   ```swift
   // Core ML
   let modelURL = Bundle.main.url(forResource: "GPT2", withExtension: "mlpackage")!
   
   // TensorFlow Lite
   let tfliteURL = Bundle.main.url(forResource: "gemma-2b", withExtension: "tflite")!
   
   // ONNX Runtime
   let onnxURL = Bundle.main.url(forResource: "phi3", withExtension: "onnxRuntime")!
   ```

### Method 2: On-Demand Download

1. **Implement Download Manager**
   ```swift
   class ModelDownloadManager {
       static let shared = ModelDownloadManager()
       
       func downloadModel(_ modelInfo: ModelInfo, 
                         progress: @escaping (Double) -> Void) async throws -> URL {
           guard let downloadURL = modelInfo.downloadURL else {
               throw ModelError.noDownloadURL
           }
           
           let session = URLSession(configuration: .default)
           let (localURL, response) = try await session.download(from: downloadURL)
           
           // Move to permanent location
           let documentsPath = FileManager.default.urls(for: .documentDirectory, 
                                                       in: .userDomainMask)[0]
           let modelDir = documentsPath.appendingPathComponent("Models/\(modelInfo.framework)")
           try FileManager.default.createDirectory(at: modelDir, 
                                                 withIntermediateDirectories: true)
           
           let finalURL = modelDir.appendingPathComponent(modelInfo.name)
           try FileManager.default.moveItem(at: localURL, to: finalURL)
           
           return finalURL
       }
   }
   ```

2. **Progress Tracking**
   ```swift
   let observation = session.downloadTask(with: url)
       .progress.observe(\.fractionCompleted) { progress, _ in
           DispatchQueue.main.async {
               self.downloadProgress = progress.fractionCompleted
           }
       }
   ```

### Method 3: CloudKit Integration

```swift
// Store models in CloudKit for Apple ecosystem
import CloudKit

func uploadModelToCloudKit(modelURL: URL, modelInfo: ModelInfo) async throws {
    let container = CKContainer.default()
    let database = container.publicCloudDatabase
    
    let record = CKRecord(recordType: "Model")
    record["name"] = modelInfo.name
    record["format"] = modelInfo.format.rawValue
    record["version"] = modelInfo.version
    
    let asset = CKAsset(fileURL: modelURL)
    record["modelFile"] = asset
    
    try await database.save(record)
}
```

## Production Distribution Strategies

### 1. App Store Distribution

**For Small Models (< 200MB)**
- Bundle directly in app
- Use App Thinning to optimize for device

**For Large Models**
- Use On-Demand Resources (ODR)
- Configure in Xcode:
  ```xml
  <key>NSBundleResourceRequest</key>
  <dict>
      <key>tags</key>
      <array>
          <string>coreml-models</string>
          <string>tflite-models</string>
      </array>
  </dict>
  ```

### 2. CDN Distribution

**Setup CDN (CloudFlare/AWS CloudFront)**
```swift
struct ModelCDN {
    static let baseURL = "https://cdn.runanywhereai.com/models/"
    
    static func modelURL(for model: ModelInfo) -> URL {
        let path = "\(model.framework)/\(model.version)/\(model.name)"
        return URL(string: baseURL + path)!
    }
}
```

**Download with Caching**
```swift
func downloadFromCDN(model: ModelInfo) async throws -> URL {
    let cdnURL = ModelCDN.modelURL(for: model)
    
    // Check cache first
    if let cachedURL = ModelCache.shared.getCachedModel(model) {
        return cachedURL
    }
    
    // Download with resume capability
    let download = URLSession.shared.downloadTask(with: cdnURL)
    download.resume()
    
    // Save to cache
    ModelCache.shared.cache(modelURL, for: model)
    
    return modelURL
}
```

### 3. Differential Updates

```swift
// Only download model deltas/patches
struct ModelDelta {
    let fromVersion: String
    let toVersion: String
    let deltaSize: Int64
    let deltaURL: URL
}

func applyModelDelta(_ delta: ModelDelta, to baseModel: URL) async throws -> URL {
    // Download delta
    let deltaData = try await downloadDelta(delta.deltaURL)
    
    // Apply patch using bsdiff or similar
    let updatedModel = try applyPatch(baseModel, delta: deltaData)
    
    return updatedModel
}
```

## Security & Best Practices

### 1. Model Verification

```swift
struct ModelSecurity {
    // Verify model integrity
    static func verifyModel(at url: URL, expectedHash: String) throws {
        let data = try Data(contentsOf: url)
        let hash = SHA256.hash(data: data)
        let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()
        
        guard hashString == expectedHash else {
            throw ModelError.invalidChecksum
        }
    }
    
    // Sign models with developer certificate
    static func signModel(at url: URL) throws {
        // Implementation depends on signing method
    }
}
```

### 2. Secure Storage

```swift
// Encrypt sensitive models
func encryptModel(at url: URL, key: SymmetricKey) throws {
    let data = try Data(contentsOf: url)
    let sealedBox = try AES.GCM.seal(data, using: key)
    try sealedBox.combined?.write(to: url)
}

// Store in secure container
func secureModelStorage() -> URL {
    let container = FileManager.default.url(for: .applicationSupportDirectory,
                                          in: .userDomainMask,
                                          appropriateFor: nil,
                                          create: true)!
    let secureDir = container.appendingPathComponent("SecureModels")
    
    // Set protection level
    try! FileManager.default.setAttributes(
        [.protectionKey: FileProtectionType.complete],
        ofItemAtPath: secureDir.path
    )
    
    return secureDir
}
```

### 3. Network Security

```swift
// Configure secure download session
let configuration = URLSessionConfiguration.default
configuration.tlsMinimumSupportedProtocolVersion = .TLSv13
configuration.urlCache = nil // Disable caching for sensitive models
configuration.httpShouldUsePipelining = true

let session = URLSession(configuration: configuration)
```

## Model Management

### 1. Storage Management

```swift
class ModelStorageManager {
    // Clean up old models
    func cleanupOldModels(keepLatest: Int = 2) async throws {
        let modelsDir = getModelsDirectory()
        let contents = try FileManager.default.contentsOfDirectory(
            at: modelsDir,
            includingPropertiesForKeys: [.creationDateKey, .fileSizeKey]
        )
        
        // Sort by creation date
        let sorted = contents.sorted { url1, url2 in
            let date1 = try! url1.resourceValues(forKeys: [.creationDateKey]).creationDate!
            let date2 = try! url2.resourceValues(forKeys: [.creationDateKey]).creationDate!
            return date1 > date2
        }
        
        // Remove old models
        for modelURL in sorted.dropFirst(keepLatest) {
            try FileManager.default.removeItem(at: modelURL)
        }
    }
    
    // Get storage usage
    func getStorageUsage() -> Int64 {
        let modelsDir = getModelsDirectory()
        let size = try? FileManager.default.allocatedSizeOfDirectory(at: modelsDir)
        return Int64(size ?? 0)
    }
}
```

### 2. Model Versioning

```swift
struct ModelVersion: Codable {
    let major: Int
    let minor: Int
    let patch: Int
    let build: String
    
    var string: String {
        "\(major).\(minor).\(patch)-\(build)"
    }
    
    func isNewer(than other: ModelVersion) -> Bool {
        if major != other.major { return major > other.major }
        if minor != other.minor { return minor > other.minor }
        if patch != other.patch { return patch > other.patch }
        return build > other.build
    }
}

// Track model versions
class ModelVersionTracker {
    func getCurrentVersion(for model: String) -> ModelVersion? {
        UserDefaults.standard.object(forKey: "model_version_\(model)") as? ModelVersion
    }
    
    func updateVersion(for model: String, version: ModelVersion) {
        UserDefaults.standard.set(version, forKey: "model_version_\(model)")
    }
}
```

### 3. Preloading Strategy

```swift
// Preload models based on usage patterns
class ModelPreloader {
    func preloadModelsForUser() async {
        // Get user's most used models
        let frequentModels = Analytics.shared.getMostUsedModels(limit: 3)
        
        // Preload in background
        for modelId in frequentModels {
            Task.detached(priority: .background) {
                try? await ModelLoader.shared.preloadModel(modelId)
            }
        }
    }
    
    // Predictive preloading
    func predictivePreload(currentModel: String) {
        let nextLikelyModel = ModelPredictor.shared.predictNext(after: currentModel)
        Task.detached(priority: .low) {
            try? await ModelLoader.shared.preloadModel(nextLikelyModel)
        }
    }
}
```

## Platform-Specific Considerations

### iOS/iPadOS
- Maximum app size: 4GB (uncompressed)
- On-Demand Resources: 20GB total, 2GB per resource
- Consider device storage constraints
- Use `AVAssetDownloadTask` for large models

### macOS
- Larger storage capacity allows bundling more models
- Can use App Store or direct distribution
- Consider Catalyst apps for unified distribution

### Device Capabilities
```swift
// Check available storage before download
func checkStorageAvailable(for modelSize: Int64) -> Bool {
    let fileURL = URL(fileURLWithPath: NSHomeDirectory())
    let values = try? fileURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
    let available = values?.volumeAvailableCapacityForImportantUsage ?? 0
    
    // Require 2x model size for safety
    return available > modelSize * 2
}
```

## Testing Distribution

### 1. TestFlight Testing
- Test model downloads with real network conditions
- Verify ODR works correctly
- Test storage cleanup

### 2. Network Simulation
```bash
# Simulate slow network
sudo dummynet pipe 1 config bw 1Mbit/s delay 100ms
sudo dummynet pipe 2 config bw 1Mbit/s delay 100ms

# Test downloads under poor conditions
```

### 3. Storage Testing
- Fill device storage to 90%
- Test model download/cleanup behavior
- Verify error handling

## Troubleshooting

### Common Issues

1. **"Model file not found"**
   - Verify file is in Copy Bundle Resources
   - Check file name case sensitivity
   - Ensure correct path in code

2. **"Download failed"**
   - Check network permissions in Info.plist
   - Verify SSL/TLS configuration
   - Check CDN/server availability

3. **"Insufficient storage"**
   - Implement proper storage checks
   - Add cleanup mechanisms
   - Use compression where possible

4. **"Model validation failed"**
   - Verify checksum/hash
   - Check for corruption during download
   - Ensure complete download

## Conclusion

This guide covers the complete process of integrating and distributing ML models for the RunAnywhereAI app. Choose the distribution method based on your model sizes, update frequency, and user base. Always prioritize security, user experience, and efficient storage management.

For framework-specific integration details, refer to the individual service implementation files in `RunAnywhereAI/Services/LLMServices/Core/`.