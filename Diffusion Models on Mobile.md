# Diffusion-Based Image Generation on Mobile: Models, Projects, and Inference Engines

## Top Diffusion-Based Models (2025–2026)

The landscape of open-source diffusion models has matured significantly. The leading models, ranked by quality and community adoption:

| Model | Developer | Parameters | Architecture | Key Strength |
|---|---|---|---|---|
| **FLUX.1 [dev/schnell]** | Black Forest Labs | ~12B | Hybrid Diffusion Transformer (DiT) | Best overall image quality and prompt adherence among open models [^1][^2] |
| **FLUX.2 [dev/klein]** | Black Forest Labs | Varies | DiT (next-gen) | Latest iteration with FLUX.2-klein for smaller footprint [^3] |
| **Stable Diffusion 3.5 Large/Medium** | Stability AI | ~8B / ~2.5B | Latent Diffusion (MMDiT) | Improved text rendering and multi-subject composition [^4] |
| **SDXL / SDXL-Turbo** | Stability AI | ~6.6B | Latent Diffusion (UNet) | Widely adopted, huge ecosystem of LoRAs and fine-tunes [^5] |
| **Stable Diffusion 1.5/2.1** | Stability AI / RunwayML | ~860M–1.2B | Latent Diffusion (UNet) | Lightweight, still the most practical for mobile on-device [^6] |
| **MobileDiffusion** | Google | ~520M | Optimized UNet (UViT) + DiffusionGAN | Sub-second generation on phones, designed for mobile [^7][^8] |
| **SnapFusion** | Snap Research | Optimized SD 1.5 | Efficient UNet | First to achieve <2s on-device generation [^9] |
| **SnapGen** | Snap Research | Compact | Efficient T2I | First 1024×1024 generation on mobile in 1.2–2.3 seconds [^10] |

FLUX.1 is the current state-of-the-art for quality among open-weight models, but its 12B parameters make it extremely challenging for mobile deployment. For practical on-device use, SD 1.5, SDXL (quantized), and MobileDiffusion remain the most viable options.[^11][^7][^2][^1]

***

## Top Open-Source Projects for Mobile Diffusion

### 1. stable-diffusion.cpp (⭐ 4.4k)

The most important project in the mobile diffusion space. Think of it as **llama.cpp but for diffusion models**.

