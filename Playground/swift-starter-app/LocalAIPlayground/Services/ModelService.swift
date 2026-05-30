//
//  ModelService.swift
//  LocalAIPlayground
//
//  =============================================================================
//  MODEL SERVICE - AI MODEL MANAGEMENT
//  =============================================================================
//
//  This service handles the lifecycle of AI models in the RunAnywhere SDK:
//
//  1. Model Registration - Register models with URLs and metadata
//  2. Model Download     - Fetch models from remote repositories
//  3. Model Loading      - Load models into memory for inference
//  4. Model Caching      - Manage local model storage
//
//  MODELS USED IN THIS APP:
//  ┌────────────┬─────────────────────────────────┬─────────┐
//  │ Capability │ Model                           │ Size    │
//  ├────────────┼─────────────────────────────────┼─────────┤
//  │ LLM        │ LiquidAI LFM2 350M Q4_K_M       │ ~250MB  │
//  │ STT        │ Sherpa Whisper Tiny (English)   │ ~75MB   │
//  │ TTS        │ Piper en_US-lessac-medium       │ ~65MB   │
//  └────────────┴─────────────────────────────────┴─────────┘
//
//  Models are downloaded on first use and cached locally on the device.
//  Subsequent launches load from cache for instant availability.
//
//  =============================================================================

import Foundation
import SwiftUI
import Combine

// Import RunAnywhere SDK for model management APIs
import RunAnywhere

// =============================================================================
// MARK: - Model Service
// =============================================================================
/// Centralized service for managing AI model lifecycle.
///
/// This service provides a unified interface for downloading, loading, and
/// managing AI models across all capabilities (LLM, STT, TTS).
///
/// ## Usage Example
/// ```swift
/// let modelService = ModelService()
///
/// // Register models first (called at app init)
/// ModelService.registerDefaultModels()
///
/// // Download and load LLM
/// await modelService.downloadAndLoadLLM()
///
/// // Check if ready
/// if modelService.isLLMLoaded {
///     // Use the model
/// }
/// ```
// =============================================================================
@MainActor
final class ModelService: ObservableObject {
    
    // -------------------------------------------------------------------------
    // MARK: - Model IDs
    // -------------------------------------------------------------------------
    // These IDs must match the IDs used when registering models.
    // They are used to download and load the correct model.
    // -------------------------------------------------------------------------
    
    /// LLM model ID - LiquidAI LFM2 350M with Q4_K_M quantization
    static let llmModelId = "lfm2-350m-q4_k_m"
    
    /// STT model ID - Whisper Tiny (English)
    static let sttModelId = "sherpa-onnx-whisper-tiny.en"
    
    /// TTS voice ID - Piper US English (Lessac Medium)
    static let ttsModelId = "vits-piper-en_US-lessac-medium"
    
    // -------------------------------------------------------------------------
    // MARK: - Download State
    // -------------------------------------------------------------------------
    
    @Published var isLLMDownloading = false
    @Published var isSTTDownloading = false
    @Published var isTTSDownloading = false
    
    @Published var llmDownloadProgress: Double = 0.0
    @Published var sttDownloadProgress: Double = 0.0
    @Published var ttsDownloadProgress: Double = 0.0
    
    // -------------------------------------------------------------------------
    // MARK: - Load State
    // -------------------------------------------------------------------------
    
    @Published var isLLMLoading = false
    @Published var isSTTLoading = false
    @Published var isTTSLoading = false
    
    // -------------------------------------------------------------------------
    // MARK: - Loaded State
    // -------------------------------------------------------------------------
    
    @Published private(set) var isLLMLoaded = false
    @Published private(set) var isSTTLoaded = false
    @Published private(set) var isTTSLoaded = false
    
    // -------------------------------------------------------------------------
    // MARK: - Computed Properties
    // -------------------------------------------------------------------------
    
    /// Whether all models for voice agent are ready
    var isVoiceAgentReady: Bool {
        isLLMLoaded && isSTTLoaded && isTTSLoaded
    }
    
    /// Whether any model is currently downloading
    var isAnyDownloading: Bool {
        isLLMDownloading || isSTTDownloading || isTTSDownloading
    }
    
