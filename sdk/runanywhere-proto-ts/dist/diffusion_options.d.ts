import _m0 from "protobufjs/minimal";
export declare const protobufPackage = "runanywhere.v1";
/**
 * ---------------------------------------------------------------------------
 * Generation mode. Sources pre-IDL (identical across all surfaces):
 *   Swift   DiffusionTypes.swift:257    (textToImage / imageToImage / inpainting)
 *   Kotlin  DiffusionTypes.kt:188       (TEXT_TO_IMAGE / IMAGE_TO_IMAGE / INPAINTING)
 *   RN      DiffusionTypes.ts:73        (TextToImage / ImageToImage / Inpainting)
 *   Web     DiffusionTypes.ts:23        (TextToImage / ImageToImage / Inpainting)
 *   C ABI   rac_diffusion_types.h:59    (RAC_DIFFUSION_MODE_*)
 * ---------------------------------------------------------------------------
 */
export declare enum DiffusionMode {
    DIFFUSION_MODE_UNSPECIFIED = 0,
    DIFFUSION_MODE_TEXT_TO_IMAGE = 1,
    DIFFUSION_MODE_IMAGE_TO_IMAGE = 2,
    DIFFUSION_MODE_INPAINTING = 3,
    UNRECOGNIZED = -1
}
export declare function diffusionModeFromJSON(object: any): DiffusionMode;
export declare function diffusionModeToJSON(object: DiffusionMode): string;
/**
 * ---------------------------------------------------------------------------
 * Scheduler / sampler algorithm — *forward-looking union*.
 *
 * Pre-IDL sources all expose the same eight cases (DPM++ 2M Karras, DPM++ 2M,
 * DPM++ 2M SDE, DDIM, Euler, Euler Ancestral, PNDM, LMS); see:
 *   Swift   DiffusionTypes.swift:184    (.dpmPP2MKarras .. .lms)
 *   Kotlin  DiffusionTypes.kt:155       (DPM_PP_2M_KARRAS .. LMS)
 *   RN      DiffusionTypes.ts:48        (DPMPP2MKarras .. LMS)
 *   Web     DiffusionTypes.ts:3         (numeric DPM_PP_2M_Karras .. LMS, matches C ABI)
 *   C ABI   rac_diffusion_types.h:31    (RAC_DIFFUSION_SCHEDULER_*)
 *
 * This proto enum extends that with two values that downstream backends are
 * expected to grow into but no SDK exposes yet:
 *   - DDPM   — original Ho et al. 2020 sampler
 *   - LCM    — Latent Consistency Model sampler (paired with the LCM model
 *              variant; today Swift/Kotlin reuse DPM++ 2M Karras for LCM
 *              models because no LCM scheduler case exists).
 * And it intentionally omits DPMPP_2M_SDE, which exists in every SDK today
 * but is being collapsed back into DPMPP_2M for the v1 IDL surface (the SDE
 * variant is purely an algorithmic toggle on DPM++ 2M; backends accept
 * either tag).
 *
 * Drift reconciliation:
 *   - Swift/Kotlin/RN/Web/C-ABI carriers of DPMPP_2M_SDE must round-trip
 *     that case to DIFFUSION_SCHEDULER_DPMPP_2M (lossy in name, equivalent
 *     in semantics — the SDE flag is a backend implementation detail).
 *   - DDPM and LCM are *new* slots; SDKs that don't yet recognize them must
 *     fall back to DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS (the recommended
 *     default).
 * ---------------------------------------------------------------------------
 */
