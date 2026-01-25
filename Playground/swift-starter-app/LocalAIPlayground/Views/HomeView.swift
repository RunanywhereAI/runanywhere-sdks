//
//  HomeView.swift
//  LocalAIPlayground
//
//  =============================================================================
//  HOME VIEW - APP LANDING PAGE
//  =============================================================================
//
//  The main landing page of the app that showcases all available AI features
//  and provides quick access to each capability.
//
//  FEATURES DISPLAYED:
//  - Chat (LLM) - On-device text generation
//  - Speech to Text - Whisper-based transcription
//  - Text to Speech - Piper voice synthesis
//  - Voice Pipeline - Full voice agent demo
//
//  =============================================================================

import SwiftUI

// =============================================================================
// MARK: - Home View
// =============================================================================
/// The main landing view displaying feature cards and model status.
// =============================================================================
struct HomeView: View {
    @EnvironmentObject var modelService: ModelService
    @Environment(\.colorScheme) var colorScheme
    
    /// Callback when a feature is selected
    let onFeatureSelected: (Feature) -> Void
    
    /// Available features in the app
    enum Feature: CaseIterable {
        case chat
        case speechToText
        case textToSpeech
        case voicePipeline
        
        var title: String {
            switch self {
            case .chat: return "Chat"
            case .speechToText: return "Speech to Text"
            case .textToSpeech: return "Text to Speech"
            case .voicePipeline: return "Voice Pipeline"
            }
        }
        
        var description: String {
            switch self {
            case .chat: 
                return "Chat with an on-device LLM. Streaming responses, complete privacy."
            case .speechToText: 
                return "Transcribe speech using Whisper. Works entirely offline."
            case .textToSpeech: 
                return "Natural voice synthesis with Piper neural TTS."
            case .voicePipeline: 
                return "Full voice agent: Speak → Transcribe → Generate → Speak"
            }
        }
        
        var icon: String {
            switch self {
            case .chat: return "bubble.left.and.bubble.right.fill"
            case .speechToText: return "waveform"
            case .textToSpeech: return "speaker.wave.2.fill"
            case .voicePipeline: return "person.wave.2.fill"
            }
        }
        
