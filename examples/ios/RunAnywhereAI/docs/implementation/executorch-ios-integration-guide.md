# ExecuTorch iOS Integration Guide for Swift

## Overview

ExecuTorch is a runtime for executing PyTorch models on edge devices, including iOS. This guide shows how to integrate ExecuTorch into your iOS Swift application to run models like LLaMA dynamically.

## Integration Methods

### 1. Swift Package Manager (Recommended)

The easiest way to integrate ExecuTorch is via Swift Package Manager using prebuilt binaries.

**In Xcode:**
1. Go to `File > Add Package Dependencies`
2. Paste: `https://github.com/pytorch/executorch`
3. Change branch to `swiftpm-0.7.0` (or latest version)
4. Select frameworks:
   - `executorch` - Core runtime (required)
   - `executorch_llm` - LLM-specific runtime
   - `backend_coreml` - Core ML acceleration
   - `backend_mps` - Metal Performance Shaders
   - `backend_xnnpack` - CPU optimization
   - `kernels_optimized` - Optimized kernels

**In Package.swift:**
```swift
dependencies: [
    .package(url: "https://github.com/pytorch/executorch.git", branch: "swiftpm-0.7.0")
],
targets: [
    .target(
        name: "YourApp",
        dependencies: [
            .product(name: "executorch", package: "executorch"),
            .product(name: "backend_xnnpack", package: "executorch"),
            .product(name: "kernels_optimized", package: "executorch"),
        ]
    )
]
```

### 2. Building from Source

For customization, build frameworks locally:

```bash
# Clone repo
git clone -b viable/strict https://github.com/pytorch/executorch.git --depth 1 --recurse-submodules
cd executorch

# Set up Python environment
python3 -m venv .venv && source .venv/bin/activate
./install_requirements.sh

# Build frameworks
./scripts/build_apple_frameworks.sh

# Frameworks will be in cmake-out/
```

## Basic Model Execution

### 1. Import ExecuTorch

```swift
import ExecuTorch
```

### 2. Load and Run a Model

```swift
class ModelRunner {
    private var module: Module?

    func loadModel(path: String) throws {
        // Create module instance
        module = Module(filePath: path)

        // Load the model and prepare for execution
        try module?.load("forward")
    }

    func runInference(input: [Float], shape: [Int]) throws -> [Float] {
        guard let module = module else {
            throw ModelError.notLoaded
        }

        // Create input tensor
        let inputTensor = Tensor(input, shape: shape)

        // Execute forward pass
        let outputs = try module.forward(inputTensor)

        // Extract output tensor
        guard let outputTensor: Tensor<Float> = outputs.first?.toTensor() else {
            throw ModelError.invalidOutput
        }

        // Get output data
        return try outputTensor.scalars()
    }
}
```

### 3. Advanced Tensor Operations

```swift
// Create tensors from various sources
let tensor1 = Tensor([1.0, 2.0, 3.0, 4.0], shape: [2, 2])
let tensor2 = Tensor<Float>.rand(shape: [3, 3])
let tensor3 = Tensor<Int32>.zeros(shape: [4, 4])

// Access tensor properties
print("Shape: \(tensor1.shape)")
print("Count: \(tensor1.count)")
print("Data type: \(tensor1.dataType)")

// Modify tensor data
try tensor1.withUnsafeMutableBytes { buffer in
    buffer[0] = 100.0
}

// Resize tensor (if shape dynamism allows)
try tensor1.resize(to: [4, 1])
```

## LLM Integration (LLaMA Example)

Based on the ExecuTorch LLaMA demo app:

### 1. Create LLM Runner Wrapper

```swift
import Foundation

class LLMRunner {
    private let modelPath: String
    private let tokenizerPath: String
    private var runner: LLaMARunner?

    init(modelPath: String, tokenizerPath: String) {
        self.modelPath = modelPath
        self.tokenizerPath = tokenizerPath
    }

    func load() throws {
        runner = LLaMARunner(
            modelPath: modelPath,
            tokenizerPath: tokenizerPath
        )

        try runner?.load()
    }

    func generate(
        prompt: String,
        maxTokens: Int = 768,
        onToken: @escaping (String) -> Void
    ) throws {
        guard let runner = runner else {
            throw LLMError.notLoaded
        }

        try runner.generate(
            prompt,
            sequenceLength: maxTokens,
            withTokenCallback: { token in
                onToken(token)
            }
        )
    }

    func stop() {
        runner?.stop()
    }
}
```

