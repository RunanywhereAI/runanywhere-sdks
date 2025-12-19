import SwiftUI
import RunAnywhere
import AVFoundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAgentViewModel()
    @State private var showModelInfo = false
    @State private var showModelSelection = false
    @State private var showSTTModelSelection = false
    @State private var showLLMModelSelection = false
    @State private var showTTSModelSelection = false

    var body: some View {
        Group {
            #if os(macOS)
            // macOS: Custom layout without NavigationView
            VStack(spacing: 0) {
            // Custom toolbar for macOS
            HStack {
                // Model selection button
                Button(action: {
                    showModelSelection = true
                }) {
                    Label("Models", systemImage: "cube")
                }
                .buttonStyle(.bordered)

                Spacer()

                // Status indicator
                HStack(spacing: AppSpacing.small) {
                    Circle()
                        .fill(viewModel.statusColor.swiftUIColor)
                        .frame(width: 8, height: 8)
                    Text(viewModel.sessionState.displayName)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                }

                Spacer()

                // Model info toggle
                Button(action: {
                    withAnimation(.spring(response: 0.3)) {
                        showModelInfo.toggle()
                    }
                }) {
                    Label(showModelInfo ? "Hide Info" : "Show Info", systemImage: "info.circle")
                }
                .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(Color(NSColor.windowBackgroundColor))

            Divider()

            // Model info section
            if showModelInfo {
                VStack(spacing: 8) {
                    HStack(spacing: 15) {
                        ModelBadge(icon: "brain", label: "LLM", value: viewModel.currentLLMModel, color: AppColors.primaryBlue)
                        ModelBadge(icon: "waveform", label: "STT", value: viewModel.currentSTTModel, color: AppColors.statusGreen)
                        ModelBadge(icon: "speaker.wave.2", label: "TTS", value: viewModel.currentTTSModel, color: AppColors.primaryPurple)
                    }
                    .padding(.horizontal, 20)
                }
                .padding(.bottom, 15)
                .transition(.opacity.combined(with: .move(edge: .top)))
            }

            // Main conversation area
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 20) {
                        // User message
                        if !viewModel.currentTranscript.isEmpty {
                            ConversationBubble(
                                speaker: "You",
                                message: viewModel.currentTranscript,
                                isUser: true
                            )
                            .id("user")
                        }

                        // Assistant response
                        if !viewModel.assistantResponse.isEmpty {
                            ConversationBubble(
                                speaker: "Assistant",
                                message: viewModel.assistantResponse,
                                isUser: false
                            )
                            .id("assistant")
                        }

                        // Placeholder when empty
                        if viewModel.currentTranscript.isEmpty && viewModel.assistantResponse.isEmpty {
                            VStack(spacing: 12) {
                                Image(systemName: "mic.circle")
                                    .font(.system(size: 48))
                                    .foregroundColor(.secondary.opacity(0.3))
                                Text("Click the microphone to start")
                                    .font(.subheadline)
                                    .foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity)
                            .padding(.top, 100)
                        }
                    }
                    .padding(.horizontal, AdaptiveSizing.contentPadding)
                    .padding(.vertical, 20)
                    .adaptiveConversationWidth()
                }
                .onChange(of: viewModel.assistantResponse) { _ in
                    withAnimation {
                        proxy.scrollTo("assistant", anchor: .bottom)
                    }
                }
            }

            Spacer()

            // Control area
            VStack(spacing: 20) {
                // Error message (if any)
                if let error = viewModel.errorMessage {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(AppColors.statusRed)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // Main mic button
                HStack {
                    Spacer()

                    AdaptiveMicButton(
                        isActive: viewModel.isListening,
                        isPulsing: viewModel.isSpeechDetected,
                        isLoading: viewModel.sessionState == .connecting || (viewModel.isProcessing && !viewModel.isListening),
                        activeColor: viewModel.micButtonColor.swiftUIColor,
                        inactiveColor: viewModel.micButtonColor.swiftUIColor,
                        icon: viewModel.micButtonIcon
                    ) {
                        Task {
                            if viewModel.isActive {
                                await viewModel.stopConversation()
                            } else {
                                await viewModel.startConversation()
                            }
                        }
                    }

                    Spacer()
                }

                // Subtle instruction text
                Text(viewModel.instructionText)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)
            }
            .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            #else
        // iOS: Keep original layout
        ZStack {
            // Show setup view when not all models are loaded
            if !viewModel.allModelsLoaded {
                VoicePipelineSetupView(
                    sttModel: Binding(
                        get: { viewModel.sttModel },
                        set: { viewModel.sttModel = $0 }
                    ),
                    llmModel: Binding(
                        get: { viewModel.llmModel },
                        set: { viewModel.llmModel = $0 }
                    ),
                    ttsModel: Binding(
                        get: { viewModel.ttsModel },
                        set: { viewModel.ttsModel = $0 }
                    ),
                    sttLoadState: viewModel.sttModelState,
                    llmLoadState: viewModel.llmModelState,
                    ttsLoadState: viewModel.ttsModelState,
                    onSelectSTT: { showSTTModelSelection = true },
                    onSelectLLM: { showLLMModelSelection = true },
                    onSelectTTS: { showTTSModelSelection = true },
                    onStartVoice: {
                        // All models loaded, nothing to do here
                        // The view will automatically switch to main voice UI
                    }
                )
            } else {
                // Main voice assistant UI (only shown when all models are ready)
                VStack(spacing: 0) {
                    // Minimal header with subtle controls
                    HStack {
                        // Model selection button - subtle, top left
                        Button(action: {
                            showModelSelection = true
                        }) {
                            Image(systemName: "cube")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                                .padding(10)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(Circle())
                        }

                        Spacer()

                        // Status indicator - minimal
                        HStack(spacing: 6) {
                            Circle()
                                .fill(viewModel.statusColor.swiftUIColor)
                                .frame(width: 8, height: 8)
                            Text(viewModel.sessionState.displayName)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }

                        Spacer()

                        // Model info toggle - subtle, top right
                        Button(action: {
                            withAnimation(.spring(response: 0.3)) {
                                showModelInfo.toggle()
                            }
                        }) {
                            Image(systemName: showModelInfo ? "info.circle.fill" : "info.circle")
                                .font(.system(size: 18))
                                .foregroundColor(.secondary)
                                .padding(10)
                                .background(Color(.tertiarySystemBackground))
                                .clipShape(Circle())
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.top, 20)
                    .padding(.bottom, 10)

                    // Expandable model info (hidden by default)
                    if showModelInfo {
                        VStack(spacing: 8) {
                            HStack(spacing: 15) {
                                // Compact model badges
                                ModelBadge(icon: "brain", label: "LLM", value: viewModel.currentLLMModel, color: AppColors.primaryBlue)
                                ModelBadge(icon: "waveform", label: "STT", value: viewModel.currentSTTModel, color: AppColors.statusGreen)
                                ModelBadge(icon: "speaker.wave.2", label: "TTS", value: viewModel.currentTTSModel, color: AppColors.primaryPurple)
                            }
                            .padding(.horizontal, 20)
                        }
                        .padding(.bottom, 15)
                        .transition(.opacity.combined(with: .move(edge: .top)))
                    }

                    // Main conversation area
                    ScrollViewReader { proxy in
                        ScrollView {
                            VStack(alignment: .leading, spacing: 20) {
                                // User message
                                if !viewModel.currentTranscript.isEmpty {
                                    ConversationBubble(
                                        speaker: "You",
                                        message: viewModel.currentTranscript,
                                        isUser: true
                                    )
                                    .id("user")
                                }

                                // Assistant response - with increased height
                                if !viewModel.assistantResponse.isEmpty {
                                    ConversationBubble(
                                        speaker: "Assistant",
                                        message: viewModel.assistantResponse,
                                        isUser: false
                                    )
                                    .id("assistant")
                                }

                                // Placeholder when empty
                                if viewModel.currentTranscript.isEmpty && viewModel.assistantResponse.isEmpty {
                                    VStack(spacing: 12) {
                                        Image(systemName: "mic.circle")
                                            .font(.system(size: 48))
                                            .foregroundColor(.secondary.opacity(0.3))
                                        Text("Tap the microphone to start")
                                            .font(.subheadline)
                                            .foregroundColor(.secondary)
                                    }
                                    .frame(maxWidth: .infinity)
                                    .padding(.top, 100)
                                }
                            }
                            .padding(.horizontal, 20)
                            .padding(.vertical, 20)
                        }
                        .onChange(of: viewModel.assistantResponse) { _ in
                            withAnimation {
                                proxy.scrollTo("assistant", anchor: .bottom)
                            }
                        }
                    }

                    Spacer()

                    // Minimal control area
                    VStack(spacing: 20) {
                        // Error message (if any)
                        if let error = viewModel.errorMessage {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(AppColors.statusRed)
                                .multilineTextAlignment(.center)
                                .padding(.horizontal, 20)
                        }

                        // Audio level indicator (visible when recording/listening)
                        if viewModel.sessionState == .listening || viewModel.isListening {
                            VStack(spacing: 8) {
                                // Recording status badge
                                HStack(spacing: 6) {
                                    Circle()
                                        .fill(AppColors.statusRed)
                                        .frame(width: 8, height: 8)
                                    Text("RECORDING")
                                        .font(.caption2)
                                        .fontWeight(.bold)
                                        .foregroundColor(AppColors.statusRed)
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(AppColors.statusRed.opacity(0.1))
                                .cornerRadius(4)

                                // Audio level bars - using adaptive sizing
                                AdaptiveAudioLevelIndicator(level: viewModel.audioLevel)
                            }
                            .padding(.bottom, 8)
                            .animation(.easeInOut(duration: 0.2), value: viewModel.audioLevel)
                        }

                        // Main mic button
                        HStack {
                            Spacer()

                            AdaptiveMicButton(
                                isActive: viewModel.isListening,
                                isPulsing: viewModel.isSpeechDetected,
                                isLoading: viewModel.sessionState == .connecting || (viewModel.isProcessing && !viewModel.isListening),
                                activeColor: viewModel.micButtonColor.swiftUIColor,
                                inactiveColor: viewModel.micButtonColor.swiftUIColor,
                                icon: viewModel.micButtonIcon
                            ) {
                                Task {
                                    if viewModel.isActive {
                                        await viewModel.stopConversation()
                                    } else {
                                        await viewModel.startConversation()
                                    }
                                }
                            }

                            Spacer()
                        }

                        // Subtle instruction text
                        Text(viewModel.instructionText)
                            .font(.caption2)
                            .foregroundColor(.secondary.opacity(0.7))
                            .multilineTextAlignment(.center)
                    }
                    .padding(.bottom, 30)
                }
                .background(Color(.systemBackground))
            }
        }
            #endif
        }
        .sheet(isPresented: $showModelSelection) {
            // Use the same VoicePipelineSetupView UI for changing models
            NavigationView {
                VoicePipelineSetupView(
                    sttModel: Binding(
                        get: { viewModel.sttModel },
                        set: { viewModel.sttModel = $0 }
                    ),
                    llmModel: Binding(
                        get: { viewModel.llmModel },
                        set: { viewModel.llmModel = $0 }
                    ),
                    ttsModel: Binding(
                        get: { viewModel.ttsModel },
                        set: { viewModel.ttsModel = $0 }
                    ),
                    sttLoadState: viewModel.sttModelState,
                    llmLoadState: viewModel.llmModelState,
                    ttsLoadState: viewModel.ttsModelState,
                    onSelectSTT: {
                        showModelSelection = false
                        // Delay to allow sheet dismiss animation
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showSTTModelSelection = true
                        }
                    },
                    onSelectLLM: {
                        showModelSelection = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showLLMModelSelection = true
                        }
                    },
                    onSelectTTS: {
                        showModelSelection = false
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) {
                            showTTSModelSelection = true
                        }
                    },
                    onStartVoice: {
                        showModelSelection = false
                    }
                )
                .navigationTitle("Voice Models")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showModelSelection = false
                        }
                    }
                }
                #else
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Done") {
                            showModelSelection = false
                        }
                    }
                }
                #endif
            }
        }
        .sheet(isPresented: $showSTTModelSelection) {
            ModelSelectionSheet(context: .stt) { model in
                viewModel.setSTTModel(model)
            }
        }
        .sheet(isPresented: $showLLMModelSelection) {
            ModelSelectionSheet(context: .llm) { model in
                viewModel.setLLMModel(model)
            }
        }
        .sheet(isPresented: $showTTSModelSelection) {
            ModelSelectionSheet(context: .tts) { model in
                viewModel.setTTSModel(model)
            }
        }
        .onAppear {
            Task {
                if !viewModel.isInitialized {
                    await viewModel.initialize()
                } else {
                    // Already initialized, just refresh component states
                    // This handles the case where user loaded models in another tab
                    viewModel.refreshComponentStatesFromSDK()
                }
            }
        }
        .onDisappear {
            viewModel.cleanup()
        }
    }

}

// Conversation bubble component
struct ConversationBubble: View {
    let speaker: String
    let message: String
    let isUser: Bool

    private func fillColor(isUser: Bool) -> Color {
        if isUser {
            #if os(macOS)
            return Color(NSColor.controlBackgroundColor)
            #else
            return Color(.secondarySystemBackground)
            #endif
        } else {
            return AppColors.primaryAccent.opacity(0.08)
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(speaker)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.secondary)

            Text(message)
                .font(.body)
                .foregroundColor(.primary)
                .padding(12)
                .background(
                    RoundedRectangle(cornerRadius: 16)
                        .fill(fillColor(isUser: isUser))
                )
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

// Compact model badge component with adaptive sizing
struct ModelBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.system(size: AdaptiveSizing.badgeFontSize))
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: AdaptiveSizing.badgeFontSize - 1))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.system(size: AdaptiveSizing.badgeFontSize))
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, AdaptiveSizing.badgePaddingH)
        .padding(.vertical, AdaptiveSizing.badgePaddingV)
        .background(color.opacity(0.1))
        .cornerRadius(6)
    }
}

// Preview
struct VoiceAssistantView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceAssistantView()
    }
}