export declare enum DiffusionScheduler {
    DIFFUSION_SCHEDULER_UNSPECIFIED = 0,
    /** DIFFUSION_SCHEDULER_DPMPP_2M - Swift/Kotlin/RN/Web/C-ABI */
    DIFFUSION_SCHEDULER_DPMPP_2M = 1,
    /** DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS - Swift/Kotlin/RN/Web/C-ABI (recommended default) */
    DIFFUSION_SCHEDULER_DPMPP_2M_KARRAS = 2,
    /** DIFFUSION_SCHEDULER_DDIM - Swift/Kotlin/RN/Web/C-ABI */
    DIFFUSION_SCHEDULER_DDIM = 3,
    /** DIFFUSION_SCHEDULER_DDPM - forward-looking — no SDK exposes this yet */
    DIFFUSION_SCHEDULER_DDPM = 4,
    /** DIFFUSION_SCHEDULER_EULER - Swift/Kotlin/RN/Web/C-ABI */
    DIFFUSION_SCHEDULER_EULER = 5,
    /** DIFFUSION_SCHEDULER_EULER_A - Swift/Kotlin/RN/Web/C-ABI ("Euler Ancestral") */
    DIFFUSION_SCHEDULER_EULER_A = 6,
    /** DIFFUSION_SCHEDULER_PNDM - Swift/Kotlin/RN/Web/C-ABI */
    DIFFUSION_SCHEDULER_PNDM = 7,
    /** DIFFUSION_SCHEDULER_LMS - Swift/Kotlin/RN/Web/C-ABI */
    DIFFUSION_SCHEDULER_LMS = 8,
    /** DIFFUSION_SCHEDULER_LCM - forward-looking — pairs with the LCM model variant */
    DIFFUSION_SCHEDULER_LCM = 9,
    UNRECOGNIZED = -1
}
export declare function diffusionSchedulerFromJSON(object: any): DiffusionScheduler;
export declare function diffusionSchedulerToJSON(object: DiffusionScheduler): string;
/**
 * ---------------------------------------------------------------------------
 * Stable Diffusion model variant. Sources pre-IDL (identical 6 cases):
 *   Swift  DiffusionTypes.swift:92     (sd15 / sd21 / sdxl / sdxlTurbo / sdxs / lcm)
 *   Kotlin DiffusionTypes.kt:85        (SD15 / SD21 / SDXL / SDXL_TURBO / SDXS / LCM)
 *   RN     DiffusionTypes.ts:28        (SD15 / SD21 / SDXL / SDXLTurbo / SDXS / LCM)
 *   Web    DiffusionTypes.ts:14        (numeric SD_1_5 / SD_2_1 / SDXL / SDXL_Turbo / SDXS / LCM)
 *   C ABI  rac_diffusion_types.h:47    (RAC_DIFFUSION_MODEL_*)
 * ---------------------------------------------------------------------------
 */
export declare enum DiffusionModelVariant {
    DIFFUSION_MODEL_VARIANT_UNSPECIFIED = 0,
    DIFFUSION_MODEL_VARIANT_SD_1_5 = 1,
    DIFFUSION_MODEL_VARIANT_SD_2_1 = 2,
    DIFFUSION_MODEL_VARIANT_SDXL = 3,
    DIFFUSION_MODEL_VARIANT_SDXL_TURBO = 4,
    DIFFUSION_MODEL_VARIANT_SDXS = 5,
    /** DIFFUSION_MODEL_VARIANT_LCM - Latent Consistency Model */
    DIFFUSION_MODEL_VARIANT_LCM = 6,
    UNRECOGNIZED = -1
}
export declare function diffusionModelVariantFromJSON(object: any): DiffusionModelVariant;
export declare function diffusionModelVariantToJSON(object: DiffusionModelVariant): string;
/**
 * ---------------------------------------------------------------------------
 * Tokenizer source kind. Apple's compiled CoreML SD models do not bundle
 * vocab.json / merges.txt, so the tokenizer must be downloaded from a
 * HuggingFace repo (or a developer-supplied URL).
 * Sources pre-IDL:
 *   Swift  DiffusionTypes.swift:18     (.sd15 / .sd2 / .sdxl / .custom(baseURL:))
 *   Kotlin DiffusionTypes.kt:31        (Sd15 / Sd2 / Sdxl / Custom(customBaseUrl))
 *   RN     DiffusionTypes.ts:17        ({kind:'sd15'|'sd2'|'sdxl'|'custom'} discriminated union)
 *   Web    — n/a (the llamacpp Web package doesn't expose tokenizer source)
 *   C ABI  rac_diffusion_types.h:79    (RAC_DIFFUSION_TOKENIZER_SD_1_5 / SD_2_X / SDXL / CUSTOM)
 * ---------------------------------------------------------------------------
 */