### 2. SwiftUI Integration

```swift
struct ChatView: View {
    @State private var prompt = ""
    @State private var messages: [Message] = []
    @State private var isGenerating = false
    @StateObject private var llmRunner = LLMRunner(
        modelPath: "path/to/model.pte",
        tokenizerPath: "path/to/tokenizer.bin"
    )

    var body: some View {
        VStack {
            ScrollView {
                ForEach(messages) { message in
                    MessageBubble(message: message)
                }
            }

            HStack {
                TextField("Enter prompt...", text: $prompt)
                    .textFieldStyle(RoundedBorderTextFieldStyle())

                Button(action: generateResponse) {
                    Image(systemName: isGenerating ? "stop.circle" : "arrow.up.circle.fill")
                }
                .disabled(prompt.isEmpty || isGenerating)
            }
            .padding()
        }
        .onAppear {
            Task {
                try? await llmRunner.load()
            }
        }
    }

    private func generateResponse() {
        let userPrompt = prompt
        prompt = ""
        isGenerating = true

        messages.append(Message(text: userPrompt, isUser: true))
        var responseMessage = Message(text: "", isUser: false)
        messages.append(responseMessage)

        Task {
            do {
                try llmRunner.generate(prompt: userPrompt) { token in
                    DispatchQueue.main.async {
                        messages[messages.count - 1].text += token
                    }
                }
            } catch {
                messages[messages.count - 1].text = "Error: \(error)"
            }

            isGenerating = false
        }
    }
}
```

## Dynamic Model Loading

### 1. File Import

```swift
import UniformTypeIdentifiers

struct ModelPicker: View {
    @Binding var modelPath: String?
    @State private var isImporting = false

    var body: some View {
        Button("Select Model") {
            isImporting = true
        }
        .fileImporter(
            isPresented: $isImporting,
            allowedContentTypes: [UTType(filenameExtension: "pte")!],
            allowsMultipleSelection: false
        ) { result in
            switch result {
            case .success(let urls):
                modelPath = urls.first?.path
            case .failure(let error):
                print("Error selecting file: \(error)")
            }
        }
    }
}
```

### 2. Model Management

```swift
class ModelManager: ObservableObject {
    @Published var availableModels: [ModelInfo] = []
    private let documentsPath = FileManager.default.urls(
        for: .documentDirectory,
        in: .userDomainMask
    ).first!

    func downloadModel(from url: URL) async throws {
        let (data, _) = try await URLSession.shared.data(from: url)
        let fileName = url.lastPathComponent
        let fileURL = documentsPath.appendingPathComponent(fileName)
        try data.write(to: fileURL)

        await MainActor.run {
            availableModels.append(ModelInfo(
                name: fileName,
                path: fileURL.path
            ))
        }
    }

    func loadModel(_ info: ModelInfo) throws -> Module {
        let module = Module(filePath: info.path)
        try module.load("forward")
        return module
    }
}
```

## Memory Management & Performance

### 1. Configure Linker Flags

Create an `.xcconfig` file:

```
OTHER_LDFLAGS = $(inherited) \
    -force_load $(BUILT_PRODUCTS_DIR)/libexecutorch_$(ET_PLATFORM).a \
    -force_load $(BUILT_PRODUCTS_DIR)/libbackend_xnnpack_$(ET_PLATFORM).a \
    -force_load $(BUILT_PRODUCTS_DIR)/libkernels_optimized_$(ET_PLATFORM).a
```

### 2. Memory Monitoring

