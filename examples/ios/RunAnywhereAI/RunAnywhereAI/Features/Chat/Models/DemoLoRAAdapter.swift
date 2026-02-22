//
//  DemoLoRAAdapter.swift
//  RunAnywhereAI
//
//  TODO: [Portal Integration] Remove this entire file once adapters are delivered OTA from portal.
//
//  =========================================================================================
//  LoRA Demo Integration Guide
//  =========================================================================================
//
//  WHAT THIS IS
//  ------------
//  This file provides a temporary, hardcoded LoRA adapter catalog so we can verify that the
//  full LoRA pipeline works end-to-end on iOS: download adapter OTA -> apply to model -> generate.
//  Once the RunAnywhere portal delivers adapter catalogs via its API, this file should be deleted
//  and replaced with the portal-provided data.
//
//
//  WHY QWEN 2.5 1.5B WAS CHOSEN
//  -----------------------------
//  LoRA adapters are architecture-specific: an adapter trained on Model A cannot be used with
//  Model B, even if they're the same parameter count. We needed a base model + GGUF LoRA adapter
//  pair that is publicly available and proven to work with llama.cpp.
//
//  - SmolLM2 360M:   No GGUF LoRA adapters exist anywhere (no one has published a fine-tune).
//  - Qwen 2.5 0.5B:  No matching adapter (smallest ggml-org adapter is for 1.5B).
//  - LFM2 350M:      No LoRA adapters exist. LFM2.5-1.2B adapters are architecturally incompatible
//                     with the LFM2-1.2B-Tool model in the app (different model version).
//  - Qwen 2.5 1.5B:  ggml-org (the llama.cpp team) publishes a tested, GGUF-format "abliterated"
//                     LoRA adapter (~374MB). This is the smallest proven pair available.
//
//  The Qwen 2.5 1.5B base model is registered in RunAnywhereAIApp.swift (~986MB Q4_K_M GGUF).
//
//
//  CONTEXT SIZE & MEMORY (C++ CHANGE)
//  ----------------------------------
//  Qwen 2.5 1.5B has 1.5B parameters and a 128K training context. The C++ llama.cpp backend
//  uses adaptive context sizing based on model size:
//
//    >= 7B params  -> 2048 context   (fits ~6GB GPU memory)
//    >= 3B params  -> 4096 context
//    >= 1B params  -> 2048 context   (** we added this tier **)
//    <  1B params  -> 8192 context   (tiny models, plenty of headroom)
//
//  Without the 1-3B tier, the 1.5B model got 8192 context -> 4,748 MB compute buffer -> OOM crash.
//  Even at 4096, applying the F16 LoRA adapter pushed the compute buffer to 2,399 MB -> OOM.
//  At 2048 context, total runtime memory is ~2.5GB (weights + KV cache + LoRA + compute), which
//  fits on 6GB+ iPhones (iPhone 14 and newer).
//
//  This change lives in: sdk/runanywhere-commons/src/backends/llamacpp/llamacpp_backend.cpp
//  (search for "Small-medium model detected")
//
//
//  LORA SCALE NOTE
//  ---------------
//  The demo adapter is F16 (full precision) applied to a Q4_K_M (4-bit quantized) base model.
//  At scale 1.0, this causes numerical instability -> gibberish output. Scale 0.3 is the tested
//  sweet spot: coherent output with observable behavior change. The UI slider still allows
//  adjustment (0.0 - 2.0) for experimentation.
//
//
//  PORTAL INTEGRATION CHECKLIST
//  ----------------------------
//  When the portal delivers LoRA adapters OTA, do the following:
//
//  1. DELETE this file (DemoLoRAAdapter.swift)
//  2. DELETE the Qwen 2.5 1.5B model registration in RunAnywhereAIApp.swift
//     (search for "qwen2.5-1.5b-instruct-q4_k_m" and the TODO above it)
//  3. In LLMViewModel.swift, REPLACE the demo adapter state & download logic
//     (search for "TODO: [Portal Integration]") with portal API calls
//  4. In ChatInterfaceView.swift, UPDATE the "Available for This Model" section
//     in LoRAManagementSheetView to use portal-provided adapter data
//     (search for "TODO: [Portal Integration]")
//  5. The SDK-level LoRA API (RunAnywhere+LoRA.swift, CppBridge+LLM.swift) stays unchanged --
//     it takes a local file path + scale, which is the same regardless of how the file got there
//
//  =========================================================================================

import Foundation

// MARK: - Demo LoRA Adapter Registry

/// Represents a pre-registered LoRA adapter available for OTA download.
/// TODO: [Portal Integration] Replace with portal-provided adapter catalog model.
struct DemoLoRAAdapter: Identifiable, Sendable {
    let id: String
    let name: String
    let description: String
    let downloadURL: URL
    let fileName: String
    let compatibleModelIds: Set<String>
    let fileSize: Int64
    let defaultScale: Float

    var fileSizeFormatted: String {
        ByteCountFormatter.string(fromByteCount: fileSize, countStyle: .file)
    }
}

// MARK: - Demo Adapter Catalog

/// TODO: [Portal Integration] Remove once adapters are delivered OTA from portal.
enum DemoLoRAAdapterCatalog {
    static let adapters: [DemoLoRAAdapter] = [
        DemoLoRAAdapter(
            id: "qwen2.5-1.5b-abliterated-lora",
            name: "Abliterated (Uncensored)",
            description: "Removes refusal behavior from Qwen2.5-1.5B. From ggml-org.",
            downloadURL: URL(string: "https://huggingface.co/ggml-org/LoRA-Qwen2.5-1.5B-Instruct-abliterated-F16-GGUF/resolve/main/LoRA-Qwen2.5-1.5B-Instruct-abliterated-f16.gguf")!,
            fileName: "LoRA-Qwen2.5-1.5B-Instruct-abliterated-f16.gguf",
            compatibleModelIds: ["qwen2.5-1.5b-instruct-q4_k_m"],
            fileSize: 374_000_000,
            defaultScale: 0.3
        )
    ]

    static func adapters(forModelId modelId: String) -> [DemoLoRAAdapter] {
        adapters.filter { $0.compatibleModelIds.contains(modelId) }
    }
}
