import SwiftUI
import RunAnywhere
import AVFoundation
#if canImport(UIKit)
import UIKit
#else
import AppKit
#endif

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAssistantViewModel()
    @State private var showModelInfo = false
    @State private var showModelSelection = false

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
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
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
                        ModelBadge(icon: "brain", label: "LLM", value: viewModel.currentLLMModel.isEmpty ? "Loading..." : viewModel.currentLLMModel, color: .blue)
                        ModelBadge(icon: "waveform", label: "STT", value: viewModel.whisperModel, color: .green)
                        ModelBadge(icon: "speaker.wave.2", label: "TTS", value: "System", color: .purple)
                    }
                    .padding(.horizontal, 20)

                    Text("Experimental Feature")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
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
                    .padding(.horizontal, 30)
                    .padding(.vertical, 20)
                    .frame(maxWidth: 800, alignment: .leading)
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
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // Main mic button
                HStack {
                    Spacer()

                    Button(action: {
                        Task {
                            if viewModel.sessionState == .listening ||
                               viewModel.sessionState == .speaking ||
                               viewModel.sessionState == .processing ||
                               viewModel.sessionState == .connecting {
                                await viewModel.stopConversation()
                            } else {
                                await viewModel.startConversation()
                            }
                        }
                    }) {
                        ZStack {
                            // Background circle
                            Circle()
                                .fill(micButtonColor)
                                .frame(width: 72, height: 72)

                            // Pulsing effect when active
                            if viewModel.isSpeechDetected {
                                Circle()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                    .scaleEffect(viewModel.isSpeechDetected ? 1.3 : 1.0)
                                    .opacity(viewModel.isSpeechDetected ? 0 : 0.8)
                                    .animation(
                                        .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                        value: viewModel.isSpeechDetected
                                    )
                            }

                            // Icon
                            if viewModel.sessionState == .connecting ||
                               (viewModel.isProcessing && !viewModel.isListening) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            } else {
                                Image(systemName: micButtonIcon)
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }
                    }
                    .buttonStyle(.plain)

                    Spacer()
                }

                // Subtle instruction text
                Text(instructionText)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text("⚠️ This feature is under active development")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 30)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(NSColor.windowBackgroundColor))
            #else
        // iOS: Keep original layout
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
                        .fill(statusColor)
                        .frame(width: 8, height: 8)
                    Text(statusText)
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
                        ModelBadge(icon: "brain", label: "LLM", value: viewModel.currentLLMModel.isEmpty ? "Loading..." : viewModel.currentLLMModel, color: .blue)
                        ModelBadge(icon: "waveform", label: "STT", value: viewModel.whisperModel, color: .green)
                        ModelBadge(icon: "speaker.wave.2", label: "TTS", value: "System", color: .purple)
                    }
                    .padding(.horizontal, 20)

                    Text("Experimental Feature")
                        .font(.caption2)
                        .foregroundColor(.orange)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 4)
                        .background(Color.orange.opacity(0.1))
                        .cornerRadius(8)
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
                        .foregroundColor(.red)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, 20)
                }

                // Main mic button
                HStack {
                    Spacer()

                    Button(action: {
                        Task {
                            if viewModel.sessionState == .listening ||
                               viewModel.sessionState == .speaking ||
                               viewModel.sessionState == .processing ||
                               viewModel.sessionState == .connecting {
                                await viewModel.stopConversation()
                            } else {
                                await viewModel.startConversation()
                            }
                        }
                    }) {
                        ZStack {
                            // Background circle
                            Circle()
                                .fill(micButtonColor)
                                .frame(width: 72, height: 72)

                            // Pulsing effect when active
                            if viewModel.isSpeechDetected {
                                Circle()
                                    .stroke(Color.white.opacity(0.4), lineWidth: 2)
                                    .scaleEffect(viewModel.isSpeechDetected ? 1.3 : 1.0)
                                    .opacity(viewModel.isSpeechDetected ? 0 : 0.8)
                                    .animation(
                                        .easeOut(duration: 1.0).repeatForever(autoreverses: false),
                                        value: viewModel.isSpeechDetected
                                    )
                            }

                            // Icon
                            if viewModel.sessionState == .connecting ||
                               (viewModel.isProcessing && !viewModel.isListening) {
                                ProgressView()
                                    .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                    .scaleEffect(1.2)
                            } else {
                                Image(systemName: micButtonIcon)
                                    .font(.system(size: 28))
                                    .foregroundColor(.white)
                            }
                        }
                    }

                    Spacer()
                }

                // Subtle instruction text
                Text(instructionText)
                    .font(.caption2)
                    .foregroundColor(.secondary.opacity(0.7))
                    .multilineTextAlignment(.center)

                Text("⚠️ This feature is under active development")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()
                    .padding(.horizontal, 40)
            }
            .padding(.bottom, 30)
        }
        .background(Color(.systemBackground))
            #endif
        }
        .sheet(isPresented: $showModelSelection) {
            ModelSelectionSheet(context: .voice) { model in
                // Model selected - the voice assistant will use this
                // For now, just close the sheet. Voice pipeline has its own model management.
            }
        }
        .onAppear {
            Task {
                await viewModel.initialize()
            }
        }
    }

    // Helper computed properties
    private var micButtonColor: Color {
        switch viewModel.sessionState {
        case .connecting: return .orange
        case .listening: return .red
        case .processing: return .blue
        case .speaking: return .green
        default: return .blue
        }
    }

    private var micButtonIcon: String {
        switch viewModel.sessionState {
        case .listening: return "mic.fill"
        case .speaking: return "speaker.wave.2.fill"
        case .processing: return "waveform"
        default: return "mic"
        }
    }

    private var statusColor: Color {
        switch viewModel.sessionState {
        case .disconnected: return .gray
        case .connecting: return .orange
        case .connected: return .green
        case .listening: return .red
        case .processing: return .blue
        case .speaking: return .green
        case .error: return .red
        }
    }

    private var statusText: String {
        switch viewModel.sessionState {
        case .disconnected: return "Ready"
        case .connecting: return "Connecting"
        case .connected: return "Ready"
        case .listening: return "Listening"
        case .processing: return "Thinking"
        case .speaking: return "Speaking"
        case .error: return "Error"
        }
    }

    private var instructionText: String {
        switch viewModel.sessionState {
        case .listening:
            return "Listening... Tap to stop"
        case .processing:
            return "Processing..."
        case .speaking:
            return "Speaking..."
        case .connecting:
            return "Connecting..."
        default:
            return "Tap to speak"
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
            return Color.blue.opacity(0.08)
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

// Compact model badge component
struct ModelBadge: View {
    let icon: String
    let label: String
    let value: String
    let color: Color

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: icon)
                .font(.caption2)
                .foregroundColor(color)
            VStack(alignment: .leading, spacing: 0) {
                Text(label)
                    .font(.system(size: 9))
                    .foregroundColor(.secondary)
                Text(value)
                    .font(.caption2)
                    .fontWeight(.medium)
                    .lineLimit(1)
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
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
