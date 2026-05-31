//
//  LocalAIPlaygroundApp.swift
//  LocalAIPlayground
//
//  Created by Shubham Malhotra on 1/19/26.
//
//  =============================================================================
//  RUNANYWHERE SDK INTEGRATION - APP ENTRY POINT
//  =============================================================================
//
//  This file demonstrates how to properly initialize the RunAnywhere SDK at
//  application launch. The SDK provides on-device AI capabilities including:
//
//  - LLM (Large Language Model) text generation via LlamaCPP backend
//  - STT (Speech-to-Text) transcription via ONNX/Whisper backend
//  - TTS (Text-to-Speech) synthesis via ONNX/Piper backend
//  - VAD (Voice Activity Detection) for voice pipelines
//
//  KEY CONCEPTS:
//  1. Initialize the SDK exactly ONCE at app launch
//  2. Register the backends you need (LlamaCPP for LLM, ONNX for STT/TTS)
//  3. Register models AFTER backends are registered
//  4. Handle initialization errors gracefully
//
//  PRIVACY BENEFIT:
//  All AI processing happens entirely on-device. No data is sent to external
//  servers, ensuring complete user privacy and offline functionality.
//
//  =============================================================================

import SwiftUI

// -----------------------------------------------------------------------------
// MARK: - RunAnywhere SDK Imports
// -----------------------------------------------------------------------------
// Import the core SDK and backend modules. Each module serves a specific purpose:
//
// - RunAnywhere: Core SDK with unified API for all AI capabilities
// - LlamaCPPRuntime: Backend for on-device LLM text generation
// - ONNXRuntime: Backend for STT (Whisper), TTS (Piper), and VAD
// -----------------------------------------------------------------------------
import RunAnywhere
import LlamaCPPRuntime
import ONNXRuntime

// -----------------------------------------------------------------------------
// MARK: - App Entry Point
// -----------------------------------------------------------------------------
/// The main entry point for the LocalAIPlayground app.
///
/// This struct is marked with `@main` to indicate it's the app's entry point.
/// SDK initialization happens asynchronously after the view appears.
// -----------------------------------------------------------------------------
@main
struct LocalAIPlaygroundApp: App {
    
    // -------------------------------------------------------------------------
    // MARK: - State Properties
    // -------------------------------------------------------------------------
    
    /// Shared model service for managing AI models
    @StateObject private var modelService = ModelService()
    
    /// Tracks whether the SDK has been initialized
    @State private var isSDKInitialized = false
    
    // -------------------------------------------------------------------------
    // MARK: - App Body
    // -------------------------------------------------------------------------
    
    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    // Main app content
                    ContentView()
                        .environmentObject(modelService)
                } else {
                    // Loading view while SDK initializes
                    SDKLoadingView()
                }
            }
            .task {
                // Initialize SDK asynchronously
                await initializeSDK()
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - SDK Initialization
    // -------------------------------------------------------------------------
    /// Initializes the RunAnywhere SDK and registers required backends.
    ///
    /// This method performs the initialization sequence:
    /// 1. Initialize the core SDK
    /// 2. Register backends (LlamaCPP, ONNX)
    /// 3. Register default models
    ///
    /// - Important: This must be called before using any SDK features.
    // -------------------------------------------------------------------------
    @MainActor
    private func initializeSDK() async {
        do {
            // -----------------------------------------------------------------
            // Step 1: Initialize the Core SDK
            // -----------------------------------------------------------------
            // The initialize() method sets up internal state, caching systems,
            // and prepares the SDK for use.
            //
            // Environments:
            // - .development: Verbose logging, debug assertions enabled
            // - .production: Minimal logging, optimized for release
            // -----------------------------------------------------------------
            try RunAnywhere.initialize(environment: .development)
            
            // -----------------------------------------------------------------
            // Step 2: Register the LlamaCPP Backend
            // -----------------------------------------------------------------
            // LlamaCPP is the backend that powers on-device LLM inference.
            // It supports various quantized models like SmolLM2, LFM2, etc.
            //
            // IMPORTANT: Register backends BEFORE registering models
            // -----------------------------------------------------------------
            LlamaCPP.register()
            
            // -----------------------------------------------------------------
            // Step 3: Register the ONNX Backend
            // -----------------------------------------------------------------
            // ONNX powers speech-related features using Sherpa-ONNX:
            // - STT (Speech-to-Text): Whisper models for transcription
            // - TTS (Text-to-Speech): Piper models for voice synthesis
            // - VAD (Voice Activity Detection): For voice pipelines
            // -----------------------------------------------------------------
            ONNX.register()
            
            // -----------------------------------------------------------------
            // Step 4: Register Default Models
            // -----------------------------------------------------------------
            // Models must be registered with URLs and metadata before they
            // can be downloaded or loaded. This is done via ModelService.
            // -----------------------------------------------------------------
            ModelService.registerDefaultModels()
            
            print("✅ RunAnywhere SDK initialized successfully")
            print("   Version: \(RunAnywhere.version)")
            
            // Mark initialization as complete
            isSDKInitialized = true
            
            // Refresh model service state
            await modelService.refreshLoadedStates()
            
        } catch {
            print("❌ Failed to initialize RunAnywhere SDK: \(error)")
            // Still show UI even if initialization fails
            isSDKInitialized = true
        }
    }
}

// -----------------------------------------------------------------------------
// MARK: - SDK Loading View
// -----------------------------------------------------------------------------
/// A view displayed while the SDK is initializing.
// -----------------------------------------------------------------------------
struct SDKLoadingView: View {
    var body: some View {
        VStack(spacing: 20) {
            ProgressView()
                .scaleEffect(1.5)
            
            Text("Initializing AI...")
                .font(.headline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(UIColor.systemBackground))
    }
}

// -----------------------------------------------------------------------------
// MARK: - Preview
// -----------------------------------------------------------------------------
#Preview {
    SDKLoadingView()
}