    /// Whether any model is currently loading
    var isAnyLoading: Bool {
        isLLMLoading || isSTTLoading || isTTSLoading
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Initialization
    // -------------------------------------------------------------------------
    
    init() {
        Task {
            await refreshLoadedStates()
        }
    }
    
    // =========================================================================
    // MARK: - Model Registration
    // =========================================================================
    
    /// Registers default models with the SDK.
    ///
    /// This must be called AFTER SDK initialization and backend registration,
    /// but BEFORE attempting to download or load any models.
    ///
    /// ## RunAnywhere SDK Pattern
    /// Models must be registered with:
    /// - A unique ID (used to reference the model later)
    /// - A display name
    /// - A download URL
    /// - The framework type (.llamaCpp for LLM, .onnx for STT/TTS)
    /// - Memory requirements (helps SDK manage resources)
    // -------------------------------------------------------------------------
    static func registerDefaultModels() {
        // -----------------------------------------------------------------
        // Register LLM Model
        // -----------------------------------------------------------------
        // LiquidAI LFM2 350M Q4_K_M - A small, fast, efficient model
        // Good for mobile devices with limited memory
        // -----------------------------------------------------------------
        if let lfm2URL = URL(string: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf") {
            RunAnywhere.registerModel(
                id: llmModelId,
                name: "LiquidAI LFM2 350M Q4_K_M",
                url: lfm2URL,
                framework: .llamaCpp,
                memoryRequirement: 250_000_000
            )
        }
        
        // -----------------------------------------------------------------
        // Register STT Model
        // -----------------------------------------------------------------
        // Whisper Tiny (English) - Fast, accurate for English speech
        // Uses Sherpa-ONNX runtime for efficient mobile inference
        // -----------------------------------------------------------------
        if let whisperURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz") {
            RunAnywhere.registerModel(
                id: sttModelId,
                name: "Sherpa Whisper Tiny (ONNX)",
                url: whisperURL,
                framework: .onnx,
                modality: .speechRecognition,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 75_000_000
            )
        }
        
        // -----------------------------------------------------------------
        // Register TTS Voice
        // -----------------------------------------------------------------
        // Piper TTS - US English, natural sounding neural TTS
        // Uses VITS architecture for high-quality synthesis
        // -----------------------------------------------------------------
        if let piperURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz") {
            RunAnywhere.registerModel(
                id: ttsModelId,
                name: "Piper TTS (US English - Medium)",
                url: piperURL,
                framework: .onnx,
                modality: .speechSynthesis,
                artifactType: .archive(.tarGz, structure: .nestedDirectory),
                memoryRequirement: 65_000_000
            )
        }
        
