# Dependencies Action Plan for RunAnywhereAI iOS App

## 📊 Current Status
- ✅ **5 Ready Dependencies** (3 external + 2 built-in)
- ⏸️ **6 Deferred Dependencies** (Future consideration)

---

## ✅ WORKING DEPENDENCIES

### 1. ONNX Runtime (Microsoft Official) ✅
```
URL: https://github.com/microsoft/onnxruntime-swift-package-manager
Version: from "1.20.0"
Products: onnxruntime
Status: SUCCESSFULLY ADDED
```

### 2. Foundation Models (Apple Built-in) ✅
```
Framework: FoundationModels (iOS 18+)
Status: NO EXTERNAL DEPENDENCY NEEDED
Implementation: Add @available(iOS 18.0, *) guards
```

### 3. Core ML (Apple Built-in) ✅
```
Framework: CoreML
Status: NO EXTERNAL DEPENDENCY NEEDED
Implementation: Built into iOS
```

### 4. MLX Framework (Apple Silicon) ✅
```
URL: https://github.com/ml-explore/mlx-swift
Version: from "0.25.0"
Products: MLX, MLXNN, MLXRandom
Status: SUCCESSFULLY ADDED (version 0.25.6)
```

### 5. TensorFlow Lite (Google Mobile) ✅
```
CocoaPods: pod 'TensorFlowLiteSwift', '~> 2.17.0'
Products: TensorFlowLite
Status: SUCCESSFULLY ADDED via CocoaPods
```

---

## ⏸️ DEFERRED DEPENDENCIES (Future Implementation)

### Priority 1: MLC-LLM - REQUIRES MANUAL INTEGRATION
```
URL: https://github.com/mlc-ai/mlc-llm
Status: NO SPM SUPPORT - Requires manual framework integration
Reason: No Swift Package Manager support, needs build from source
Products: MLCSwift framework
UI Note: "Coming Soon - MLC-LLM (Universal Deployment)"
Timeline: When manual integration is needed
```

### Priority 2: ExecuTorch - BETA/NOT PRODUCTION READY 
```
URL: https://github.com/pytorch/executorch
Status: BETA/PREVIEW - Explicitly not recommended for production (July 2025)
Reason: PyTorch mobile framework still in preview, experimental APIs
Products: ExecutorchRuntime, ExecutorchBackendCoreML
UI Note: "Coming Soon - ExecuTorch (PyTorch Mobile)"
Timeline: Expected production-ready Q4 2025/Q1 2026
```

### Priority 3: llama.cpp via SpeziLLM - VERSION CONFLICTS
```
URL: https://github.com/StanfordSpezi/SpeziLLM  
Status: CONFLICT - Blocked by MLX Examples version issues
Reason: Popular GGUF format support, but dependency conflicts
Products: SpeziLLMLocal, SpeziLLMLocalLlama
UI Note: "Coming Soon - llama.cpp (GGUF Models)"
Timeline: After MLX Examples version resolved
```

### Priority 4: Swift Transformers - DEPENDENCY CONFLICTS
```
URL: https://github.com/huggingface/swift-transformers
Status: CONFLICT - Complex dependency tree conflicts
Reason: Hugging Face ecosystem integration, newer framework
Products: Transformers, Tokenizers, Hub
UI Note: "Coming Soon - Hugging Face Transformers"
Timeline: When dependency conflicts resolved
```

### Priority 5: PicoLLM - REQUIRES LICENSE
```
Requirement: Proprietary SDK + access key
Status: PROPRIETARY - Requires licensing agreement
Reason: Optimized for voice/edge, but not open source
UI Note: "Coming Soon - PicoLLM (Requires License)"
Timeline: If license obtained
```

### Priority 6: TensorFlow Lite Flex - ADVANCED FEATURE
```
Extension: Full TensorFlow Lite with Flex delegate
Status: FUTURE - Core TFLite implemented first
Reason: Advanced ops support, larger binary size
UI Note: "Coming Soon - TensorFlow Lite Advanced"
Timeline: After core TFLite stable
```

### ❌ REMOVED FROM PLAN

### MLX Vision & MLX Audio - REMOVED
```
Reason: Repositories don't exist
Action: Remove from init_plan.md completely
```

### MLX Examples - REMOVE OR FIX
```
Issue: Wrong version constraints (2.25.5+ doesn't exist)
Action: Either fix version or remove dependency
```

---

## 🎯 IMMEDIATE ACTION PLAN

### Step 1: Fix Working Frameworks (1-2 hours)
1. **MLX Framework**: Change version from "0.30.0" to "from: 0.25.0"
2. **TensorFlow Lite**: Create Podfile and add CocoaPods dependency

### Step 2: Clean Up Dependencies (1 hour)
1. Remove MLX Vision/Audio from all plans
2. Add "Coming Soon" notes to all deferred services
3. Update service documentation with implementation status

### Step 3: Add llama.cpp (2-3 hours) - OPTIONAL
1. Fix MLX Examples version conflict first
2. Add SpeziLLM dependency if conflicts resolved
3. Otherwise mark as "Coming Soon - llama.cpp (GGUF Models)"

---

## 📝 RECOMMENDED FRAMEWORK PRIORITY

### Core Implementation (Working Now) - 5 Frameworks
1. ✅ **Foundation Models** - Apple's native AI (iOS 18+)
2. ✅ **Core ML** - Apple's ML framework  
3. ✅ **ONNX Runtime** - Microsoft's inference engine
4. ✅ **MLX** - Apple Silicon optimization (working with 0.25.6)
5. ✅ **TensorFlow Lite** - Google's mobile framework (added via CocoaPods)

### Coming Soon Features (6 Deferred)
6. ⏸️ **MLC-LLM** - Universal LLM deployment (no SPM support)
7. ⏸️ **ExecuTorch** - PyTorch mobile (beta, not production-ready)
8. ⏸️ **llama.cpp/SpeziLLM** - GGUF format support (version conflicts)
9. ⏸️ **Swift Transformers** - Hugging Face integration (dependency conflicts)
10. ⏸️ **PicoLLM** - Proprietary optimization (requires license)
11. ⏸️ **TensorFlow Lite Advanced** - Flex delegate support (future enhancement)

---

## 🚀 FINAL DEPENDENCIES LIST FOR XCODE

Add these to your Xcode project:

### Swift Package Manager (5 Core Frameworks)
```swift
dependencies: [
    // ✅ Working Dependencies
    .package(url: "https://github.com/microsoft/onnxruntime-swift-package-manager", from: "1.20.0"),
    .package(url: "https://github.com/ml-explore/mlx-swift", from: "0.25.0"), // Working with 0.25.6
    
    // ⚠️ MLC-LLM not available via SPM - requires manual integration
    
    // ⏸️ Optional - Add after fixing conflicts
    // .package(url: "https://github.com/StanfordSpezi/SpeziLLM", from: "0.5.0"),
]
```

### CocoaPods (Create Podfile)
```ruby
platform :ios, '15.0'

target 'RunAnywhereAI' do
  use_frameworks!
  pod 'TensorFlowLiteSwift', '~> 2.17.0'
end
```

### Built-in Apple Frameworks (No Setup Required)
- Foundation Models (iOS 18+) - Add @available guards
- Core ML - Built into iOS

---

*Updated: July 27, 2025*  
*Status: 5 core dependencies working, 6 deferred for future (including MLC-LLM)*