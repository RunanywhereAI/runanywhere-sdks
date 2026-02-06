/// Diffusion Types for Flutter SDK
///
/// Matches Swift DiffusionTypes.swift and Kotlin DiffusionTypes.kt

import 'package:runanywhere/core/types/model_types.dart';

// ============================================================================
// Tokenizer Source
// ============================================================================

/// Tokenizer source for Stable Diffusion models
sealed class DiffusionTokenizerSource {
  const DiffusionTokenizerSource();

  /// Get the base URL for downloading tokenizer files
  String get baseURL;

  /// C++ enum value
  int get cValue;
}

/// Stable Diffusion 1.x tokenizer (CLIP ViT-L/14)
class SD15TokenizerSource extends DiffusionTokenizerSource {
  const SD15TokenizerSource();

  @override
  String get baseURL =>
      'https://huggingface.co/runwayml/stable-diffusion-v1-5/resolve/main/tokenizer';

  @override
  int get cValue => 0;
}

/// Stable Diffusion 2.x tokenizer (OpenCLIP ViT-H/14)
class SD2TokenizerSource extends DiffusionTokenizerSource {
  const SD2TokenizerSource();

  @override
  String get baseURL =>
      'https://huggingface.co/stabilityai/stable-diffusion-2-1/resolve/main/tokenizer';

  @override
  int get cValue => 1;
}

/// Stable Diffusion XL tokenizer (dual tokenizers)
class SDXLTokenizerSource extends DiffusionTokenizerSource {
  const SDXLTokenizerSource();

  @override
  String get baseURL =>
      'https://huggingface.co/stabilityai/stable-diffusion-xl-base-1.0/resolve/main/tokenizer';

  @override
  int get cValue => 2;
}

/// Custom tokenizer from a specified base URL
class CustomTokenizerSource extends DiffusionTokenizerSource {
  final String customBaseURL;

  const CustomTokenizerSource(this.customBaseURL);

  @override
  String get baseURL => customBaseURL;

  @override
  int get cValue => 99;
}

// ============================================================================
// Model Variant
// ============================================================================

/// Stable Diffusion model variants
enum DiffusionModelVariant {
  /// Stable Diffusion 1.5 (512x512 default)
  sd15('sd15', 512, 512, 28),

  /// Stable Diffusion 2.1 (768x768 default)
  sd21('sd21', 768, 768, 28),

  /// SDXL (1024x1024 default, requires 8GB+ RAM)
  sdxl('sdxl', 1024, 1024, 28),

  /// SDXL Turbo (fast, fewer steps)
  sdxlTurbo('sdxl_turbo', 1024, 1024, 4),

  /// SDXS (ultra-fast 1-step model, no CFG)
  sdxs('sdxs', 512, 512, 1),

  /// LCM (Latent Consistency Model, 4 steps)
  lcm('lcm', 512, 512, 4);

  const DiffusionModelVariant(
    this.rawValue,
    this.defaultWidth,
    this.defaultHeight,
    this.defaultSteps,
  );

  final String rawValue;
  final int defaultWidth;
  final int defaultHeight;
  final int defaultSteps;

  /// C++ enum value
  int get cValue {
    switch (this) {
      case DiffusionModelVariant.sd15:
        return 0;
      case DiffusionModelVariant.sd21:
        return 1;
      case DiffusionModelVariant.sdxl:
        return 2;
      case DiffusionModelVariant.sdxlTurbo:
        return 3;
      case DiffusionModelVariant.sdxs:
        return 4;
      case DiffusionModelVariant.lcm:
        return 5;
    }
  }

  /// Default tokenizer source for this model variant
  DiffusionTokenizerSource get defaultTokenizerSource {
    switch (this) {
      case DiffusionModelVariant.sd15:
        return const SD15TokenizerSource();
      case DiffusionModelVariant.sd21:
        return const SD2TokenizerSource();
      case DiffusionModelVariant.sdxl:
      case DiffusionModelVariant.sdxlTurbo:
        return const SDXLTokenizerSource();
      case DiffusionModelVariant.sdxs:
      case DiffusionModelVariant.lcm:
        return const SD15TokenizerSource();
    }
  }
}

// ============================================================================
// Scheduler
// ============================================================================

/// Diffusion scheduler/sampler types for the denoising process
enum DiffusionScheduler {
  /// DPM++ 2M Karras - Recommended for best quality/speed tradeoff
  dpmPP2MKarras('dpm++_2m_karras', 0),

  /// DPM++ 2M
  dpmPP2M('dpm++_2m', 1),

  /// DPM++ 2M SDE
  dpmPP2MSDE('dpm++_2m_sde', 2),

  /// DDIM
  ddim('ddim', 3),

  /// Euler
  euler('euler', 4),

  /// Euler Ancestral
  eulerAncestral('euler_a', 5),

  /// PNDM
  pndm('pndm', 6),

  /// LMS
  lms('lms', 7);

  const DiffusionScheduler(this.rawValue, this.cValue);

  final String rawValue;
  final int cValue;
}

// ============================================================================
// Generation Mode
// ============================================================================

/// Generation mode for diffusion
enum DiffusionMode {
  /// Generate image from text prompt
  textToImage('txt2img', 0),