        print("✅ Models registered: LLM, STT, TTS")
    }
    
    // =========================================================================
    // MARK: - State Refresh
    // =========================================================================
    
    /// Refreshes the loaded state of all models.
    ///
    /// Queries the SDK to check which models are currently loaded into memory.
    // -------------------------------------------------------------------------
    func refreshLoadedStates() async {
        isLLMLoaded = await RunAnywhere.isModelLoaded
        isSTTLoaded = await RunAnywhere.isSTTModelLoaded
        isTTSLoaded = await RunAnywhere.isTTSVoiceLoaded
    }
    
    // =========================================================================
    // MARK: - LLM Operations
    // =========================================================================
    
    /// Downloads and loads the LLM model.
    ///
    /// This method:
    /// 1. Attempts to load from cache first
    /// 2. If not cached, downloads the model
    /// 3. Loads the model into memory
    ///
    /// ## RunAnywhere SDK Methods Used
    /// - `RunAnywhere.loadModel(id)` - Load a registered model
    /// - `RunAnywhere.downloadModel(id)` - Download a registered model
    // -------------------------------------------------------------------------
    func downloadAndLoadLLM() async {
        guard !isLLMDownloading && !isLLMLoading else { return }
        
        // Try to load first if already downloaded
        isLLMLoading = true
        do {
            try await RunAnywhere.loadModel(Self.llmModelId)
            isLLMLoaded = true
            isLLMLoading = false
            print("✅ LLM model loaded from cache")
            return
        } catch {
            print("LLM load attempt failed (will download): \(error)")
            isLLMLoading = false
        }
        
        // If loading failed, download the model
        isLLMDownloading = true
        llmDownloadProgress = 0.0
        
        do {
            // -----------------------------------------------------------------
            // Download Model with Progress
            // -----------------------------------------------------------------
            // RunAnywhere.downloadModel() returns an AsyncStream of progress
            // updates. Each progress object contains:
            // - overallProgress: 0.0 to 1.0
            // - stage: .downloading, .extracting, .completed, etc.
            // -----------------------------------------------------------------
            let progressStream = try await RunAnywhere.downloadModel(Self.llmModelId)
            
            for await progress in progressStream {
                llmDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("LLM download error: \(error)")
            isLLMDownloading = false
            return
        }
        
        isLLMDownloading = false
        
        // Load the model after download
        isLLMLoading = true
        do {
            try await RunAnywhere.loadModel(Self.llmModelId)
            isLLMLoaded = true
        } catch {
            print("LLM load error: \(error)")
        }
        isLLMLoading = false
    }
    
    /// Unloads the LLM model from memory.
    // -------------------------------------------------------------------------
    func unloadLLM() async {
        do {
            try await RunAnywhere.unloadModel()
            isLLMLoaded = false
            print("📤 LLM model unloaded")
        } catch {
            print("⚠️ LLM unload error: \(error)")
        }
    }
    
    // =========================================================================
    // MARK: - STT Operations
    // =========================================================================
    
    /// Downloads and loads the STT (Speech-to-Text) model.
    // -------------------------------------------------------------------------
    func downloadAndLoadSTT() async {
        guard !isSTTDownloading && !isSTTLoading else { return }
        
        // Try to load first if already downloaded
        isSTTLoading = true
        do {
            try await RunAnywhere.loadSTTModel(Self.sttModelId)
            isSTTLoaded = true
            isSTTLoading = false
            print("✅ STT model loaded from cache")
            return
        } catch {
            print("STT load attempt failed (will download): \(error)")
            isSTTLoading = false
        }
        
        // If loading failed, download the model
        isSTTDownloading = true
        sttDownloadProgress = 0.0
        
        do {
            let progressStream = try await RunAnywhere.downloadModel(Self.sttModelId)
            
            for await progress in progressStream {
                sttDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("STT download error: \(error)")
            isSTTDownloading = false
            return
        }
        
        isSTTDownloading = false
        
        // Load the model after download
        isSTTLoading = true
        do {
            try await RunAnywhere.loadSTTModel(Self.sttModelId)
            isSTTLoaded = true
        } catch {
            print("STT load error: \(error)")
        }
        isSTTLoading = false
    }
    
    /// Unloads the STT model from memory.
    // -------------------------------------------------------------------------
    func unloadSTT() async {
        do {
            try await RunAnywhere.unloadSTTModel()
            isSTTLoaded = false
            print("📤 STT model unloaded")
        } catch {
            print("⚠️ STT unload error: \(error)")
        }
    }
    
    // =========================================================================
    // MARK: - TTS Operations
    // =========================================================================
    
    /// Downloads and loads the TTS (Text-to-Speech) voice.
    // -------------------------------------------------------------------------
    func downloadAndLoadTTS() async {
        guard !isTTSDownloading && !isTTSLoading else { return }
        
        // Try to load first if already downloaded
        isTTSLoading = true
        do {
            try await RunAnywhere.loadTTSVoice(Self.ttsModelId)
            isTTSLoaded = true
            isTTSLoading = false
            print("✅ TTS voice loaded from cache")
            return
        } catch {
            print("TTS load attempt failed (will download): \(error)")
            isTTSLoading = false
        }
        
        // If loading failed, download the model
        isTTSDownloading = true
        ttsDownloadProgress = 0.0
        
        do {
            let progressStream = try await RunAnywhere.downloadModel(Self.ttsModelId)
            
            for await progress in progressStream {
                ttsDownloadProgress = progress.overallProgress
                if progress.stage == .completed {
                    break
                }
            }
        } catch {
            print("TTS download error: \(error)")
            isTTSDownloading = false
            return
        }
        
        isTTSDownloading = false
        
        // Load the voice after download
        isTTSLoading = true
        do {
            try await RunAnywhere.loadTTSVoice(Self.ttsModelId)
            isTTSLoaded = true
        } catch {
            print("TTS load error: \(error)")
        }
        isTTSLoading = false
    }
    
    /// Unloads the TTS voice from memory.
    // -------------------------------------------------------------------------
    func unloadTTS() async {
        do {
            try await RunAnywhere.unloadTTSVoice()
            isTTSLoaded = false
            print("📤 TTS voice unloaded")
        } catch {
            print("⚠️ TTS unload error: \(error)")
        }
    }
    
    // =========================================================================
    // MARK: - Batch Operations
    // =========================================================================
    
    /// Downloads and loads all models for the voice agent.
    ///
    /// Note: Downloads run sequentially to avoid SDK concurrency issues.
    // -------------------------------------------------------------------------
    func downloadAndLoadAllModels() async {
        await downloadAndLoadLLM()
        await downloadAndLoadSTT()
        await downloadAndLoadTTS()
    }
    
    /// Unloads all models to free memory.
    // -------------------------------------------------------------------------
    func unloadAllModels() async {
        await unloadLLM()
        await unloadSTT()
        await unloadTTS()
        await refreshLoadedStates()
    }
}
