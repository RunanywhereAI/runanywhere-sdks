//
//  ContentView.swift
//  LocalAIPlayground
//
//  Created by Shubham Malhotra on 1/19/26.
//
//  =============================================================================
//  CONTENT VIEW - MAIN APP NAVIGATION
//  =============================================================================
//
//  This is the root view of the app that manages navigation to all features.
//  It uses a sheet-based navigation pattern where:
//
//  1. HomeView displays feature cards
//  2. Tapping a card presents the corresponding feature view as a sheet
//
//  This pattern keeps the home view as the anchor while allowing deep dives
//  into each AI capability.
//
//  =============================================================================

import SwiftUI

// =============================================================================
// MARK: - Content View
// =============================================================================
/// The main content view managing navigation between features.
// =============================================================================
struct ContentView: View {
    // -------------------------------------------------------------------------
    // MARK: - Environment & State
    // -------------------------------------------------------------------------
    
    /// Model service passed from App
    @EnvironmentObject var modelService: ModelService
    
    /// Currently selected feature (drives sheet presentation)
    @State private var selectedFeature: HomeView.Feature?
    
    // -------------------------------------------------------------------------
    // MARK: - Body
    // -------------------------------------------------------------------------
    
    var body: some View {
        // Home view with feature cards
        HomeView { feature in
            selectedFeature = feature
        }
        .environmentObject(modelService)
        // Present feature views as full-screen sheets
        .fullScreenCover(item: $selectedFeature) { feature in
            featureView(for: feature)
                .environmentObject(modelService)
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Feature Views
    // -------------------------------------------------------------------------
    
    /// Returns the appropriate view for a given feature.
    ///
    /// Each feature demonstrates a different RunAnywhere SDK capability:
    /// - Chat: LLM text generation with streaming
    /// - Speech to Text: Whisper-based transcription
    /// - Text to Speech: Piper voice synthesis
    /// - Voice Pipeline: Combined VAD + STT + LLM + TTS
    // -------------------------------------------------------------------------
    @ViewBuilder
    private func featureView(for feature: HomeView.Feature) -> some View {
        switch feature {
        case .chat:
            // -----------------------------------------------------------------
            // Chat View
            // -----------------------------------------------------------------
            // Demonstrates on-device LLM text generation.
            // Features streaming token generation for real-time responses.
            //
            // SDK Methods:
            // - RunAnywhere.generateStream()
            // - LLMGenerationOptions for temperature, max tokens, etc.
            // -----------------------------------------------------------------
            ChatView()
            
        case .speechToText:
            // -----------------------------------------------------------------
            // Speech to Text View
            // -----------------------------------------------------------------
            // Demonstrates on-device speech recognition using Whisper.
            // Records audio and transcribes it locally.
            //
            // SDK Methods:
            // - RunAnywhere.loadSTTModel()
            // - RunAnywhere.transcribe()
            // -----------------------------------------------------------------
            SpeechToTextView()
            
        case .textToSpeech:
            // -----------------------------------------------------------------
            // Text to Speech View
            // -----------------------------------------------------------------
            // Demonstrates on-device voice synthesis using Piper.
            // Converts text to natural-sounding speech.
            //
            // SDK Methods:
            // - RunAnywhere.loadTTSVoice()
            // - RunAnywhere.synthesize()
            // - TTSOptions for rate, pitch, volume
            // -----------------------------------------------------------------
            TextToSpeechView()
            
        case .voicePipeline:
            // -----------------------------------------------------------------
            // Voice Pipeline View
            // -----------------------------------------------------------------
            // Demonstrates the complete voice agent pipeline:
            // 1. User speaks → Audio recorded
            // 2. Whisper transcribes → Text
            // 3. LLM generates response → Text
            // 4. Piper synthesizes → Audio
            // 5. Audio played back
            // -----------------------------------------------------------------
            VoicePipelineView()
        }
    }
}

// =============================================================================
// MARK: - Feature Extension for Identifiable
// =============================================================================
/// Makes Feature identifiable for sheet presentation.
// =============================================================================
extension HomeView.Feature: Identifiable {
    var id: String { title }
}

// =============================================================================
// MARK: - Preview
// =============================================================================
#Preview {
    ContentView()
        .environmentObject(ModelService())
}
