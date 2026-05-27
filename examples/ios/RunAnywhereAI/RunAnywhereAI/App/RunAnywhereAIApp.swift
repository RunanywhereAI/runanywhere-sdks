//
//  RunAnywhereAIApp.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/21/25.
//

import SwiftUI
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime
// Deferred backends (MetalRT, WhisperKit, Diffusion) are excluded from the
// Swift v1 build. See `thoughts/shared/plans/curious-greeting-panda.md`.
#if canImport(UIKit)
import UIKit
#endif
import os
#if os(macOS)
import AppKit
#endif

// MARK: - Model Catalog Seed
//
// Registers the default example-app model catalog with the SDK registry.
// Mirrors the Flutter example's `_registerModulesAndModels()` and matches
// the Kotlin / RN / Web examples so every SDK surfaces the same baseline
// set of LLM / VLM / STT / TTS / VAD / embedding models (six modalities
// total — diffusion is deferred from the Swift v1 build). The example
// apps are each responsible for seeding their own catalog — the SDK does
// not ship a default list. See BUG-SWIFT-IOS-002.

// swiftlint:disable type_body_length
@main
struct RunAnywhereAIApp: App {
    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "RunAnywhereAIApp")
    #if os(iOS)
    @StateObject private var flowSession = FlowSessionManager.shared
    @State private var showFlowActivation = false
    #endif
    @State private var isSDKInitialized = false
    @State private var initializationError: Error?
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    ContentView()
                        #if os(iOS)
                        .environmentObject(flowSession)
                        .onOpenURL { url in
                            guard url.scheme == SharedConstants.urlScheme,
                                  url.host == "startFlow" else { return }
                            logger.info("📲 Received startFlow deep link")
                            showFlowActivation = true
                            Task { await flowSession.handleStartFlow() }
                        }
                        .fullScreenCover(isPresented: $showFlowActivation) {
                            FlowActivationView(isPresented: $showFlowActivation)
                                .environmentObject(flowSession)
                        }
                        #endif
                        .onAppear {
                            logger.info("__RUNANYWHERE_AI_READY__")
                            logger.info("🎉 App is ready to use!")
                        }
                } else if let error = initializationError {
                    InitializationErrorView(error: error) {
                        // Retry initialization
                        Task {
                            await retryInitialization()
                        }
                    }
                } else {
                    InitializationLoadingView()
                }
            }
            .task {
                _ = SettingsViewModel.shared
                logger.info("🏁 App launched, initializing SDK...")
                await initializeSDK()
            }
            .onChange(of: scenePhase) { _, phase in
                guard phase == .active, !isSDKInitialized, initializationError == nil else { return }
                Task {
                    _ = SettingsViewModel.shared
                    logger.info("🏁 App active, initializing SDK...")
                    await initializeSDK()
                }
            }
        }
        #if os(macOS)
        .windowStyle(.titleBar)
        .windowToolbarStyle(.unified)
        .defaultSize(width: 1200, height: 800)
        .windowResizability(.contentSize)
        #endif
    }

    private func initializeSDK() async {
        do {
            // Register backends with C++ registry FIRST, before any await. Otherwise we can
            // suspend at the next line and another task may run loadModel() → ensureServicesReady()
            // → only Platform is registered → -422 "No provider could handle the request".
            LlamaCPP.register(priority: 100)
            ONNX.register(priority: 100)

            // Clear any previous error
            await MainActor.run { initializationError = nil }

            logger.info("🎯 Initializing SDK...")

            let startTime = Date()

            try runSDKInitialize()

            // Seed the example-app model catalog (~20 entries across six
            // modalities: LLM / VLM / STT / TTS / VAD / embedding). Each SDK's
            // example owns its own catalog; the SDK does not ship a default list.
            // Diffusion is deferred from the Swift v1 build.
            await registerModulesAndModels()

            // Refresh generated model/catalog state.
            await refreshSDKCatalogs()

            let initTime = Date().timeIntervalSince(startTime)
            logger.info("✅ SDK successfully initialized!")
            logger.info("⚡ Initialization time: \(String(format: "%.3f", initTime * 1000), privacy: .public)ms")
            logger.info("🎯 SDK Status: \(RunAnywhere.isActive ? "Active" : "Inactive")")
            logger.info("🔧 Environment: \(RunAnywhere.environment?.description ?? "Unknown")")
            logger.info("📱 Services initialized for catalog refresh")

            // Mark as initialized
            await MainActor.run {
                isSDKInitialized = true
            }

            logger.info("💡 Model registry refreshed, user can now download and select models")
        } catch {
            logger.error("❌ SDK initialization failed: \(error, privacy: .public)")
            await MainActor.run {
                initializationError = error
            }
        }
    }

    /// Runs `RunAnywhere.initialize(...)` with either custom credentials
    /// (from Settings) or a default build-configuration-driven mode.
    private func runSDKInitialize() throws {
        // Check for custom API configuration (stored in Settings)
        let customApiKey = SettingsViewModel.getStoredApiKey()
        let customBaseURL = SettingsViewModel.getStoredBaseURL()

        if let apiKey = customApiKey,
           let baseURL = customBaseURL,
           !apiKey.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !baseURL.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
           !looksLikePlaceholder(apiKey),
           isUsableHTTPURL(baseURL) {
            // Custom configuration mode - use stored credentials
            // Always use .production for custom backends (model assignment auto-fetch enabled)
            logger.info("🔧 Found custom API configuration")
            logger.info("   Base URL: \(baseURL, privacy: .public)")

            try RunAnywhere.initialize(
                apiKey: apiKey,
                baseURL: baseURL,
                environment: .production
            )
            logger.info("✅ SDK initialized with CUSTOM configuration (production)")
        } else {
            // Default mode based on build configuration
            #if DEBUG
            // Development mode - uses Supabase, no API key needed
            try RunAnywhere.initialize()
            logger.info("✅ SDK initialized in DEVELOPMENT mode")
            #else
            // Release builds must be configured before launch — either via
            // the in-app Settings screen (which writes to Settings.bundle and
            // is read back via SettingsViewModel.getStoredApiKey()/getStoredBaseURL())
            // or via an .xcconfig that injects RUNANYWHERE_API_KEY /
            // RUNANYWHERE_BASE_URL at build time. We deliberately fail loud
            // here so a release build never silently runs against placeholder
            // credentials.
            fatalError(
                "Release builds require RUNANYWHERE_API_KEY and RUNANYWHERE_BASE_URL via xcconfig or Settings; " +
                "set in Settings.bundle or .xcconfig before shipping."
            )
            #endif
        }
    }

    private func looksLikePlaceholder(_ value: String) -> Bool {
        value.range(
            of: "YOUR_|<your|REPLACE_ME|PLACEHOLDER",
            options: [.regularExpression, .caseInsensitive]
        ) != nil
    }

    private func isUsableHTTPURL(_ value: String) -> Bool {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !looksLikePlaceholder(trimmed),
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              ["http", "https"].contains(scheme),
              let host = url.host,
              !host.isEmpty,
              host.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              !host.contains("<"),
              !host.contains(">") else {
            return false
        }
        return true
    }

    private func retryInitialization() async {
        await MainActor.run {
            initializationError = nil
        }
        await initializeSDK()
    }

    @MainActor
    private func refreshSDKCatalogs() async {
        logger.info("Refreshing SDK model registry...")

        await RunAnywhere.refreshModelRegistry()

        let listResult = await RunAnywhere.listModels()
        if listResult.success {
            let models = listResult.models.models
            let downloaded = models.filter(\.isDownloaded).count
            let available = models.filter(\.isAvailableForUse).count
            logger.info(
                "Model registry refreshed: registered=\(models.count), downloaded=\(downloaded), available=\(available)"
            )
        } else {
            let message = listResult.errorMessage.isEmpty ? "unknown error" : listResult.errorMessage
            logger.warning("Model registry refresh did not complete: \(message, privacy: .public)")
        }

        logger.info("SDK registry now exposes \(listResult.models.models.count) models")

        do {
            let adapters = try await RunAnywhere.lora.allRegistered()
            logger.info("LoRA registry exposes \(adapters.count) adapter entries")
        } catch {
            logger.warning("LoRA catalog list unavailable: \(error.localizedDescription, privacy: .public)")
        }

        logger.info("SDK catalog refresh complete")
    }

    // MARK: - Model Catalog Seeding
    //
    // Mirrors the Flutter example's `_registerModulesAndModels()`. Uses the
    // canonical `RunAnywhere.registerModel(...)` async public API, including
    // the multi-file and archive-with-structure overloads added in P5-T2.
    //
    // swiftlint:disable:next function_body_length
    private func registerModulesAndModels() async {
        logger.info("📦 Registering modules with their models...")

        // --- LLM models (LlamaCpp backend) ------------------------------------
        await registerLLM(
            id: "smollm2-360m-q8_0",
            name: "SmolLM2 360M Q8_0",
            url: "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 500_000_000
        )
        await registerLLM(
            id: "llama-2-7b-chat-q4_k_m",
            name: "Llama 2 7B Chat Q4_K_M",
            url: "https://huggingface.co/TheBloke/Llama-2-7B-Chat-GGUF/resolve/main/llama-2-7b-chat.Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 4_000_000_000
        )
        await registerLLM(
            id: "mistral-7b-instruct-q4_k_m",
            name: "Mistral 7B Instruct Q4_K_M",
            url: "https://huggingface.co/TheBloke/Mistral-7B-Instruct-v0.1-GGUF/resolve/main/mistral-7b-instruct-v0.1.Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 4_000_000_000
        )
        await registerLLM(
            id: "qwen2.5-0.5b-instruct-q6_k",
            name: "Qwen 2.5 0.5B Instruct Q6_K",
            url: "https://huggingface.co/Qwen/Qwen2.5-0.5B-Instruct-GGUF/resolve/main/qwen2.5-0.5b-instruct-q6_k.gguf",
            framework: .llamaCpp,
            memoryRequirement: 600_000_000
        )
        await registerLLM(
            id: "qwen2.5-1.5b-instruct-q4_k_m",
            name: "Qwen 2.5 1.5B Instruct Q4_K_M",
            url: "https://huggingface.co/Qwen/Qwen2.5-1.5B-Instruct-GGUF/resolve/main/qwen2.5-1.5b-instruct-q4_k_m.gguf",
            framework: .llamaCpp,
            memoryRequirement: 2_500_000_000,
            supportsLora: true
        )
        await registerLLM(
            id: "lfm2-350m-q4_k_m",
            name: "LiquidAI LFM2 350M Q4_K_M",
            url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 250_000_000
        )
        await registerLLM(
            id: "lfm2-350m-q8_0",
            name: "LiquidAI LFM2 350M Q8_0",
            url: "https://huggingface.co/LiquidAI/LFM2-350M-GGUF/resolve/main/LFM2-350M-Q8_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 400_000_000
        )
        await registerLLM(
            id: "lfm2-1.2b-tool-q4_k_m",
            name: "LiquidAI LFM2 1.2B Tool Q4_K_M",
            url: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 800_000_000
        )
        await registerLLM(
            id: "lfm2-1.2b-tool-q8_0",
            name: "LiquidAI LFM2 1.2B Tool Q8_0",
            url: "https://huggingface.co/LiquidAI/LFM2-1.2B-Tool-GGUF/resolve/main/LFM2-1.2B-Tool-Q8_0.gguf",
            framework: .llamaCpp,
            memoryRequirement: 1_400_000_000
        )
        await registerLLM(
            id: "qwen3-0.6b-q4_k_m",
            name: "Qwen3 0.6B Q4_K_M",
            url: "https://huggingface.co/unsloth/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 500_000_000,
            supportsThinking: true
        )
        await registerLLM(
            id: "qwen3-1.7b-q4_k_m",
            name: "Qwen3 1.7B Q4_K_M",
            url: "https://huggingface.co/unsloth/Qwen3-1.7B-GGUF/resolve/main/Qwen3-1.7B-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 1_200_000_000,
            supportsThinking: true
        )
        await registerLLM(
            id: "qwen3-4b-q4_k_m",
            name: "Qwen3 4B Q4_K_M",
            url: "https://huggingface.co/unsloth/Qwen3-4B-GGUF/resolve/main/Qwen3-4B-Q4_K_M.gguf",
            framework: .llamaCpp,
            memoryRequirement: 2_800_000_000,
            supportsThinking: true
        )
        logger.info("✅ LLM models registered")

        // --- VLM models (multi-modal, multi-file) -----------------------------
        await registerArchive(
            id: "smolvlm-500m-instruct-q8_0",
            name: "SmolVLM 500M Instruct",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-vlm-models-v1/smolvlm-500m-instruct-q8_0.tar.gz",
            framework: .llamaCpp,
            modality: .multimodal,
            archive: .tarGz,
            structure: .directoryBased,
            memoryRequirement: 600_000_000
        )
        await registerMultiFile(
            id: "qwen2-vl-2b-instruct-q4_k_m",
            name: "Qwen2-VL 2B Instruct",
            files: [
                ("https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/Qwen2-VL-2B-Instruct-Q4_K_M.gguf",
                 "Qwen2-VL-2B-Instruct-Q4_K_M.gguf"),
                ("https://huggingface.co/ggml-org/Qwen2-VL-2B-Instruct-GGUF/resolve/main/mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf",
                 "mmproj-Qwen2-VL-2B-Instruct-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 1_800_000_000
        )
        await registerMultiFile(
            id: "lfm2-vl-450m-q8_0",
            name: "LFM2-VL 450M",
            files: [
                ("https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/LFM2-VL-450M-Q8_0.gguf",
                 "LFM2-VL-450M-Q8_0.gguf"),
                ("https://huggingface.co/runanywhere/LFM2-VL-450M-GGUF/resolve/main/mmproj-LFM2-VL-450M-Q8_0.gguf",
                 "mmproj-LFM2-VL-450M-Q8_0.gguf")
            ],
            framework: .llamaCpp,
            modality: .multimodal,
            memoryRequirement: 600_000_000
        )
        logger.info("✅ VLM models registered")

        // --- STT models (Sherpa-ONNX) -----------------------------------------
        await registerArchive(
            id: "sherpa-onnx-whisper-tiny.en",
            name: "Sherpa Whisper Tiny (ONNX)",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz",
            framework: .sherpa,
            modality: .speechRecognition,
            archive: .tarGz,
            structure: .nestedDirectory,
            memoryRequirement: 75_000_000
        )

        // --- TTS models (Sherpa-ONNX Piper VITS) ------------------------------
        await registerArchive(
            id: "vits-piper-en_US-lessac-medium",
            name: "Piper TTS (US English - Medium)",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_US-lessac-medium.tar.gz",
            framework: .sherpa,
            modality: .speechSynthesis,
            archive: .tarGz,
            structure: .nestedDirectory,
            memoryRequirement: 65_000_000
        )
        await registerArchive(
            id: "vits-piper-en_GB-alba-medium",
            name: "Piper TTS (British English)",
            url: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/vits-piper-en_GB-alba-medium.tar.gz",
            framework: .sherpa,
            modality: .speechSynthesis,
            archive: .tarGz,
            structure: .nestedDirectory,
            memoryRequirement: 65_000_000
        )

        // --- VAD (Silero, ONNX) -----------------------------------------------
        await registerLLM(
            id: "silero-vad",
            name: "Silero VAD",
            url: "https://github.com/snakers4/silero-vad/raw/master/src/silero_vad/data/silero_vad.onnx",
            framework: .onnx,
            modality: .voiceActivityDetection,
            memoryRequirement: 5_000_000
        )
        logger.info("✅ Sherpa STT/TTS + Silero VAD models registered")

        // --- ONNX Embedding (RAG) ---------------------------------------------
        // MiniLM needs model.onnx + vocab.txt in the same folder for the C++
        // RAG pipeline to find its vocab next to the model.
        await registerMultiFile(
            id: "all-minilm-l6-v2",
            name: "All MiniLM L6 v2 (Embedding)",
            files: [
                ("https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/onnx/model.onnx", "model.onnx"),
                ("https://huggingface.co/Xenova/all-MiniLM-L6-v2/resolve/main/vocab.txt", "vocab.txt")
            ],
            framework: .onnx,
            modality: .embedding,
            memoryRequirement: 25_500_000
        )
        logger.info("✅ ONNX Embedding models registered")

        // MetalRT, WhisperKit, and Diffusion (CoreML) backends are deferred
        // scope for Swift v1. Their model catalog entries are intentionally
        // omitted. See `thoughts/shared/plans/curious-greeting-panda.md`.

        logger.info("🎉 All modules and models registered")
    }

    // MARK: - Catalog Seeding Helpers

    /// Register a single-file model via the canonical `RunAnywhere.registerModel`
    /// public API. Logs on failure but does not abort the whole seed pass.
    private func registerLLM(
        id: String,
        name: String,
        url: String,
        framework: InferenceFramework,
        modality: ModelCategory = .language,
        memoryRequirement: Int64,
        supportsThinking: Bool = false,
        supportsLora: Bool = false
    ) async {
        do {
            _ = try await RunAnywhere.registerModel(
                id: id,
                name: name,
                url: url,
                framework: framework,
                modality: modality,
                memoryRequirement: memoryRequirement,
                supportsThinking: supportsThinking,
                supportsLora: supportsLora
            )
        } catch {
            logger.warning(
                "Failed to register model \(id, privacy: .public): \(error.localizedDescription, privacy: .public)"
            )
        }
    }

    // swiftlint:disable function_parameter_count
    /// Register a tar.gz / zip archive model via the canonical public API.
    /// Delegates to `RunAnywhere.registerModel(archive:structure:...)` (P5-T2),
    /// which preserves the archive type + on-disk layout.
    private func registerArchive(
        id: String,
        name: String,
        url: String,
        framework: InferenceFramework,
        modality: ModelCategory,
        archive: ArchiveType,
        structure: ArchiveStructure,
        memoryRequirement: Int64
    ) async {
        do {
            _ = try await RunAnywhere.registerModel(
                archive: url,
                structure: structure,
                id: id,
                name: name,
                framework: framework,
                modality: modality,
                archiveType: archive,
                memoryRequirement: memoryRequirement
            )
        } catch {
            // swiftlint:disable:next line_length
            logger.warning("Failed to register archive model \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }

    /// Register a multi-file model (e.g., VLMs with a separate mmproj, MiniLM
    /// embedding with vocab.txt). Delegates to
    /// `RunAnywhere.registerModel(multiFile:...)` (P5-T2).
    private func registerMultiFile(
        id: String,
        name: String,
        files: [(url: String, filename: String)],
        framework: InferenceFramework,
        modality: ModelCategory,
        memoryRequirement: Int64
    ) async {
        let descriptors: [RAModelFileDescriptor] = files.compactMap { file in
            guard let fileURL = URL(string: file.url) else { return nil }
            var descriptor = RAModelFileDescriptor(url: fileURL, filename: file.filename, isRequired: true)
            descriptor.role = RunAnywhere.inferModelFileRole(filename: file.filename, modality: modality)
            return descriptor
        }
        guard descriptors.count == files.count else {
            logger.warning("Invalid multi-file URL list for model \(id, privacy: .public)")
            return
        }

        do {
            _ = try await RunAnywhere.registerModel(
                multiFile: descriptors,
                id: id,
                name: name,
                framework: framework,
                modality: modality,
                memoryRequirement: memoryRequirement
            )
        } catch {
            // swiftlint:disable:next line_length
            logger.warning("Failed to register multi-file model \(id, privacy: .public): \(error.localizedDescription, privacy: .public)")
        }
    }
    // swiftlint:enable function_parameter_count
}
// swiftlint:enable type_body_length

// MARK: - Loading Views

struct InitializationLoadingView: View {
    @State private var isAnimating = false
    @State private var progress: Double = 0.0

    var body: some View {
        VStack(spacing: 32) {
            Spacer()

            // RunAnywhere Logo
            Image("runanywhere_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 120, height: 120)
                .scaleEffect(isAnimating ? 1.05 : 1.0)
                .animation(.easeInOut(duration: 1.5).repeatForever(autoreverses: true), value: isAnimating)

            VStack(spacing: 12) {
                Text("Setting Up Your AI")
                    .font(.title2)
                    .fontWeight(.semibold)

                Text("Preparing your private AI assistant...")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }

            // Loading Bar
            VStack(spacing: 8) {
                ProgressView(value: progress, total: 1.0)
                    .progressViewStyle(.linear)
                    .tint(AppColors.primaryAccent)
                    .frame(width: 240)

                Text("Initializing SDK...")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }

            Spacer()
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
        .onAppear {
            isAnimating = true
            startProgressAnimation()
        }
    }

    private func startProgressAnimation() {
        Timer.scheduledTimer(withTimeInterval: 0.02, repeats: true) { _ in
            if progress < 1.0 {
                progress += 0.01
            } else {
                // Reset and start again
                progress = 0.0
            }
        }
    }
}

struct InitializationErrorView: View {
    let error: Error
    let retryAction: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 60))
                .foregroundColor(.orange)

            Text("Initialization Failed")
                .font(.title2)
                .fontWeight(.semibold)

            Text(error.localizedDescription)
                .font(.subheadline)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            Button("Retry") {
                retryAction()
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
            .font(.headline)
        }
        .padding(40)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        #if os(iOS)
        .background(Color(.systemBackground))
        #else
        .background(Color(NSColor.windowBackgroundColor))
        #endif
    }
}
