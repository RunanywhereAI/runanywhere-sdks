# RunAnywhereAI iOS Sample App

A comprehensive iOS example app showcasing advanced on-device AI capabilities with multiple LLM frameworks, benchmarking tools, and performance optimization features.

📖 **For detailed features documentation, see [FEATURES.md](./FEATURES.md)**

## Features

### 🤖 Multi-Framework Support
Integrates 10+ LLM frameworks including:
- **llama.cpp** (GGUF models)
- **Core ML** (Apple's native ML framework)
- **MLX** (Apple Silicon optimized)
- **ONNX Runtime** (Cross-platform inference)
- **TensorFlow Lite** (Mobile-optimized ML)
- **ExecuTorch** (PyTorch mobile runtime)
- **MLC LLM** (Machine Learning Compilation)
- **Swift Transformers** (Native Swift implementation)
- **PicoLLM** (Lightweight inference engine)
- **Foundation Models** (System-level APIs)

### 💬 Advanced Chat Interface
- **Enhanced Chat View**: Full-featured chat UI with streaming responses
- **Chat Interface View**: Specialized chat components
- **Message Management**: Support for enhanced chat messages with metadata
- **Conversation Export**: Export chat histories
- **Conversation Store**: Persistent chat storage

### 📊 Performance & Benchmarking
- **Comprehensive Benchmarking Suite**: Multi-framework performance testing
- **Real-time Performance Monitoring**: Live metrics during inference
- **Memory Profiling**: Track memory usage and optimization
- **Performance Dashboard**: Visual charts and analytics
- **A/B Testing Framework**: Compare different configurations
- **Benchmark Service**: Automated performance testing

### 🔧 Model Management & Conversion
- **Model Repository**: Centralized model storage and management
- **Model Compatibility Checker**: Validate model-framework compatibility
- **Model Conversion Wizard**: Convert between different model formats
- **Model Format Detection**: Automatic format identification
- **Model Quantization**: Optimize models for mobile deployment
- **Model Import/Download**: Easy model acquisition and management
- **Bundled Models Service**: Pre-packaged model management

### 🚀 Framework Exploration
- **Framework Capability Explorer**: Interactive framework comparison
- **Model Compatibility Matrix**: Visual compatibility overview
- **Framework Configurations**: Optimized settings per framework
- **Dependency Container**: Modular service architecture

### ⚙️ Advanced Configuration
- **Settings View**: Comprehensive configuration options
- **Generation Options**: Fine-tune inference parameters
- **Memory Management**: Intelligent memory allocation
- **Service Lifecycle Management**: Proper resource handling
- **Logging System**: Comprehensive debug and performance logging

## Project Structure

```
RunAnywhereAI/
├── Models/
│   ├── ChatMessage.swift
│   ├── ChatMessageEnhanced.swift
│   ├── GenerationOptions.swift
│   └── ModelInfo.swift
├── Services/
│   ├── LLMService/
│   │   ├── BaseLLMService.swift
│   │   ├── CoreMLService.swift
│   │   ├── FoundationModelsService.swift
│   │   ├── FrameworkInfo.swift
│   │   ├── LLMCapabilities.swift
│   │   ├── LLMInference.swift
│   │   ├── LLMMetrics.swift
│   │   ├── LLMModelLoader.swift
│   │   ├── LLMProtocol.swift
│   │   ├── LlamaCppService.swift
│   │   └── MLXService.swift
│   ├── Benchmarking/
│   │   └── BenchmarkSuite.swift
│   ├── Configuration/
│   │   ├── ConfigurationFactory.swift
│   │   └── FrameworkConfigurations.swift
│   ├── Logging/
│   │   ├── LLMService+Logging.swift
│   │   └── Logger.swift
│   ├── ModelManagement/
│   │   ├── ModelCompatibilityMatrix.swift
│   │   ├── ModelConverter.swift
│   │   ├── ModelFormatDetector.swift
│   │   └── ModelRepository.swift
│   ├── Monitoring/
│   │   └── RealtimePerformanceMonitor.swift
│   ├── Profiling/
│   │   └── MemoryProfiler.swift
│   ├── Testing/
│   │   └── ABTestingFramework.swift
│   ├── Tokenization/
│   │   └── Tokenizer.swift
│   ├── BenchmarkService.swift
│   ├── BundledModelsService.swift
│   ├── ConversationExporter.swift
│   ├── ConversationStore.swift
│   ├── DependencyContainer.swift
│   ├── ExecuTorchService.swift
│   ├── FrameworkConfiguration.swift
│   ├── LLMError+Extended.swift
│   ├── LLMError.swift
│   ├── MLCService.swift
│   ├── MemoryManager.swift
│   ├── ModelCompatibilityChecker.swift
│   ├── ModelLoader.swift
│   ├── ModelManager.swift
│   ├── ONNXService.swift
│   ├── PerformanceMonitor.swift
│   ├── PicoLLMService.swift
│   ├── ServiceLifecycleObserverImpl.swift
│   ├── SwiftTransformersService.swift
│   ├── TFLiteService.swift
│   └── UnifiedLLMService.swift
├── ViewModels/
│   ├── ChatViewModel.swift
│   ├── ChatViewModelEnhanced.swift
│   ├── ComparisonViewModel.swift
│   ├── FrameworkCapabilityExplorerViewModel.swift
│   ├── ModelConversionWizardViewModel.swift
│   ├── ModelListViewModel.swift
│   └── ModelQuantizationViewModel.swift
├── Views/
│   ├── Chat/
│   │   └── ChatInterfaceView.swift
│   ├── Comparison/
│   │   └── ComparisonView.swift
│   ├── Dashboard/
│   │   ├── Charts/
│   │   │   └── DashboardCharts.swift
│   │   └── PerformanceDashboardView.swift
│   ├── FrameworkExplorer/
│   │   └── FrameworkCapabilityExplorerView.swift
│   ├── ModelConversion/
│   │   └── ModelConversionWizardView.swift
│   ├── Quantization/
│   │   └── ModelQuantizationView.swift
│   ├── BenchmarkView.swift
│   ├── ChatView.swift
│   ├── MemoryMonitorView.swift
│   ├── ModelDownloadView.swift
│   ├── ModelImportView.swift
│   ├── ModelListView.swift
│   ├── ModelLoadingView.swift
│   └── SettingsView.swift
├── Utilities/
│   └── Constants.swift
└── ContentView.swift
```

## App Navigation

The app features a tab-based interface with four main sections:

1. **Chat Tab**: Interactive chat interface with streaming responses
2. **Models Tab**: Model management, loading, and framework selection
3. **Benchmark Tab**: Performance testing and analytics tools
4. **Settings Tab**: Configuration options and advanced settings

## Getting Started

### Prerequisites
- **iOS 15.0+** (iOS 17.0+ recommended for full feature support)
- **Xcode 15.0+**
- **Swift 5.9+**
- **macOS 12.0+** for development
- **Apple Silicon Mac** recommended for MLX framework testing

### Quick Start

#### Option 1: Using Build Scripts (Recommended)
1. Clone the repository and navigate to the iOS example:
   ```bash
   cd examples/ios/RunAnywhereAI/
   ```

2. Build and run on simulator:
   ```bash
   ./scripts/build_and_run.sh simulator "iPhone 16 Pro"
   ```

3. Or build and run on connected device:
   ```bash
   ./scripts/build_and_run.sh device
   ```

#### Option 2: Using Xcode
1. Install dependencies and open workspace:
   ```bash
   pod install
   ./fix_pods_sandbox.sh  # Required for Xcode 16
   open RunAnywhereAI.xcworkspace
   ```

2. Build and run the app on simulator or device

#### Explore the App
- **Chat Tab**: Start a conversation with an LLM service
- **Models Tab**: Browse available frameworks and download models
- **Benchmark Tab**: Run performance tests and view analytics
- **Settings Tab**: Configure generation parameters

## Development Setup

### Dependencies Installation
```bash
# Install CocoaPods dependencies (required for TensorFlow Lite)
pod install

# After pod install, always open the .xcworkspace file
open RunAnywhereAI.xcworkspace
```

### Important: Xcode 16 Sandbox Issues
When building with Xcode 16, you may encounter sandbox errors during the "Copy Pods Resources" build phase:
```
error: Sandbox: rsync(xxxxx) deny(1) file-write-create
```

**Solution**: After running `pod install`, run the fix script:
```bash
./fix_pods_sandbox.sh
```

This script automatically replaces the problematic `rsync` commands with `cp` to work around Xcode 16's stricter sandbox restrictions.

**Alternative manual fix**:
1. Open `Pods/Target Support Files/Pods-RunAnywhereAI/Pods-RunAnywhereAI-resources.sh`
2. Replace the `rsync` commands (around line 114) with `cp`:
   ```bash
   # Replace rsync with cp for sandbox compatibility
   while IFS= read -r file; do
     if [[ -n "$file" ]] && [[ -e "$file" ]]; then
       cp -R "$file" "${TARGET_BUILD_DIR}/${UNLOCALIZED_RESOURCES_FOLDER_PATH}/" || true
     fi
   done < "$RESOURCES_TO_COPY"
   ```

**Note**: This script is auto-generated by CocoaPods and will be overwritten on each `pod install`, so you'll need to apply this fix again after updating pods.

### Swift Macro Support Setup

This project integrates **llm.swift** which uses Swift Macros for LLM model definitions and prompt handling. If you encounter macro fingerprint validation errors or macro-related build issues, follow these steps:

#### 1. Enable Macro Fingerprint Validation Skip
Run this command to disable macro fingerprint validation in Xcode:
```bash
defaults write com.apple.dt.Xcode IDESkipMacroFingerprintValidation -bool YES
```

#### 2. Configure Build Settings
In your Xcode project:
1. Select your target in the Project Navigator
2. Go to **Build Settings**
3. Search for **"Other Swift Flags"**
4. Add the following flag: `-enable-experimental-feature Macros`

#### Why This Is Needed
llm.swift uses Swift Macros for code generation, particularly for:
- LLM model definitions and configurations
- Prompt template processing and generation
- Type-safe model parameter handling

Without these settings, you may encounter build errors related to macro expansion or fingerprint validation.

### Running Lints
```bash
# From the iOS example directory
./swiftlint.sh
```

```swiftlint --fix --format```

### Building from Command Line

#### Using Build Scripts (Recommended)
```bash
# Build and run on simulator
./scripts/build_and_run.sh simulator "iPhone 16 Pro"

# Build and run on connected device
./scripts/build_and_run.sh device "Your Device Name"

# Clean build artifacts
./scripts/clean_build_and_run.sh
```

#### Manual Xcode Commands
```bash
# Build for iOS Simulator
xcodebuild -workspace RunAnywhereAI.xcworkspace -scheme RunAnywhereAI -destination 'platform=iOS Simulator,name=iPhone 16 Pro' build

# Build for device (requires valid provisioning profile)
xcodebuild -workspace RunAnywhereAI.xcworkspace -scheme RunAnywhereAI -destination 'generic/platform=iOS' build
```

### Testing
```bash
# Run unit tests
xcodebuild test -workspace RunAnywhereAI.xcworkspace -scheme RunAnywhereAI -destination 'platform=iOS Simulator,name=iPhone 16 Pro'
```

### Model URL Verification
The app includes a comprehensive model download system with URL verification:

```bash
# Verify all model download URLs
./scripts/verify_urls.sh
```

This script:
- ✅ Uses `ModelURLRegistry.swift` as the single source of truth
- 🔍 Verifies accessibility of all download URLs
- 📊 Provides detailed success/failure reporting
- ⚠️ Handles authentication-required URLs (Kaggle models)
- 🔄 Must be run from the `scripts/` directory

## Framework Integration

This app demonstrates integration patterns for multiple LLM frameworks:

### Currently Available Services
- **Core ML**: Apple's native ML framework (iOS 17.0+)
- **MLX**: Apple Silicon-optimized framework (iOS 17.0+)
- **ONNX Runtime**: Cross-platform inference engine
- **TensorFlow Lite**: Mobile-optimized TensorFlow
- **Foundation Models**: System-level model APIs (iOS 18.0+)

### Integration-Ready Services
Each service includes the interface and architecture for:
- **llama.cpp**: GGUF model support with C++ bridge
- **Core ML**: Apple's native ML framework integration
- **MLX**: Apple Silicon-optimized framework
- **ONNX Runtime**: Cross-platform model execution
- **TensorFlow Lite**: Mobile-optimized TensorFlow
- **ExecuTorch**: PyTorch mobile runtime
- **MLC LLM**: Machine learning compilation framework
- **Swift Transformers**: Pure Swift transformer implementation
- **PicoLLM**: Lightweight inference engine

### Adding Real Framework Support
To integrate actual frameworks:

1. **Add Dependencies**: Include the framework's Swift Package or library
2. **Update Service**: Replace mock implementation with real calls
3. **Configure Models**: Add model loading and format detection
4. **Test Integration**: Use the benchmark suite to validate performance

## Documentation

### Guides
- **[Bundled Models Guide](RunAnywhereAI/docs/BUNDLED_MODELS_GUIDE.md)**: How to add pre-trained models to your app bundle
- **[Model Download Guide](docs/MODEL_DOWNLOAD_GUIDE.md)**: On-demand model download system
- **[Model Integration Guide](docs/MODEL_INTEGRATION_GUIDE.md)**: Complete model integration documentation
- **[Foundation Models Setup](docs/FOUNDATION_MODELS_SETUP.md)**: iOS 18+ foundation models
- **[TensorFlow Lite Fix](docs/TENSORFLOW_LITE_FIX.md)**: Resolving TFLite issues

## Architecture Highlights

- **Modular Design**: Each framework is isolated in its own service
- **Dependency Injection**: Services are managed through DependencyContainer
- **Performance Monitoring**: Real-time metrics collection and analysis
- **Memory Management**: Intelligent resource allocation and cleanup
- **Error Handling**: Comprehensive error types and recovery strategies
- **Logging**: Structured logging for debugging and performance analysis

## License

This sample code is part of the RunAnywhereAI SDK project.