        var gradientColors: [Color] {
            switch self {
            case .chat: return [.aiPrimary, .aiPrimary.opacity(0.7)]
            case .speechToText: return [.aiSecondary, .aiSecondary.opacity(0.7)]
            case .textToSpeech: return [.aiAccent, .aiAccent.opacity(0.7)]
            case .voicePipeline: return [.purple, .purple.opacity(0.7)]
            }
        }
    }
    
    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: AISpacing.xl) {
                    // Hero section
                    heroSection
                    
                    // Model status
                    modelStatusSection
                    
                    // Feature cards
                    featureCardsSection
                    
                    // Footer
                    footerSection
                }
                .padding()
            }
            .background(backgroundGradient)
            .navigationTitle("LocalAI Playground")
            .navigationBarTitleDisplayMode(.large)
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Hero Section
    // -------------------------------------------------------------------------
    
    private var heroSection: some View {
        VStack(spacing: AISpacing.md) {
            // App icon
            ZStack {
                RoundedRectangle(cornerRadius: 24)
                    .fill(
                        LinearGradient(
                            colors: [.aiPrimary, .aiPrimary.opacity(0.7)],
                            startPoint: .topLeading,
                            endPoint: .bottomTrailing
                        )
                    )
                    .frame(width: 80, height: 80)
                    .shadow(color: .aiPrimary.opacity(0.4), radius: 16, y: 8)
                
                Image(systemName: "cpu")
                    .font(.system(size: 36, weight: .semibold))
                    .foregroundStyle(.white)
            }
            
            // Title
            Text("On-Device AI")
                .font(.aiDisplayLarge)
                .foregroundStyle(.primary)
            
            // Subtitle
            Text("Privacy-first AI capabilities powered by RunAnywhere SDK. All processing happens locally on your device.")
                .font(.aiBody)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            
            // Privacy badges
            HStack(spacing: AISpacing.md) {
                PrivacyBadge(icon: "lock.shield.fill", text: "100% Private")
                PrivacyBadge(icon: "wifi.slash", text: "Works Offline")
                PrivacyBadge(icon: "bolt.fill", text: "Low Latency")
            }
        }
        .padding(.vertical, AISpacing.lg)
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Model Status Section
    // -------------------------------------------------------------------------
    
    private var modelStatusSection: some View {
        VStack(alignment: .leading, spacing: AISpacing.md) {
            HStack {
                Text("Model Status")
                    .font(.aiHeading)
                
                Spacer()
                
                if modelService.isVoiceAgentReady {
                    AIStatusBadge(status: .ready, text: "All Ready")
                }
            }
            
            VStack(spacing: AISpacing.sm) {
                ModelStatusRow(
                    name: "LLM",
                    model: "LFM2 350M",
                    isLoaded: modelService.isLLMLoaded,
                    isLoading: modelService.isLLMLoading,
                    isDownloading: modelService.isLLMDownloading,
                    downloadProgress: modelService.llmDownloadProgress
                )
                
                ModelStatusRow(
                    name: "STT",
                    model: "Whisper Tiny",
                    isLoaded: modelService.isSTTLoaded,
                    isLoading: modelService.isSTTLoading,
                    isDownloading: modelService.isSTTDownloading,
                    downloadProgress: modelService.sttDownloadProgress
                )
                
                ModelStatusRow(
                    name: "TTS",
                    model: "Piper Lessac",
                    isLoaded: modelService.isTTSLoaded,
                    isLoading: modelService.isTTSLoading,
                    isDownloading: modelService.isTTSDownloading,
                    downloadProgress: modelService.ttsDownloadProgress
                )
            }
            .padding(AISpacing.md)
            .aiCardStyle()
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Feature Cards Section
    // -------------------------------------------------------------------------
    
    private var featureCardsSection: some View {
        VStack(alignment: .leading, spacing: AISpacing.md) {
            Text("Features")
                .font(.aiHeading)
            
            ForEach(Feature.allCases, id: \.title) { feature in
                AIFeatureCard(
                    icon: feature.icon,
                    title: feature.title,
                    description: feature.description,
                    gradientColors: feature.gradientColors
                ) {
                    onFeatureSelected(feature)
                }
            }
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Footer Section
    // -------------------------------------------------------------------------
    
    private var footerSection: some View {
        VStack(spacing: AISpacing.sm) {
            Divider()
            
            Text("Powered by RunAnywhere SDK")
                .font(.aiCaption)
                .foregroundStyle(.tertiary)
            
            HStack(spacing: AISpacing.xs) {
                Text("v0.16.0")
                    .font(.aiCaption)
                    .foregroundStyle(.tertiary)
                
                Text("•")
                    .foregroundStyle(.tertiary)
                
                Link("Documentation", destination: URL(string: "https://docs.runanywhere.ai")!)
                    .font(.aiCaption)
            }
        }
        .padding(.top, AISpacing.lg)
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Background
    // -------------------------------------------------------------------------
    
    private var backgroundGradient: some View {
        Group {
            if colorScheme == .dark {
                Color.aiGradientBackgroundDark
                    .ignoresSafeArea()
            } else {
                Color.aiGradientBackground
                    .ignoresSafeArea()
            }
        }
    }
}

// =============================================================================
// MARK: - Privacy Badge
// =============================================================================
/// A small badge displaying a privacy/feature benefit.
// =============================================================================
struct PrivacyBadge: View {
    let icon: String
    let text: String
    
    var body: some View {
        HStack(spacing: AISpacing.xs) {
            Image(systemName: icon)
                .font(.system(size: 12))
                .foregroundStyle(Color.aiPrimary)
            
            Text(text)
                .font(.aiCaption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, AISpacing.sm)
        .padding(.vertical, AISpacing.xs)
        .background(
            Capsule()
                .fill(Color.aiPrimary.opacity(0.1))
        )
    }
}

// =============================================================================
// MARK: - Model Status Row
// =============================================================================
/// A row displaying the status of a single model.
// =============================================================================
struct ModelStatusRow: View {
    let name: String
    let model: String
    let isLoaded: Bool
    let isLoading: Bool
    let isDownloading: Bool
    let downloadProgress: Double
    
    var body: some View {
        HStack(spacing: AISpacing.md) {
            // Status indicator
            Circle()
                .fill(statusColor)
                .frame(width: 10, height: 10)
            
            // Name
            Text(name)
                .font(.aiLabel)
                .frame(width: 40, alignment: .leading)
            
            // Model name
            Text(model)
                .font(.aiBodySmall)
                .foregroundStyle(.secondary)
            
            Spacer()
            
            // Status
            Group {
                if isDownloading {
                    Text("\(Int(downloadProgress * 100))%")
                        .font(.aiMono)
                } else if isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                } else {
                    Text(statusText)
                        .font(.aiCaption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }
    
    private var statusColor: Color {
        if isLoaded {
            return .aiSuccess
        } else if isLoading || isDownloading {
            return .aiWarning
        } else {
            return .secondary
        }
    }
    
    private var statusText: String {
        if isLoaded {
            return "Ready"
        } else {
            return "Not loaded"
        }
    }
}

// =============================================================================
// MARK: - Preview
// =============================================================================
#Preview {
    HomeView { feature in
        print("Selected: \(feature.title)")
    }
    .environmentObject(ModelService())
}