- **Repo**: [github.com/leejet/stable-diffusion.cpp](https://github.com/leejet/stable-diffusion.cpp)[^3]
- **Inference Engine**: Pure C/C++ built on **ggml** (same backend as llama.cpp)
- **Supported Models**: SD1.x, SD2.x, SD3/SD3.5, SDXL, SDXL-Turbo, FLUX.1 dev/schnell, FLUX.2 dev/klein, Chroma, Qwen Image, Z-Image, Wan2.1/2.2 (video), plus image editing models like FLUX.1-Kontext-dev[^3]
- **Quantization**: 2-bit through 8-bit integer quantization (q2_K, q3_K, q4_0, q4_1, q5_0, q5_1, q8_0)[^3]
- **GPU Backends**: CUDA, Metal, Vulkan, OpenCL (Adreno), SYCL[^3]
- **Mobile Support**: Android via Termux or via the Local Diffusion Flutter app; iOS indirectly via Metal backend[^3]
- **Key Features**: Flash Attention, TAESD fast decoding, VAE tiling, ControlNet, LoRA, PhotoMaker, ESRGAN upscaling[^3]
- **Memory**: ~2.3GB for 512×512 with FP16, ~1.8GB with Flash Attention enabled[^3]
- **Bindings**: Python, Rust, Go, Flutter/Dart, C#[^12][^3]

This is the foundation that most Android diffusion apps are built on.

### 2. Local Diffusion (Android)

A **Flutter app** that wraps stable-diffusion.cpp for Android:

- **Repo**: [github.com/rmatif/Local-Diffusion](https://github.com/rmatif/Local-Diffusion)[^13]
- **Inference Engine**: stable-diffusion.cpp (ggml backend)
- **Supported Models**: SD1.x, SD2.x, SDXL, SD3/SD3.5, Flux/Flux-schnell, SD-Turbo, SDXL-Turbo[^13]
- **Model Sources**: Direct loading from HuggingFace and Civitai (.safetensors, .ckpt)[^13]
- **On-the-Fly Quantization**: q2_k through q8_0 during model loading[^13]
- **GPU Acceleration (Experimental)**: Vulkan (~2x slower than CPU currently), OpenCL (Adreno 7xx GPUs, optimized for Q4_0)[^13]
- **Features**: ControlNet, PhotoMaker, Img2Img, Inpainting/Outpainting, LoRA, negative prompts, token weighting[^13]
- **Roadmap**: iOS support is planned[^13]

Memory benchmarks from the project:[^13]

| Model | Resolution | Q4_0 (MB) | Q8_0 (MB) | FP16 (MB) |
|---|---|---|---|---|
| SD 1.5 | 512×512 | 1,900 | 2,087 | 2,436 |
| SDXL | 1024×1024 | 2,810 | 4,249 | 6,946 |
| SD3.5 Medium | 1024×1024 | 3,962 | 5,080 | 7,067 |
| FLUX.1 | 1024×1024 | 7,534 | 13,177 | — |

### 3. Draw Things (iOS/macOS)

The leading on-device diffusion app in the Apple ecosystem:

- **App**: [Draw Things on App Store](https://apps.apple.com/us/app/draw-things-offline-ai-art/id6444050820)[^14]
- **Inference Engine**: Custom Swift implementation using **s4nnc** (Swift for Neural Network Computation), with CoreML and Metal FlashAttention backends[^15][^16]
- **Supported Models**: SD 1.x, SD 2.x, SDXL, SD3 Medium, and community models[^17][^16]
- **Model Conversion**: PyTorch → Swift reimplementation using s4nnc, with PythonKit for layer-by-layer validation[^16]
- **Hardware Utilization**: CoreML runs on CPU + GPU + Apple Neural Engine simultaneously; Metal FlashAttention outperforms CoreML GPU on M1 Pro/M2 Pro and above by 20–40%[^15]
- **Features**: ControlNet, LoRA, on-device LoRA training, inpainting, outpainting, pose editing, PhotoMaker, textual inversion[^14]
- **Performance**: SD2.1 base at 512×512 runs in ~7s on iPad Pro M2 with CoreML[^18]
- **Source Code**: Open source at [github.com/liuliu/swift-diffusion](https://github.com/liuliu/swift-diffusion)[^16]

### 4. Apple's Core ML Stable Diffusion (Official)

Apple's official implementation for running SD on Apple Silicon:

- **Repo**: [github.com/apple/ml-stable-diffusion](https://github.com/apple/ml-stable-diffusion)[^18]
- **Inference Engine**: **Core ML** framework (leverages CPU, GPU, and Neural Engine)[^19]
- **Swift Package**: `StableDiffusion` — drop-in Xcode dependency[^18]
- **Python Tools**: `python_coreml_stable_diffusion` for PyTorch → Core ML conversion[^18]
- **Supported Models**: SD 1.x, SD 2.x (converted to Core ML format)[^18]
- **Attention Implementations**: ORIGINAL (GPU-optimized) and SPLIT_EINSUM/SPLIT_EINSUM_V2 (Neural Engine optimized)[^18]
- **Quantization**: Supports quantized models via coremltools 7+ (requires iOS 17+)[^20]

Performance benchmarks:[^18]

| Device | Latency (SD2.1-base, 512×512) | Diffusion Speed |
|---|---|---|
| iPhone 12 Mini | 18.5s | 1.44 iter/s |
| iPhone 13 | 10.8s | 2.53 iter/s |
| iPhone 14 Pro Max | 7.9s | 2.69 iter/s |
| iPad Pro M2 | 7.0s | 3.07 iter/s |

### 5. HuggingFace Swift Core ML Diffusers

A native Swift UI demo app wrapping Apple's Core ML SD:

- **Repo**: [github.com/huggingface/swift-coreml-diffusers](https://github.com/huggingface/swift-coreml-diffusers)[^20]
- **Inference Engine**: Core ML with DPM-Solver++ scheduler (ported to Swift)[^21][^20]
- **Models**: SD v2 base (auto-downloaded from HuggingFace Hub), quantized model support[^20]
- **Performance**: ~8s on MacBook Pro M1 Max, 23–30s on iPhone 13 Pro[^20]
- **Purpose**: Reference app / starting point for building your own iOS diffusion app[^21]

### 6. Qualcomm AI Hub + Layla Network (Android NPU)

For Qualcomm Snapdragon devices with NPU acceleration:

- **Qualcomm AI Hub Apps**: [github.com/quic/ai-hub-apps](https://github.com/quic/ai-hub-apps)[^22]
- **Inference Engine**: Qualcomm AI Engine Direct SDK (QAIRT), TensorFlow Lite, ONNX, Genie SDK[^22]
- **Supported Chips**: Snapdragon 8 Gen 2, Gen 3, 8 Elite, X Elite, X2 Elite[^22]
- **NPU Models**: INT8 quantized SD 1.5 and fast SD variants running on Hexagon Tensor Processor[^23][^24]
- **Performance**: ~10 seconds per image on NPU with minimal RAM usage[^24]
- **Layla App**: A third-party Android app that leverages Qualcomm NPU for SD inference, supporting multiple NPU-optimized models[^24]

***

## Inference Engine Comparison for Mobile Diffusion

| Inference Engine | Platform | GPU/Accelerator Support | Used By | Best For |
|---|---|---|---|---|
| **ggml** (via stable-diffusion.cpp) | Android, Linux, macOS, Windows | CPU, CUDA, Metal, Vulkan, OpenCL (Adreno) | Local Diffusion, sd.cpp-webui, Jellybox | Android (primary), cross-platform CLI [^3] |
| **Core ML** | iOS, iPadOS, macOS | CPU + GPU + Apple Neural Engine | Draw Things, Apple ml-stable-diffusion, HF Swift Diffusers | iOS/macOS (best Apple HW utilization) [^18][^19] |
| **Metal FlashAttention** (s4nnc) | iOS, iPadOS, macOS | Apple GPU directly | Draw Things | Apple devices M1 Pro+ (fastest on high-end Apple silicon) [^15] |
| **QAIRT / QNN SDK** | Android (Snapdragon) | Hexagon NPU, Adreno GPU | Qualcomm AI Hub, Layla | Snapdragon devices with NPU [^22][^24] |
| **ONNX Runtime Mobile** | Android, iOS | CPU, NNAPI (Android), CoreML (iOS), XNNPACK | Custom apps | Cross-platform with ONNX model format [^25][^26] |
| **ExecuTorch** | Android, iOS, embedded | CPU, GPU, NPU (delegated) | Meta apps, PyTorch ecosystem | PyTorch-native deployment pipeline [^27][^28] |
| **LiteRT (TFLite)** | Android, iOS | CPU, GPU, Qualcomm QNN NPU | Google ecosystem | TensorFlow model deployment [^29] |

***

## Cross-Platform Strategy: Running Diffusion on Both Android AND iOS

Given your background with on-device AI and both Apple/Qualcomm development, here are the practical approaches:

### Option A: stable-diffusion.cpp as Unified Core (Recommended)

The most mature cross-platform approach:

- **Android**: Use stable-diffusion.cpp compiled with OpenCL (Adreno GPUs) or Vulkan backend. The Local Diffusion Flutter app demonstrates this working end-to-end.[^3][^13]
- **iOS**: Compile stable-diffusion.cpp with Metal backend. The ggml library already supports Metal.[^3]
- **Wrapper**: Build a Flutter or React Native wrapper (Local Diffusion already provides a Flutter/Dart binding).[^13]
- **Models**: Use quantized SD 1.5 (q4_0 or q8_0) for broadest device compatibility, or SDXL/FLUX for high-end devices.[^13]
- **Pros**: Single C++ codebase, broadest model support (SD through FLUX.2), active development.[^3]
- **Cons**: GPU acceleration on Android still experimental; Vulkan ~2x slower than CPU currently.[^13]

### Option B: Platform-Native Engines

Use the best engine per platform:

- **iOS**: Core ML via Apple's `ml-stable-diffusion` Swift package for Neural Engine acceleration, or Draw Things' s4nnc approach for Metal FlashAttention.[^16][^18]
- **Android**: Qualcomm QAIRT SDK for NPU acceleration on Snapdragon devices, or stable-diffusion.cpp for broader Android support.[^22][^3]
- **Pros**: Maximum performance on each platform.
- **Cons**: Two separate codebases to maintain.

### Option C: ONNX Runtime Mobile

- Convert models to ONNX format, then use ONNX Runtime Mobile on both platforms.[^25][^26]
- Android gets NNAPI and XNNPACK acceleration; iOS gets CoreML acceleration via ONNX Runtime's execution providers.[^26]
- **Pros**: Single model format, cross-platform API.
- **Cons**: Less community support for diffusion specifically, model conversion overhead.

***

## Recommended Model Choices by Device Tier

| Device Tier | Recommended Model | Quantization | Expected Latency | RAM Needed |
|---|---|---|---|---|
| Low-end (3–4GB RAM) | SD 1.5 | Q4_0 | 30–60s | ~1.9GB [^13] |
| Mid-range (6–8GB RAM) | SD 1.5 or SDXL | Q8_0 / Q4_0 | 10–30s | 2–4GB [^13] |
| High-end Android (12GB+) | SDXL or SD3.5 Medium | Q4_0 | 5–15s | 3–5GB [^13] |
| iPhone 14+ / iPad M-series | SD 2.1 via CoreML | FP16 | 7–10s | ~2.5GB [^18] |
| Snapdragon 8 Gen 2/3 (NPU) | SD 1.5 (INT8) | INT8 | ~10s | Minimal [^24] |
| Apple M-series Mac/iPad | SDXL via CoreML/Metal | FP16/Quantized | 3–8s | ~4GB [^20][^15] |

***

## Key Research Models for Mobile (Not Yet Fully Open Source)

Two important research models to watch:

- **MobileDiffusion** (Google): 520M parameter model achieving sub-second 512×512 generation on both Android and iOS. Uses DiffusionGAN for single-step sampling. Not publicly released as of early 2026.[^7][^8][^30]
- **SnapGen** (Snap Research): First to generate 1024×1024 images on mobile in 1.2–2.3 seconds. Presented at CVPR 2025.[^10]
- **Efficient DiT**: Research on deploying Diffusion Transformers (the architecture behind FLUX and SD3) on mobile via elastic scaling, allowing a single model to adapt to different device capabilities.[^31]

These represent the next wave of mobile-optimized architectures that could eventually replace the current UNet-based approaches being run via stable-diffusion.cpp.

***

## Summary of the Ecosystem

The practical stack for shipping a cross-platform mobile diffusion app today:

1. **Inference Engine**: stable-diffusion.cpp (ggml) for cross-platform, Core ML for iOS-specific optimization[^18][^3]
2. **Models**: Quantized SD 1.5 (universal), SDXL Q4_0 (mid-high end), FLUX quantized (high-end only)[^13]
3. **Cross-platform wrapper**: Flutter (proven by Local Diffusion)[^13]
4. **iOS alternative**: Draw Things' open-source Swift implementation with s4nnc for best Apple Silicon performance[^16]
5. **Android NPU path**: Qualcomm QAIRT SDK for Snapdragon-specific NPU acceleration[^24][^22]

---

## References

1. [State-of-the-Art Open Source AI Models in 2025](https://hiringnet.com/image-generation-state-of-the-art-open-source-ai-models-in-2025) - A model like FLUX.1 or Stable Diffusion 3.5 would process this text and generate a detailed image ma...

2. [black-forest-labs/FLUX.1-dev](https://huggingface.co/black-forest-labs/FLUX.1-dev) - FLUX.1 [dev] is a 12 billion parameter rectified flow transformer capable of generating images from ...

3. [leejet/stable-diffusion.cpp - GitHub](https://github.com/leejet/stable-diffusion.cpp) - stable-diffusion.cpp ... Note that this project is under active development. API and command-line op...

4. [Image Generation: State-of-the-Art Open Source AI Models in 2025](https://madailab.com/image-generation-state-of-the-art-open-source-ai-models-in-2025) - The most advanced image generation models in 2025 primarily use diffusion models, transformer archit...

5. [The Best Open-Source Image Generation Models in 2026 - BentoML](https://www.bentoml.com/blog/a-guide-to-open-source-image-generation-models) - In this blog post, we will provide a featured list of open-source models that stand out for their ab...

6. [Stable Diffusion - Wikipedia](https://en.wikipedia.org/wiki/Stable_Diffusion) - Stable Diffusion is a deep learning, text-to-image model released in 2022 based on diffusion techniq...

7. [MobileDiffusion: Rapid text-to-image generation on-device](https://research.google/blog/mobilediffusion-rapid-text-to-image-generation-on-device/) - MobileDiffusion is an efficient latent diffusion model specifically designed for mobile devices. We ...

8. [Google's MobileDiffusion generates AI images on mobile devices in ...](https://the-decoder.com/googles-mobilediffusion-generates-ai-images-on-mobile-devices-in-less-than-a-second/) - MobileDiffusion uses a UNet architecture with a text encoder, a diffusion UNet, and an image decoder...

9. [Text-to-Image Diffusion Model on Mobile Devices within Two Seconds](https://neurips.cc/virtual/2023/poster/70144) - We present a generic approach that, for the first time, unlocks running text-to-image diffusion mode...

10. [SnapGen: Taming High-Resolution Text-to-Image Models for Mobile ...](https://cvpr.thecvf.com/virtual/2025/poster/33208) - Our model, for the first time, demonstrates the generation of 1024x1024 px images on a mobile device...

11. [On-Device LLMs: State of the Union, 2026 - Vikas Chandra](https://v-chandra.github.io/on-device-llms/) - Three years ago, running a language model on a phone meant a toy demo. Today, billion-parameter mode...

12. [stable-diffusion.cpp download | SourceForge.net](https://sourceforge.net/projects/stable-diffusion-cpp.mirror/) - Features. Portable C/C++ inference engine for diffusion models; Wide model support (SD1.x, SD2.x, SD...

13. [rmatif/Local-Diffusion: Run SD1.x/2.x/3.x, SDXL, and FLUX ... - GitHub](https://github.com/rmatif/Local-Diffusion) - Truly Local Inference: Generate images entirely on your Android device. Broad Model Compatibility: S...

14. [Draw Things: Offline AI Art - App Store - Apple](https://apps.apple.com/us/app/draw-things-offline-ai-art/id6444050820) - Draw Things, the powerful offline AI creation tool for your iPhone or iPad. The number one Stable Di...

15. [Integrating Metal FlashAttention: Accelerating the Heart of Image ...](https://engineering.drawthings.ai/p/integrating-metal-flashattention-accelerating-the-heart-of-image-generation-in-the-apple-ecosystem-16a86142eb18) - Draw Things was the first practical app to run full-blown image generation models at the “edge” — di...

16. [enabling rapid local deployment of SD3 Medium with s4nnc](https://engineering.drawthings.ai/p/from-iphone-ipad-to-mac-enabling-rapid-local-deployment-of-sd3-medium-with-s4nnc-324bd5e81cd5) - Draw Things users on iPhone, iPad and Mac. Stable Diffusion 1.4 now takes iOS, and iPadOS systems. D...

17. [Draw Things App (iOS, macOS, locally run SD) February Update](https://www.reddit.com/r/StableDiffusion/comments/11myng5/draw_things_app_ios_macos_locally_run_sd_february/) - This is the app currently under active development for Stable Diffusion in Apple ecosystem. CoreML s...

18. [Stable Diffusion with Core ML on Apple Silicon](https://github.com/apple/ml-stable-diffusion) - StableDiffusion , a Swift package that developers can add to their Xcode projects as a dependency to...

19. [Stable Diffusion with Core ML on Apple Silicon](https://machinelearning.apple.com/research/stable-diffusion-coreml-apple-silicon) - Today, we are excited to release optimizations to Core ML for Stable Diffusion in macOS 13.1 and iOS...

20. [Swift app demonstrating Core ML Stable Diffusion](https://github.com/huggingface/swift-coreml-diffusers) - Swift Core ML Diffusers. This is a native app that shows how to integrate Apple's Core ML Stable Dif...

21. [Swift 🧨Diffusers - Fast Stable Diffusion for Mac](https://huggingface.co/blog/fast-mac-diffusers) - Transform your text into stunning images with ease using Diffusers for Mac, a native app powered by ...

22. [quic/ai-hub-apps - GitHub](https://github.com/quic/ai-hub-apps) - The Qualcomm AI Hub Apps are a collection of sample apps and tutorials to help deploy machine learni...

23. [World's First On-device Demonstration of Stable Diffusion On an ...](https://www.edge-ai-vision.com/2023/02/worlds-first-on-device-demonstration-of-stable-diffusion-on-an-android-phone/) - Qualcomm AI Research deploys a popular 1B+ parameter foundation model on an edge device through full...

24. [Unlocking the Power of NPU: Exceptional Image Generation ... - Layla](https://www.layla-network.ai/post/layla-supports-generating-images-locally-using-the-npu) - Layla currently provides four NPU models, all of which are popular stable diffusion models. Users ca...

25. [Inference - ONNX Runtime](https://onnxruntime.ai/inference) - ONNX Runtime Mobile runs models on mobile devices using the same API used for cloud-based inferencin...

26. [Deploy on mobile | onnxruntime](https://onnxruntime.ai/docs/tutorials/mobile/) - ONNX Runtime gives you a variety of options to add machine learning to your mobile application. This...

27. [Introducing ExecuTorch 1.0: Powering the next generation of edge AI](https://pytorch.org/blog/introducing-executorch-1-0/) - ExecuTorch enables seamless, production-ready deployment of PyTorch models directly to edge devices ...

28. [Accelerating on-device ML on Meta's family of apps with ExecuTorch](https://engineering.fb.com/2025/07/28/android/executorch-on-device-ml-meta-family-of-apps/) - Over the past year, we've rolled out ExecuTorch, an open-source solution for on-device inference on ...

29. [Unlocking Peak Performance on Qualcomm NPU with LiteRT](https://developers.googleblog.com/unlocking-peak-performance-on-qualcomm-npu-with-litert/) - Unlock NPU power for on-device GenAI with the new LiteRT Qualcomm AI Engine Direct Accelerator. Get ...

30. [MobileDiffusion: Instant Text-to-Image Generation on Mobile Devices](https://arxiv.org/abs/2311.16567) - MobileDiffusion achieves a remarkable \textbf{sub-second} inference speed for generating a 512\times...

31. [Unleashing Diffusion Transformers for Efficient High-Fidelity Image ...](https://arxiv.org/html/2601.08303v2) - Together, these contributions enable scalable, efficient, and high-quality diffusion models for depl...


Here's the report on running diffusion-based image generation models on Android and iOS. It covers the top diffusion models, the leading open-source projects for mobile deployment, the inference engines they use, supported model architectures, and cross-platform strategies.

Prepared by Deep Research
we already integrated coreml stable diffusoin for iOS what's the equivalent for android for that if any? otherwise help me find a cross platform soluiton also
Since you already have CoreML Stable Diffusion working on iOS, here's a focused breakdown of the Android equivalent and cross-platform options.

Direct Android Equivalent of CoreML SD
There is no single first-party equivalent to Apple's ml-stable-diffusion CoreML package on Android. Apple provided an official, polished Swift package with Neural Engine optimization — Google hasn't done the same at that level of polish. However, there are several strong options:

Option 1: MediaPipe Image Generator (Closest to "official")
Google's own on-device diffusion solution for Android:
​

SDK: MediaPipe Solutions (Java/Kotlin API)

Models: Supports any model matching the SD 1.5 architecture
​

Features: Text-to-image, ControlNet-style plugins (face structure, edge detection, depth), LoRA fine-tuning via Vertex AI
​

Performance: ~15 seconds on high-end devices
​

Status: Still marked as experimental — not production-grade yet
​

Limitation: Only SD 1.5-class models, no SDXL/FLUX/SD3 support
​

Option 2: stable-diffusion.cpp with OpenCL (Best Breadth)
The most capable Android solution, especially if you want model parity with your iOS CoreML setup:
​

Build for Android: Compile with OpenCL backend for Adreno GPU acceleration (Snapdragon devices) using Android NDK

Models: SD 1.x, SD 2.x, SDXL, SD3/SD3.5, FLUX.1, FLUX.2 — far broader than MediaPipe
​

Quantization: q2_K through q8_0, loads .safetensors and .ckpt directly
​

GPU: OpenCL optimized for Adreno 7xx (Q4_0), Vulkan available but ~2x slower than CPU currently
​

Memory: SD 1.5 Q4_0 at 512×512 uses ~1.9GB
​

Option 3: Qualcomm QAIRT SDK + NPU (Fastest on Snapdragon)
If you're targeting Snapdragon 8 Gen 2/3/Elite specifically:

Runtime: Qualcomm AI Engine Direct (QNN) delegate via LiteRT or native SDK
​

Models: SD 1.5 INT8 on Hexagon NPU — generates images in ~10 seconds with minimal RAM

Limitation: Only SD 1.5 / SD 2.1-class models fit on NPU currently. SDXL is too heavy
​

Note: NNAPI is deprecated as of Android 15 — use the QNN delegate directly instead

Cross-Platform Solutions
Since you already have CoreML on iOS, here are options to unify:

Approach	iOS Engine	Android Engine	Shared Code	Model Support	Maturity
stable-diffusion.cpp + Flutter	Metal backend	OpenCL/Vulkan backend	Flutter UI + Dart bindings to sd.cpp	SD1.x → FLUX.2	Production-ready (Local Diffusion proves it) 
​
stable-diffusion.cpp + native wrappers	Metal backend	OpenCL backend	C/C++ core, platform-native UI	SD1.x → FLUX.2	Solid, requires platform bridge code 
​
ONNX Runtime Mobile	CoreML EP	NNAPI/XNNPACK EP	Same ONNX model, same API	SD 1.5 (with conversion)	Moderate — less diffusion-specific tooling 
​
LiteRT (TFLite successor)	CoreML delegate	QNN/GPU delegate	Same .tflite model	SD 1.5 (with conversion)	Active development, 1.4x faster GPU 
​
Recommended Path
Given that you already have CoreML integrated on iOS:

For quickest Android parity: Use stable-diffusion.cpp compiled with the OpenCL backend for Android. It supports the same models you're likely running via CoreML (SD 1.5/2.x), plus everything up to FLUX.2. The Local Diffusion project already ships this as a working Android app you can reference.

For eventual cross-platform unification: Build a Flutter wrapper around stable-diffusion.cpp using the existing Dart/Flutter bindings. On iOS, sd.cpp uses the Metal backend (comparable performance to CoreML for many models), and on Android it uses OpenCL/Vulkan. This lets you share the UI layer and model management code across both platforms while each platform uses its optimal GPU backend.
​

If Snapdragon NPU matters: Layer in the Qualcomm QNN delegate for Snapdragon devices specifically. This gives you the fastest generation (~10s) on supported hardware, while falling back to stable-diffusion.cpp CPU/OpenCL on other Android devices.

The key tradeoff: CoreML on iOS leverages the Neural Engine beautifully, but sd.cpp's Metal backend is close in performance on M-series chips. On Android, OpenCL on Adreno is the closest equivalent to what CoreML's Neural Engine does on iOS.

Prepared by Deep Research


                                                                                                                                                                                                                                  
  OpenCL GPU Acceleration: Findings                                                                                                                                                                                               
                                                                                                                                                                                                                                  
  The Core Problem                                                                                                                                                                                                                
                                                                                                                                                                                                                                  
  There are two major blockers preventing OpenCL from working with Stable Diffusion on Adreno GPUs:                                                                                                                               
                                                                                                                                                                                                                                  
  1. Missing Operations (~21 ops not implemented in ggml-opencl)

  The Qualcomm-contributed OpenCL backend was optimized for LLM inference (matmul-heavy), NOT diffusion models. Stable Diffusion requires operations like GROUP_NORM, TIMESTEP_EMBEDDING, IM2COL, UPSCALE, CONCAT, etc. that don't
   exist in the OpenCL backend. When sd.cpp hits one of these, it crashes or hangs.

  This was confirmed in llama.cpp issue #13621 — someone tried sd.cpp with OpenCL and got: "op not supported node_185 (GROUP_NORM)".

  2. No Automatic CPU Fallback

  sd.cpp uses the older ggml_gallocr allocator instead of ggml_backend_sched. The newer scheduler would automatically fall back to CPU for unsupported GPU operations. Without it, any unsupported op = hard crash/hang.

  3. GPU Watchdog Timeout (Secondary)

  Adreno GPUs enforce a ~2-second kernel execution timeout (KGSL watchdog). Large matmuls can exceed this, causing the GPU driver to reset — which looks like a hang.

  What We Can Try (Ranked by Feasibility)

  Short-term (can try now):

  1. Re-enable OpenCL + offload flags — Set keep_clip_on_cpu=true, vae_on_cpu=true, offload_params_to_cpu=true in sd_ctx_params_t. This puts only UNet matmuls on GPU while keeping CLIP/VAE on CPU, reducing the chance of
  hitting unsupported ops.
  2. Test with tiny generation first — 256x256, 4 steps. If that works but 512x512/28 steps doesn't, it's a timeout issue. If it crashes immediately, it's the missing ops issue.
  3. Add diagnostic logging — Query CL_DEVICE_GLOBAL_MEM_SIZE, CL_DEVICE_MAX_MEM_ALLOC_SIZE on the S25 to understand memory constraints.

  Medium-term:

  4. Update ggml submodule — sd.cpp's bundled ggml may be behind llama.cpp's latest OpenCL improvements. Newer commits may have more operation coverage.
  5. Vulkan backend — Better operation coverage than OpenCL for diffusion, but currently crashes on Adreno (vkCmdBindPipeline driver bug). Could improve with newer Qualcomm drivers.

  Long-term:

  6. Upstream fix — sd.cpp needs to migrate to ggml_backend_sched for automatic CPU fallback on unsupported ops. This is the real fix.
  7. Qualcomm QNN SDK — Proprietary but purpose-built for on-device AI on Snapdragon. Different integration path entirely.

  My Recommendation

  The most practical path is option 1+2: re-enable OpenCL with offload flags and test with a small generation to see exactly what fails. Even if only the matmul portions run on GPU (which ARE optimized for Adreno), it could
  still cut significant time off the UNet sampling phase (which is 90% of the ~17 min).

  Want me to proceed with enabling OpenCL with the offload flags and building a test?