export declare enum DiffusionTokenizerSourceKind {
    DIFFUSION_TOKENIZER_SOURCE_KIND_UNSPECIFIED = 0,
    /** DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 - CLIP ViT-L/14 (runwayml/stable-diffusion-v1-5) */
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD15 = 1,
    /** DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 - OpenCLIP ViT-H/14 (stabilityai/stable-diffusion-2-1) */
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SD2 = 2,
    /** DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL - dual tokenizers (stabilityai/stable-diffusion-xl-base-1.0) */
    DIFFUSION_TOKENIZER_SOURCE_KIND_BUNDLED_SDXL = 3,
    /** DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM - developer-supplied base URL */
    DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM = 4,
    UNRECOGNIZED = -1
}
export declare function diffusionTokenizerSourceKindFromJSON(object: any): DiffusionTokenizerSourceKind;
export declare function diffusionTokenizerSourceKindToJSON(object: DiffusionTokenizerSourceKind): string;
/**
 * ---------------------------------------------------------------------------
 * Tokenizer source descriptor. `kind` is the preset; `custom_path` is only
 * meaningful when kind == CUSTOM and points at a directory URL containing
 * vocab.json + merges.txt (the SDK appends those filenames itself).
 * ---------------------------------------------------------------------------
 */
export interface DiffusionTokenizerSource {
    kind: DiffusionTokenizerSourceKind;
    /**
     * Only set when kind == DIFFUSION_TOKENIZER_SOURCE_KIND_CUSTOM. Empty /
     * unset for the bundled presets.
     */
    customPath?: string | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Diffusion component configuration — the static, lifetime-of-component
 * settings handed to the diffusion service at initialize() time.
 * Sources pre-IDL:
 *   Swift  DiffusionTypes.swift:279    (DiffusionConfiguration)
 *   Kotlin DiffusionTypes.kt:204       (DiffusionConfiguration)
 *   RN     DiffusionTypes.ts:86        (DiffusionConfiguration)
 *   Web    — n/a (config is implicit in the llamacpp service ctor)
 *   C ABI  rac_diffusion_types.h:144   (rac_diffusion_config_t)
 *
 * Drift note: Swift/Kotlin/RN also carry `model_id`, `preferred_framework`,
 * and `reduce_memory` fields. Those belong on the more general component
 * configuration carried by ModelInfo / framework selection elsewhere in
 * this IDL package; this message intentionally narrows to the four
 * diffusion-specific knobs called out by the v1 spec.
 * `max_memory_mb` here is the new generalization of pre-IDL `reduce_memory`
 * (a bool) — backends interpret 0 as "no cap / engine default" and any
 * positive value as a hard MB ceiling. SDKs translating pre-IDL
 * `reduceMemory == true` should set this to the backend's documented
 * reduced-memory threshold; `reduceMemory == false` ⇒ 0.
 * ---------------------------------------------------------------------------
 */
export interface DiffusionConfiguration {
    /**
     * Stable Diffusion model variant (selects the default resolution, step
     * count, guidance scale, and tokenizer preset).
     */
    modelVariant: DiffusionModelVariant;
    /**
     * Tokenizer download source (CoreML SD models don't bundle the
     * tokenizer files — the runtime must fetch vocab.json + merges.txt).
     */
    tokenizerSource?: DiffusionTokenizerSource | undefined;
    /**
     * Run NSFW safety checker on the decoded latent before returning the
     * image. Default in every SDK is true.
     */
    enableSafetyChecker: boolean;
    /**
     * Maximum working-set memory the diffusion runtime is allowed to use,
     * in MiB. 0 = no cap (engine default). Generalizes the pre-IDL
     * `reduceMemory` bool flag.
     */
    maxMemoryMb: number;
}
/**
 * ---------------------------------------------------------------------------
 * Per-call generation options. Sources pre-IDL:
 *   Swift  DiffusionTypes.swift:341    (DiffusionGenerationOptions)
 *   Kotlin DiffusionTypes.kt:230       (DiffusionGenerationOptions)
 *   RN     DiffusionTypes.ts:114       (DiffusionGenerationOptions)
 *   Web    DiffusionTypes.ts:29        (DiffusionGenerationOptions)
 *   C ABI  rac_diffusion_types.h:187   (rac_diffusion_options_t)
 *
 * Drift note: pre-IDL Swift/Kotlin/RN carry additional fields that the v1
 * IDL deliberately drops from this message in favor of more general /
 * future carriers:
 *   - input_image / mask_image (bytes)         → flows through a separate
 *                                                input artifact message in
 *                                                the service IDL
 *   - denoise_strength (float)                 → deferred (img2img-only,
 *                                                not in spec)
 *   - report_intermediate_images / progress_stride → covered by
 *                                                DiffusionProgress
 *                                                streaming semantics
 * ---------------------------------------------------------------------------
 */
export interface DiffusionGenerationOptions {
    /** Text prompt describing the desired image. Required. */
    prompt: string;
    /** Things to avoid in the image. Empty = no negative prompt. */
    negativePrompt: string;
    /**
     * Output image width  in pixels.  0 = use variant default
     * (512 for SD 1.5 / SDXS / LCM, 768 for SD 2.1, 1024 for SDXL / Turbo).
     */
    width: number;
    /** Output image height in pixels.  0 = use variant default. */
    height: number;
    /**
     * Number of denoising steps. Range 1–50 (variant-dependent: SDXS=1,
     * SDXL_Turbo / LCM=4, SD*=20–28). 0 = use variant default.
     */
    numInferenceSteps: number;
    /**
     * Classifier-free guidance scale. 0.0 = no CFG (required for SDXS /
     * SDXL_Turbo). Typical SD range 1.0–20.0; default 7.5.
     */
    guidanceScale: number;
    /** RNG seed for reproducibility. -1 = pick a random seed. */
    seed: number;
    /**
     * Sampler algorithm. UNSPECIFIED = backend picks (recommended:
     * DPMPP_2M_KARRAS).
     */
    scheduler: DiffusionScheduler;
    /**
     * Generation mode (txt2img / img2img / inpainting). UNSPECIFIED =
     * TEXT_TO_IMAGE.
     */
    mode: DiffusionMode;
}
/**
 * ---------------------------------------------------------------------------
 * Streamed progress event. Sources pre-IDL:
 *   Swift  DiffusionTypes.swift:511    (DiffusionProgress)
 *   Kotlin DiffusionTypes.kt:337       (DiffusionProgress)
 *   RN     DiffusionTypes.ts:163       (DiffusionProgress)
 *   Web    DiffusionTypes.ts:69        (callback signature, not a struct)
 *   C ABI  rac_diffusion_types.h:279   (rac_diffusion_progress_t)
 * ---------------------------------------------------------------------------
 */
export interface DiffusionProgress {
    /** Fraction of denoising completed in [0.0, 1.0]. */
    progressPercent: number;
    /** 1-based current step number. */
    currentStep: number;
    /** Total number of steps the engine plans to execute. */
    totalSteps: number;
    /** Free-form stage name ("Encoding", "Denoising", "Decoding", …). */
    stage: string;
    /**
     * Optional intermediate image bytes (PNG when surfaced by
     * Swift/Kotlin/RN; raw RGBA when surfaced by the C ABI). Present only
     * when the caller requested intermediate-image reporting and the
     * engine has produced one for this step.
     */
    intermediateImageData?: Uint8Array | undefined;
}
/**
 * ---------------------------------------------------------------------------
 * Final generation result. Sources pre-IDL:
 *   Swift  DiffusionTypes.swift:560    (DiffusionResult)
 *   Kotlin DiffusionTypes.kt:355       (DiffusionResult)
 *   RN     DiffusionTypes.ts:185       (DiffusionResult)
 *   Web    DiffusionTypes.ts:54        (DiffusionGenerationResult)
 *   C ABI  rac_diffusion_types.h:314   (rac_diffusion_result_t)
 *
 * Drift note: pre-IDL Swift/Kotlin/RN/Web all name the wall-clock field
 * `generation_time_ms`. The v1 IDL renames it to `total_time_ms` per the
 * spec — round-trip is a pure rename. `used_scheduler` is *new* in the IDL
 * (no pre-IDL surface echoes back which scheduler actually ran when the
 * caller sent UNSPECIFIED); it lets clients log which sampler the engine
 * chose.
 * ---------------------------------------------------------------------------
 */
export interface DiffusionResult {
    /**
     * Encoded image. PNG bytes on Swift/Kotlin/RN; raw RGBA bytes on the
     * C ABI / Web llamacpp surface. (Encoding is a property of the
     * backend's vtable, not of this message.)
     */
    imageData: Uint8Array;
    /** Final image width  in pixels. */
    width: number;
    /** Final image height in pixels. */
    height: number;
    /** Seed actually used (resolved if the caller passed -1 for random). */
    seedUsed: number;
    /**
     * Total wall-clock generation time in milliseconds (renamed from
     * pre-IDL `generation_time_ms`).
     */
    totalTimeMs: number;
    /**
     * Whether the safety checker flagged the image as NSFW. False if the
     * checker was disabled in DiffusionConfiguration.
     */
    safetyFlag: boolean;
    /**
     * Scheduler the engine actually ran. Useful when the caller passed
     * DIFFUSION_SCHEDULER_UNSPECIFIED.
     */
    usedScheduler: DiffusionScheduler;
}
/**
 * ---------------------------------------------------------------------------
 * Capability descriptor for the loaded diffusion backend / model. Sources
 * pre-IDL:
 *   Swift  DiffusionCapabilities (OptionSet bit flags — supportsTextToImage,
 *          supportsImageToImage, supportsInpainting, supportsIntermediateImages,
 *          supportsSafetyChecker)
 *   Kotlin DiffusionTypes.kt:378       (DiffusionCapabilities, mirror of Swift)
 *   RN     DiffusionTypes.ts:210       (interface with supportedVariants /
 *          supportedSchedulers / supportedModes / maxWidth / maxHeight /
 *          supportsIntermediateImages)
 *   Web    — n/a
 *   C ABI  rac_diffusion_types.h:352   (rac_diffusion_info_t — flags +
 *          max_width / max_height)
 *
 * The IDL takes the RN-style "what can the backend do?" shape (lists of
 * supported enums + a single max-resolution scalar) since it carries the
 * most information; SDKs whose pre-IDL surface is a bit-flag set must map
 * each flag to populating / leaving the corresponding repeated field.
 * `max_resolution_px` represents the larger of width/height the backend can
 * produce in a single call (RN/C-ABI carry width and height separately —
 * for square SD models they're equal; for the IDL we fold them to the
 * shared cap and document that asymmetric caps would need a future
 * `max_width_px` / `max_height_px` split).
 * ---------------------------------------------------------------------------
 */
export interface DiffusionCapabilities {
    /** Stable Diffusion model variants this backend can load. */
    supportedVariants: DiffusionModelVariant[];
    /** Sampler algorithms this backend implements. */
    supportedSchedulers: DiffusionScheduler[];
    /**
     * Largest image edge (in pixels) the backend can produce in a single
     * generation. 0 = unknown / not advertised.
     */
    maxResolutionPx: number;
}
export declare const DiffusionTokenizerSource: {
    encode(message: DiffusionTokenizerSource, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DiffusionTokenizerSource;
    fromJSON(object: any): DiffusionTokenizerSource;
    toJSON(message: DiffusionTokenizerSource): unknown;
    create<I extends Exact<DeepPartial<DiffusionTokenizerSource>, I>>(base?: I): DiffusionTokenizerSource;
    fromPartial<I extends Exact<DeepPartial<DiffusionTokenizerSource>, I>>(object: I): DiffusionTokenizerSource;
};
export declare const DiffusionConfiguration: {
    encode(message: DiffusionConfiguration, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DiffusionConfiguration;
    fromJSON(object: any): DiffusionConfiguration;
    toJSON(message: DiffusionConfiguration): unknown;
    create<I extends Exact<DeepPartial<DiffusionConfiguration>, I>>(base?: I): DiffusionConfiguration;
    fromPartial<I extends Exact<DeepPartial<DiffusionConfiguration>, I>>(object: I): DiffusionConfiguration;
};
export declare const DiffusionGenerationOptions: {
    encode(message: DiffusionGenerationOptions, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DiffusionGenerationOptions;
    fromJSON(object: any): DiffusionGenerationOptions;
    toJSON(message: DiffusionGenerationOptions): unknown;
    create<I extends Exact<DeepPartial<DiffusionGenerationOptions>, I>>(base?: I): DiffusionGenerationOptions;
    fromPartial<I extends Exact<DeepPartial<DiffusionGenerationOptions>, I>>(object: I): DiffusionGenerationOptions;
};
export declare const DiffusionProgress: {
    encode(message: DiffusionProgress, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DiffusionProgress;
    fromJSON(object: any): DiffusionProgress;
    toJSON(message: DiffusionProgress): unknown;
    create<I extends Exact<DeepPartial<DiffusionProgress>, I>>(base?: I): DiffusionProgress;
    fromPartial<I extends Exact<DeepPartial<DiffusionProgress>, I>>(object: I): DiffusionProgress;
};
export declare const DiffusionResult: {
    encode(message: DiffusionResult, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DiffusionResult;
    fromJSON(object: any): DiffusionResult;
    toJSON(message: DiffusionResult): unknown;
    create<I extends Exact<DeepPartial<DiffusionResult>, I>>(base?: I): DiffusionResult;
    fromPartial<I extends Exact<DeepPartial<DiffusionResult>, I>>(object: I): DiffusionResult;
};
export declare const DiffusionCapabilities: {
    encode(message: DiffusionCapabilities, writer?: _m0.Writer): _m0.Writer;
    decode(input: _m0.Reader | Uint8Array, length?: number): DiffusionCapabilities;
    fromJSON(object: any): DiffusionCapabilities;
    toJSON(message: DiffusionCapabilities): unknown;
    create<I extends Exact<DeepPartial<DiffusionCapabilities>, I>>(base?: I): DiffusionCapabilities;
    fromPartial<I extends Exact<DeepPartial<DiffusionCapabilities>, I>>(object: I): DiffusionCapabilities;
};
type Builtin = Date | Function | Uint8Array | string | number | boolean | undefined;
export type DeepPartial<T> = T extends Builtin ? T : T extends globalThis.Array<infer U> ? globalThis.Array<DeepPartial<U>> : T extends ReadonlyArray<infer U> ? ReadonlyArray<DeepPartial<U>> : T extends {} ? {
    [K in keyof T]?: DeepPartial<T[K]>;
} : Partial<T>;
type KeysOfUnion<T> = T extends T ? keyof T : never;
export type Exact<P, I extends P> = P extends Builtin ? P : P & {
    [K in keyof P]: Exact<P[K], I[K]>;
} & {
    [K in Exclude<keyof I, KeysOfUnion<P>>]: never;
};
export {};
//# sourceMappingURL=diffusion_options.d.ts.map