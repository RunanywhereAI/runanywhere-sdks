Since you already have CoreML Stable Diffusion working on iOS, here's a focused breakdown of the Android equivalent and cross-platform options.

## Direct Android Equivalent of CoreML SD

There is **no single first-party equivalent** to Apple's `ml-stable-diffusion` CoreML package on Android. Apple provided an official, polished Swift package with Neural Engine optimization — Google hasn't done the same at that level of polish. However, there are several strong options:

### Option 1: MediaPipe Image Generator (Closest to "official")

Google's own on-device diffusion solution for Android: [developers.googleblog](https://developers.googleblog.com/mediapipe-on-device-text-to-image-generation-solution-now-available-for-android-developers/)

- **SDK**: MediaPipe Solutions (Java/Kotlin API)
- **Models**: Supports any model matching the **SD 1.5 architecture** [infoq](https://www.infoq.com/news/2023/10/mediapipe-image-generator/)
- **Features**: Text-to-image, ControlNet-style plugins (face structure, edge detection, depth), LoRA fine-tuning via Vertex AI [developers.googleblog](https://developers.googleblog.com/mediapipe-on-device-text-to-image-generation-solution-now-available-for-android-developers/)
- **Performance**: ~15 seconds on high-end devices [developers.googleblog](https://developers.googleblog.com/mediapipe-on-device-text-to-image-generation-solution-now-available-for-android-developers/)
- **Status**: Still marked as **experimental** — not production-grade yet [youtube](https://www.youtube.com/watch?v=nLNBbu0DYbI)
- **Limitation**: Only SD 1.5-class models, no SDXL/FLUX/SD3 support [reddit](https://www.reddit.com/r/StableDiffusion/comments/1f1iu1m/mediapipe_on_android/)

### Option 2: stable-diffusion.cpp with OpenCL (Best Breadth)

The most capable Android solution, especially if you want model parity with your iOS CoreML setup: [github](https://github.com/leejet/stable-diffusion.cpp)

- **Build for Android**: Compile with OpenCL backend for **Adreno GPU acceleration** (Snapdragon devices) using Android NDK [ojambo](https://www.ojambo.com/review-generative-ai-stable-diffusion-v1-5-1b-model)
- **Models**: SD 1.x, SD 2.x, SDXL, SD3/SD3.5, FLUX.1, FLUX.2 — far broader than MediaPipe [github](https://github.com/leejet/stable-diffusion.cpp)
- **Quantization**: q2_K through q8_0, loads .safetensors and .ckpt directly [github](https://github.com/leejet/stable-diffusion.cpp)
- **GPU**: OpenCL optimized for Adreno 7xx (Q4_0), Vulkan available but ~2x slower than CPU currently [github](https://github.com/rmatif/Local-Diffusion)
- **Memory**: SD 1.5 Q4_0 at 512×512 uses ~1.9GB [github](https://github.com/rmatif/Local-Diffusion)

### Option 3: Qualcomm QAIRT SDK + NPU (Fastest on Snapdragon)

If you're targeting Snapdragon 8 Gen 2/3/Elite specifically: [reddit](https://www.reddit.com/r/StableDiffusion/comments/1jmdm2g/i_made_an_android_stable_diffusion_apk_run_on/)

- **Runtime**: Qualcomm AI Engine Direct (QNN) delegate via LiteRT or native SDK [ai.google](https://ai.google.dev/edge/litert/android/npu/qualcomm)
- **Models**: SD 1.5 INT8 on Hexagon NPU — generates images in **~10 seconds** with minimal RAM [layla-network](https://www.layla-network.ai/post/layla-supports-generating-images-locally-using-the-npu)
- **Limitation**: Only SD 1.5 / SD 2.1-class models fit on NPU currently. SDXL is too heavy [reddit](https://www.reddit.com/r/StableDiffusion/comments/1jmdm2g/i_made_an_android_stable_diffusion_apk_run_on/)
- **Note**: NNAPI is **deprecated as of Android 15** — use the QNN delegate directly instead [genio-community.mediatek](https://genio-community.mediatek.com/t/are-there-any-official-android-examples-executing-tflite-models-using-nnapi-for-genio/464)

## Cross-Platform Solutions

Since you already have CoreML on iOS, here are options to unify:

| Approach | iOS Engine | Android Engine | Shared Code | Model Support | Maturity |
|---|---|---|---|---|---|
| **stable-diffusion.cpp + Flutter** | Metal backend | OpenCL/Vulkan backend | Flutter UI + Dart bindings to sd.cpp | SD1.x → FLUX.2 | Production-ready (Local Diffusion proves it)  [github](https://github.com/rmatif/Local-Diffusion) |
| **stable-diffusion.cpp + native wrappers** | Metal backend | OpenCL backend | C/C++ core, platform-native UI | SD1.x → FLUX.2 | Solid, requires platform bridge code  [github](https://github.com/leejet/stable-diffusion.cpp) |
| **ONNX Runtime Mobile** | CoreML EP | NNAPI/XNNPACK EP | Same ONNX model, same API | SD 1.5 (with conversion) | Moderate — less diffusion-specific tooling  [onnxruntime](https://onnxruntime.ai/inference) |
| **LiteRT (TFLite successor)** | CoreML delegate | QNN/GPU delegate | Same .tflite model | SD 1.5 (with conversion) | Active development, 1.4x faster GPU  [developers.googleblog](https://developers.googleblog.com/litert-the-universal-framework-for-on-device-ai/) |

## Recommended Path

Given that you already have CoreML integrated on iOS:

**For quickest Android parity**: Use **stable-diffusion.cpp** compiled with the OpenCL backend for Android. It supports the same models you're likely running via CoreML (SD 1.5/2.x), plus everything up to FLUX.2. The Local Diffusion project already ships this as a working Android app you can reference. [github](https://github.com/rmatif/Local-Diffusion)

**For eventual cross-platform unification**: Build a **Flutter wrapper around stable-diffusion.cpp** using the existing Dart/Flutter bindings. On iOS, sd.cpp uses the Metal backend (comparable performance to CoreML for many models), and on Android it uses OpenCL/Vulkan. This lets you share the UI layer and model management code across both platforms while each platform uses its optimal GPU backend. [github](https://github.com/rmatif/Local-Diffusion)

**If Snapdragon NPU matters**: Layer in the **Qualcomm QNN delegate** for Snapdragon devices specifically. This gives you the fastest generation (~10s) on supported hardware, while falling back to stable-diffusion.cpp CPU/OpenCL on other Android devices. [ai.google](https://ai.google.dev/edge/litert/android/npu/qualcomm)

The key tradeoff: CoreML on iOS leverages the Neural Engine beautifully, but sd.cpp's Metal backend is close in performance on M-series chips. On Android, OpenCL on Adreno is the closest equivalent to what CoreML's Neural Engine does on iOS. [engineering.drawthings](https://engineering.drawthings.ai/p/integrating-metal-flashattention-accelerating-the-heart-of-image-generation-in-the-apple-ecosystem-16a86142eb18)


Diffusion-Based Image Generation on Mobile: Models, Projects, and Inference Engines
Top Diffusion-Based Models (2025–2026)
The landscape of open-source diffusion models has matured significantly. The leading models, ranked by quality and community adoption:

Model	Developer	Parameters	Architecture	Key Strength
FLUX.1 [dev/schnell]	Black Forest Labs	~12B	Hybrid Diffusion Transformer (DiT)	Best overall image quality and prompt adherence among open models 
FLUX.2 [dev/klein]	Black Forest Labs	Varies	DiT (next-gen)	Latest iteration with FLUX.2-klein for smaller footprint 
​
Stable Diffusion 3.5 Large/Medium	Stability AI	~8B / ~2.5B	Latent Diffusion (MMDiT)	Improved text rendering and multi-subject composition 
​
SDXL / SDXL-Turbo	Stability AI	~6.6B	Latent Diffusion (UNet)	Widely adopted, huge ecosystem of LoRAs and fine-tunes 
​
Stable Diffusion 1.5/2.1	Stability AI / RunwayML	~860M–1.2B	Latent Diffusion (UNet)	Lightweight, still the most practical for mobile on-device 
​
MobileDiffusion	Google	~520M	Optimized UNet (UViT) + DiffusionGAN	Sub-second generation on phones, designed for mobile 
SnapFusion	Snap Research	Optimized SD 1.5	Efficient UNet	First to achieve <2s on-device generation 
​
SnapGen	Snap Research	Compact	Efficient T2I	First 1024×1024 generation on mobile in 1.2–2.3 seconds 
​
FLUX.1 is the current state-of-the-art for quality among open-weight models, but its 12B parameters make it extremely challenging for mobile deployment. For practical on-device use, SD 1.5, SDXL (quantized), and MobileDiffusion remain the most viable options.

Top Open-Source Projects for Mobile Diffusion
1. stable-diffusion.cpp (⭐ 4.4k)
The most important project in the mobile diffusion space. Think of it as llama.cpp but for diffusion models.

Repo: 
github.com/leejet/stable-diffusion.cpp
​

Inference Engine: Pure C/C++ built on ggml (same backend as llama.cpp)

Supported Models: SD1.x, SD2.x, SD3/SD3.5, SDXL, SDXL-Turbo, FLUX.1 dev/schnell, FLUX.2 dev/klein, Chroma, Qwen Image, Z-Image, Wan2.1/2.2 (video), plus image editing models like FLUX.1-Kontext-dev
​

Quantization: 2-bit through 8-bit integer quantization (q2_K, q3_K, q4_0, q4_1, q5_0, q5_1, q8_0)
​

GPU Backends: CUDA, Metal, Vulkan, OpenCL (Adreno), SYCL
​

Mobile Support: Android via Termux or via the Local Diffusion Flutter app; iOS indirectly via Metal backend
​

Key Features: Flash Attention, TAESD fast decoding, VAE tiling, ControlNet, LoRA, PhotoMaker, ESRGAN upscaling
​

Memory: ~2.3GB for 512×512 with FP16, ~1.8GB with Flash Attention enabled
​

Bindings: Python, Rust, Go, Flutter/Dart, C#

This is the foundation that most Android diffusion apps are built on.

2. Local Diffusion (Android)
A Flutter app that wraps stable-diffusion.cpp for Android:

Repo: 
github.com/rmatif/Local-Diffusion
​

Inference Engine: stable-diffusion.cpp (ggml backend)

Supported Models: SD1.x, SD2.x, SDXL, SD3/SD3.5, Flux/Flux-schnell, SD-Turbo, SDXL-Turbo
​

Model Sources: Direct loading from HuggingFace and Civitai (.safetensors, .ckpt)
​

On-the-Fly Quantization: q2_k through q8_0 during model loading
​

GPU Acceleration (Experimental): Vulkan (~2x slower than CPU currently), OpenCL (Adreno 7xx GPUs, optimized for Q4_0)
​

Features: ControlNet, PhotoMaker, Img2Img, Inpainting/Outpainting, LoRA, negative prompts, token weighting
​

Roadmap: iOS support is planned
​

Memory benchmarks from the project:
​

Model	Resolution	Q4_0 (MB)	Q8_0 (MB)	FP16 (MB)
SD 1.5	512×512	1,900	2,087	2,436
SDXL	1024×1024	2,810	4,249	6,946
SD3.5 Medium	1024×1024	3,962	5,080	7,067
FLUX.1	1024×1024	7,534	13,177	—
3. Draw Things (iOS/macOS)
The leading on-device diffusion app in the Apple ecosystem:

App: 
Draw Things on App Store
​

Inference Engine: Custom Swift implementation using s4nnc (Swift for Neural Network Computation), with CoreML and Metal FlashAttention backends

Supported Models: SD 1.x, SD 2.x, SDXL, SD3 Medium, and community models

Model Conversion: PyTorch → Swift reimplementation using s4nnc, with PythonKit for layer-by-layer validation
​

Hardware Utilization: CoreML runs on CPU + GPU + Apple Neural Engine simultaneously; Metal FlashAttention outperforms CoreML GPU on M1 Pro/M2 Pro and above by 20–40%
​

Features: ControlNet, LoRA, on-device LoRA training, inpainting, outpainting, pose editing, PhotoMaker, textual inversion
​

Performance: SD2.1 base at 512×512 runs in ~7s on iPad Pro M2 with CoreML
​

Source Code: Open source at github.com/liuliu/swift-diffusion
​

4. Apple's Core ML Stable Diffusion (Official)
Apple's official implementation for running SD on Apple Silicon:

Repo: 
github.com/apple/ml-stable-diffusion
​

Inference Engine: Core ML framework (leverages CPU, GPU, and Neural Engine)
​

Swift Package: StableDiffusion — drop-in Xcode dependency
​

Python Tools: python_coreml_stable_diffusion for PyTorch → Core ML conversion
​

Supported Models: SD 1.x, SD 2.x (converted to Core ML format)
​

Attention Implementations: ORIGINAL (GPU-optimized) and SPLIT_EINSUM/SPLIT_EINSUM_V2 (Neural Engine optimized)
​

Quantization: Supports quantized models via coremltools 7+ (requires iOS 17+)
​

Performance benchmarks:
​

Device	Latency (SD2.1-base, 512×512)	Diffusion Speed
iPhone 12 Mini	18.5s	1.44 iter/s
iPhone 13	10.8s	2.53 iter/s
iPhone 14 Pro Max	7.9s	2.69 iter/s
iPad Pro M2	7.0s	3.07 iter/s
5. HuggingFace Swift Core ML Diffusers
A native Swift UI demo app wrapping Apple's Core ML SD:

Repo: 
github.com/huggingface/swift-coreml-diffusers
​

Inference Engine: Core ML with DPM-Solver++ scheduler (ported to Swift)

Models: SD v2 base (auto-downloaded from HuggingFace Hub), quantized model support
​

Performance: ~8s on MacBook Pro M1 Max, 23–30s on iPhone 13 Pro
​

Purpose: Reference app / starting point for building your own iOS diffusion app
​

6. Qualcomm AI Hub + Layla Network (Android NPU)
For Qualcomm Snapdragon devices with NPU acceleration:

Qualcomm AI Hub Apps: 
github.com/quic/ai-hub-apps
​

Inference Engine: Qualcomm AI Engine Direct SDK (QAIRT), TensorFlow Lite, ONNX, Genie SDK
​

Supported Chips: Snapdragon 8 Gen 2, Gen 3, 8 Elite, X Elite, X2 Elite
​

NPU Models: INT8 quantized SD 1.5 and fast SD variants running on Hexagon Tensor Processor

Performance: ~10 seconds per image on NPU with minimal RAM usage
​

Layla App: A third-party Android app that leverages Qualcomm NPU for SD inference, supporting multiple NPU-optimized models
​

Inference Engine Comparison for Mobile Diffusion
Inference Engine	Platform	GPU/Accelerator Support	Used By	Best For
ggml (via stable-diffusion.cpp)	Android, Linux, macOS, Windows	CPU, CUDA, Metal, Vulkan, OpenCL (Adreno)	Local Diffusion, sd.cpp-webui, Jellybox	Android (primary), cross-platform CLI 
​
Core ML	iOS, iPadOS, macOS	CPU + GPU + Apple Neural Engine	Draw Things, Apple ml-stable-diffusion, HF Swift Diffusers	iOS/macOS (best Apple HW utilization) 
Metal FlashAttention (s4nnc)	iOS, iPadOS, macOS	Apple GPU directly	Draw Things	Apple devices M1 Pro+ (fastest on high-end Apple silicon) 
​
QAIRT / QNN SDK	Android (Snapdragon)	Hexagon NPU, Adreno GPU	Qualcomm AI Hub, Layla	Snapdragon devices with NPU 
ONNX Runtime Mobile	Android, iOS	CPU, NNAPI (Android), CoreML (iOS), XNNPACK	Custom apps	Cross-platform with ONNX model format 
ExecuTorch	Android, iOS, embedded	CPU, GPU, NPU (delegated)	Meta apps, PyTorch ecosystem	PyTorch-native deployment pipeline 
LiteRT (TFLite)	Android, iOS	CPU, GPU, Qualcomm QNN NPU	Google ecosystem	TensorFlow model deployment 
​
Cross-Platform Strategy: Running Diffusion on Both Android AND iOS
Given your background with on-device AI and both Apple/Qualcomm development, here are the practical approaches:

Option A: stable-diffusion.cpp as Unified Core (Recommended)
The most mature cross-platform approach:

Android: Use stable-diffusion.cpp compiled with OpenCL (Adreno GPUs) or Vulkan backend. The Local Diffusion Flutter app demonstrates this working end-to-end.

iOS: Compile stable-diffusion.cpp with Metal backend. The ggml library already supports Metal.
​

Wrapper: Build a Flutter or React Native wrapper (Local Diffusion already provides a Flutter/Dart binding).
​

Models: Use quantized SD 1.5 (q4_0 or q8_0) for broadest device compatibility, or SDXL/FLUX for high-end devices.
​

Pros: Single C++ codebase, broadest model support (SD through FLUX.2), active development.
​

Cons: GPU acceleration on Android still experimental; Vulkan ~2x slower than CPU currently.
​

Option B: Platform-Native Engines
Use the best engine per platform:

iOS: Core ML via Apple's ml-stable-diffusion Swift package for Neural Engine acceleration, or Draw Things' s4nnc approach for Metal FlashAttention.

Android: Qualcomm QAIRT SDK for NPU acceleration on Snapdragon devices, or stable-diffusion.cpp for broader Android support.

Pros: Maximum performance on each platform.

Cons: Two separate codebases to maintain.

Option C: ONNX Runtime Mobile
Convert models to ONNX format, then use ONNX Runtime Mobile on both platforms.

Android gets NNAPI and XNNPACK acceleration; iOS gets CoreML acceleration via ONNX Runtime's execution providers.
​

Pros: Single model format, cross-platform API.

Cons: Less community support for diffusion specifically, model conversion overhead.

Recommended Model Choices by Device Tier
Device Tier	Recommended Model	Quantization	Expected Latency	RAM Needed
Low-end (3–4GB RAM)	SD 1.5	Q4_0	30–60s	~1.9GB 
​
Mid-range (6–8GB RAM)	SD 1.5 or SDXL	Q8_0 / Q4_0	10–30s	2–4GB 
​
High-end Android (12GB+)	SDXL or SD3.5 Medium	Q4_0	5–15s	3–5GB 
​
iPhone 14+ / iPad M-series	SD 2.1 via CoreML	FP16	7–10s	~2.5GB 
​
Snapdragon 8 Gen 2/3 (NPU)	SD 1.5 (INT8)	INT8	~10s	Minimal 
​
Apple M-series Mac/iPad	SDXL via CoreML/Metal	FP16/Quantized	3–8s	~4GB 
Key Research Models for Mobile (Not Yet Fully Open Source)
Two important research models to watch:

MobileDiffusion (Google): 520M parameter model achieving sub-second 512×512 generation on both Android and iOS. Uses DiffusionGAN for single-step sampling. Not publicly released as of early 2026.

SnapGen (Snap Research): First to generate 1024×1024 images on mobile in 1.2–2.3 seconds. Presented at CVPR 2025.
​

Efficient DiT: Research on deploying Diffusion Transformers (the architecture behind FLUX and SD3) on mobile via elastic scaling, allowing a single model to adapt to different device capabilities.
​

These represent the next wave of mobile-optimized architectures that could eventually replace the current UNet-based approaches being run via stable-diffusion.cpp.

Summary of the Ecosystem
The practical stack for shipping a cross-platform mobile diffusion app today:

Inference Engine: stable-diffusion.cpp (ggml) for cross-platform, Core ML for iOS-specific optimization

Models: Quantized SD 1.5 (universal), SDXL Q4_0 (mid-high end), FLUX quantized (high-end only)
​

Cross-platform wrapper: Flutter (proven by Local Diffusion)
​

iOS alternative: Draw Things' open-source Swift implementation with s4nnc for best Apple Silicon performance
​

Android NPU path: Qualcomm QAIRT SDK for Snapdragon-specific NPU acceleration