  /// Transform input image with prompt
  imageToImage('img2img', 1),

  /// Edit specific regions with mask
  inpainting('inpainting', 2);

  const DiffusionMode(this.rawValue, this.cValue);

  final String rawValue;
  final int cValue;
}

// ============================================================================
// Configuration
// ============================================================================

/// Configuration for the diffusion component
class DiffusionConfiguration {
  final String? modelId;
  final DiffusionModelVariant modelVariant;
  final bool enableSafetyChecker;
  final bool reduceMemory;
  final InferenceFramework? preferredFramework;
  final DiffusionTokenizerSource? tokenizerSource;

  const DiffusionConfiguration({
    this.modelId,
    this.modelVariant = DiffusionModelVariant.sd15,
    this.enableSafetyChecker = true,
    this.reduceMemory = false,
    this.preferredFramework,
    this.tokenizerSource,
  });

  /// The effective tokenizer source (uses model variant default if not specified)
  DiffusionTokenizerSource get effectiveTokenizerSource =>
      tokenizerSource ?? modelVariant.defaultTokenizerSource;
}

// ============================================================================
// Generation Options
// ============================================================================

/// Options for image generation
class DiffusionGenerationOptions {
  final String prompt;
  final String negativePrompt;
  final int width;
  final int height;
  final int steps;
  final double guidanceScale;
  final int seed;
  final DiffusionScheduler scheduler;
  final DiffusionMode mode;
  final List<int>? inputImage;
  final List<int>? maskImage;
  final double denoiseStrength;
  final bool reportIntermediateImages;
  final int progressStride;

  const DiffusionGenerationOptions({
    required this.prompt,
    this.negativePrompt = '',
    this.width = 512,
    this.height = 512,
    this.steps = 28,
    this.guidanceScale = 7.5,
    this.seed = -1,
    this.scheduler = DiffusionScheduler.dpmPP2MKarras,
    this.mode = DiffusionMode.textToImage,
    this.inputImage,
    this.maskImage,
    this.denoiseStrength = 0.75,
    this.reportIntermediateImages = false,
    this.progressStride = 1,
  });

  /// Create options for text-to-image generation
  factory DiffusionGenerationOptions.textToImage({
    required String prompt,
    String negativePrompt = '',
    int width = 512,
    int height = 512,
    int steps = 28,
    double guidanceScale = 7.5,
    int seed = -1,
    DiffusionScheduler scheduler = DiffusionScheduler.dpmPP2MKarras,
  }) {
    return DiffusionGenerationOptions(
      prompt: prompt,
      negativePrompt: negativePrompt,
      width: width,
      height: height,
      steps: steps,
      guidanceScale: guidanceScale,
      seed: seed,
      scheduler: scheduler,
      mode: DiffusionMode.textToImage,
    );
  }

  /// Create options for image-to-image transformation
  factory DiffusionGenerationOptions.imageToImage({
    required String prompt,
    required List<int> inputImage,
    String negativePrompt = '',
    double denoiseStrength = 0.75,
    int steps = 28,
    double guidanceScale = 7.5,
    int seed = -1,
    DiffusionScheduler scheduler = DiffusionScheduler.dpmPP2MKarras,
  }) {
    return DiffusionGenerationOptions(
      prompt: prompt,
      negativePrompt: negativePrompt,
      steps: steps,
      guidanceScale: guidanceScale,
      seed: seed,
      scheduler: scheduler,
      mode: DiffusionMode.imageToImage,
      inputImage: inputImage,
      denoiseStrength: denoiseStrength,
    );
  }

  /// Create options for inpainting
  factory DiffusionGenerationOptions.inpainting({
    required String prompt,
    required List<int> inputImage,
    required List<int> maskImage,
    String negativePrompt = '',
    int steps = 28,
    double guidanceScale = 7.5,
    int seed = -1,
    DiffusionScheduler scheduler = DiffusionScheduler.dpmPP2MKarras,
  }) {
    return DiffusionGenerationOptions(
      prompt: prompt,
      negativePrompt: negativePrompt,
      steps: steps,
      guidanceScale: guidanceScale,
      seed: seed,
      scheduler: scheduler,
      mode: DiffusionMode.inpainting,
      inputImage: inputImage,
      maskImage: maskImage,
    );
  }
}

// ============================================================================
// Progress
// ============================================================================

/// Progress update during image generation
class DiffusionProgress {
  final double progress;
  final int currentStep;
  final int totalSteps;
  final String stage;
  final List<int>? intermediateImage;

  const DiffusionProgress({
    required this.progress,
    required this.currentStep,
    required this.totalSteps,
    required this.stage,
    this.intermediateImage,
  });
}

// ============================================================================
// Result
// ============================================================================

/// Result of image generation
class DiffusionResult {
  final List<int> imageData;
  final int width;
  final int height;
  final int seedUsed;
  final int generationTimeMs;
  final bool safetyFlagged;

  const DiffusionResult({
    required this.imageData,
    required this.width,
    required this.height,
    required this.seedUsed,
    required this.generationTimeMs,
    this.safetyFlagged = false,
  });
}