```swift
class ResourceMonitor: ObservableObject {
    @Published var usedMemory: Int = 0
    private var timer: Timer?

    func start() {
        timer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { _ in
            self.updateMemoryUsage()
        }
    }

    private func updateMemoryUsage() {
        var info = mach_task_basic_info()
        var count = mach_msg_type_number_t(MemoryLayout<mach_task_basic_info>.size) / 4

        let result = withUnsafeMutablePointer(to: &info) {
            $0.withMemoryRebound(to: integer_t.self, capacity: 1) {
                task_info(mach_task_self_,
                         task_flavor_t(MACH_TASK_BASIC_INFO),
                         $0,
                         &count)
            }
        }

        if result == KERN_SUCCESS {
            usedMemory = Int(info.resident_size / 1024 / 1024)
        }
    }
}
```

## Backend Selection

### 1. Core ML Backend

```swift
// Ensure model was exported with Core ML delegate
// The runtime will automatically use Core ML if available
```

### 2. Metal Performance Shaders

```swift
// Models exported with MPS backend will use GPU acceleration
// No additional configuration needed
```

### 3. XNNPACK (CPU Optimization)

```swift
// Default CPU backend with SIMD optimizations
// Automatically selected for CPU operations
```

## Error Handling

```swift
enum ModelError: Error {
    case notLoaded
    case invalidInput
    case invalidOutput
    case executionFailed(String)
}

extension ModelError: LocalizedError {
    var errorDescription: String? {
        switch self {
        case .notLoaded:
            return "Model not loaded"
        case .invalidInput:
            return "Invalid input format"
        case .invalidOutput:
            return "Invalid output format"
        case .executionFailed(let message):
            return "Execution failed: \(message)"
        }
    }
}
```

## Best Practices

1. **Model Loading**: Load models on background queues to avoid blocking UI
2. **Memory**: Use `increased-memory-limit` entitlement for large models
3. **Backends**: Choose appropriate backend based on model and device capabilities
4. **Error Handling**: Always handle errors gracefully with user feedback
5. **Resource Cleanup**: Properly release models when not needed

## Debugging

Enable debug logs by linking against debug frameworks:

```swift
#if DEBUG
class DebugLogSink: LogSink {
    func log(level: LogLevel, timestamp: TimeInterval, filename: String, line: UInt, message: String) {
        print("[\(level)] \(filename):\(line) - \(message)")
    }
}

// In your app initialization
Log.shared.add(sink: DebugLogSink())
#endif
```

## Example: Complete Image Classification App

```swift
import SwiftUI
import ExecuTorch

struct ImageClassifierView: View {
    @State private var selectedImage: UIImage?
    @State private var prediction = ""
    @State private var isProcessing = false
    private let model = try? Module(filePath: Bundle.main.path(forResource: "mobilenet", ofType: "pte")!)

    var body: some View {
        VStack {
            if let image = selectedImage {
                Image(uiImage: image)
                    .resizable()
                    .scaledToFit()
                    .frame(height: 300)
            }

            Text(prediction)
                .font(.headline)
                .padding()

            Button("Select Image") {
                // Show image picker
            }

            Button("Classify") {
                classifyImage()
            }
            .disabled(selectedImage == nil || isProcessing)
        }
        .onAppear {
            try? model?.load("forward")
        }
    }

    private func classifyImage() {
        guard let image = selectedImage,
              let model = model else { return }

        isProcessing = true

        Task {
            do {
                // Preprocess image to [1, 3, 224, 224]
                let input = preprocessImage(image)
                let inputTensor = Tensor(input, shape: [1, 3, 224, 224])

                // Run inference
                let outputs = try model.forward(inputTensor)

                // Process results
                if let logits: Tensor<Float> = outputs.first?.toTensor() {
                    let scores = try logits.scalars()
                    let topClass = scores.enumerated().max(by: { $0.1 < $1.1 })?.0 ?? 0

                    await MainActor.run {
                        prediction = "Class: \(topClass)"
                        isProcessing = false
                    }
                }
            } catch {
                await MainActor.run {
                    prediction = "Error: \(error)"
                    isProcessing = false
                }
            }
        }
    }

    private func preprocessImage(_ image: UIImage) -> [Float] {
        // Image preprocessing logic
        // Resize to 224x224, normalize, convert to CHW format
        return []
    }
}
```

This guide provides a comprehensive overview of integrating ExecuTorch into iOS Swift applications, from basic setup to advanced LLM integration, based on the actual source code and examples in the ExecuTorch framework.
