import SwiftUI
import RunAnywhereSDK
import AVFoundation

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAssistantViewModel()
    @State private var showTranscriptionView = false

    var body: some View {
        VStack(spacing: 20) {
            // Title with experimental badge
            VStack(spacing: 8) {
                Text("Voice Assistant")
                    .font(.largeTitle)
                    .fontWeight(.bold)

                HStack(spacing: 4) {
                    Image(systemName: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundColor(.orange)
                    Text("EXPERIMENTAL FEATURE")
                        .font(.caption)
                        .fontWeight(.semibold)
                        .foregroundColor(.orange)
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .background(Color.orange.opacity(0.15))
                .cornerRadius(12)

                Text("🚧 In Development")
                    .font(.caption2)
                    .foregroundColor(.secondary)
                    .italic()
            }
            .padding(.top)

            // Model info badges
            HStack(spacing: 12) {
                // LLM Model Badge
                HStack(spacing: 6) {
                    Image(systemName: "brain")
                        .font(.caption)
                        .foregroundColor(.blue)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("LLM")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(viewModel.currentLLMModel.isEmpty ? "Loading..." : viewModel.currentLLMModel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                            .lineLimit(1)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.blue.opacity(0.1))
                .cornerRadius(8)

                // Whisper Model Badge
                HStack(spacing: 6) {
                    Image(systemName: "waveform")
                        .font(.caption)
                        .foregroundColor(.green)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("STT")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text(viewModel.whisperModel)
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.green.opacity(0.1))
                .cornerRadius(8)

                // TTS Badge
                HStack(spacing: 6) {
                    Image(systemName: "speaker.wave.2")
                        .font(.caption)
                        .foregroundColor(.purple)
                    VStack(alignment: .leading, spacing: 2) {
                        Text("TTS")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                        Text("System")
                            .font(.caption)
                            .fontWeight(.medium)
                            .foregroundColor(.primary)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.vertical, 6)
                .background(Color.purple.opacity(0.1))
                .cornerRadius(8)
            }
            .padding(.horizontal)

            // Status indicator
            HStack {
                Circle()
                    .fill(statusColor)
                    .frame(width: 12, height: 12)
                Text(statusText)
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .padding(.horizontal)

            // Transcript display
            VStack(alignment: .leading, spacing: 10) {
                Text("You:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                Text(viewModel.currentTranscript.isEmpty ? "Tap mic to speak..." : viewModel.currentTranscript)
                    .font(.body)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding()
                    .background(Color(.secondarySystemBackground))
                    .cornerRadius(10)
                    .frame(minHeight: 80)
            }
            .padding(.horizontal)

            // AI Response
            VStack(alignment: .leading, spacing: 10) {
                Text("Assistant:")
                    .font(.headline)
                    .foregroundColor(.secondary)
                ScrollView {
                    Text(viewModel.assistantResponse.isEmpty ? "Waiting..." : viewModel.assistantResponse)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color.blue.opacity(0.1))
                        .cornerRadius(10)
                }
                .frame(maxHeight: 200)
            }
            .padding(.horizontal)

            // Mode Switch Button
            Button(action: {
                showTranscriptionView = true
            }) {
                HStack {
                    Image(systemName: "text.quote")
                        .font(.system(size: 16))
                    Text("Transcription Only Mode")
                        .font(.subheadline)
                        .fontWeight(.medium)
                }
                .foregroundColor(.white)
                .padding(.horizontal, 20)
                .padding(.vertical, 10)
                .background(
                    LinearGradient(
                        gradient: Gradient(colors: [Color.blue, Color.purple]),
                        startPoint: .leading,
                        endPoint: .trailing
                    )
                )
                .cornerRadius(20)
            }
            .sheet(isPresented: $showTranscriptionView) {
                TranscriptionView()
            }

            Spacer()

            // Control buttons
            HStack(spacing: 30) {
                // Mic button - tap to start/stop
                Button(action: {
                    Task {
                        // If in any active state, stop the conversation
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
                        // Fixed size container to prevent layout shifts
                        Circle()
                            .fill(micButtonColor)
                            .frame(width: 80, height: 80)
                            .overlay(
                                // Animated border when speaking
                                Circle()
                                    .stroke(
                                        viewModel.isSpeechDetected ? Color.blue : Color.clear,
                                        lineWidth: viewModel.isSpeechDetected ? 3 : 0
                                    )
                                    .scaleEffect(viewModel.isSpeechDetected ? 1.15 : 1.0)
                                    .opacity(viewModel.isSpeechDetected ? 0.8 : 0)
                                    .animation(.easeInOut(duration: 0.3), value: viewModel.isSpeechDetected)
                            )
                            .overlay(
                                // Subtle pulsing glow effect
                                Circle()
                                    .stroke(
                                        LinearGradient(
                                            gradient: Gradient(colors: [Color.blue.opacity(0.6), Color.blue.opacity(0.2)]),
                                            startPoint: .top,
                                            endPoint: .bottom
                                        ),
                                        lineWidth: 2
                                    )
                                    .scaleEffect(viewModel.isSpeechDetected ? 1.25 : 1.0)
                                    .opacity(viewModel.isSpeechDetected ? 0.5 : 0)
                                    .animation(
                                        viewModel.isSpeechDetected ?
                                            .easeInOut(duration: 0.8).repeatForever(autoreverses: true) :
                                            .easeInOut(duration: 0.3),
                                        value: viewModel.isSpeechDetected
                                    )
                            )

                        if viewModel.sessionState == .connecting {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        } else if viewModel.isProcessing && !viewModel.isListening {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        } else {
                            Image(systemName: viewModel.sessionState == .speaking ? "stop.fill" :
                                            (viewModel.isListening ? "mic.fill" : "mic"))
                                .font(.system(size: 35))
                                .foregroundColor(.white)
                        }
                    }
                }
                .frame(width: 120, height: 120)  // Fixed frame to prevent layout shifts
                .disabled(false)  // Always enabled so user can stop at any time

                // Interrupt button - only shown when AI is responding
                if viewModel.sessionState == .speaking || viewModel.sessionState == .processing {
                    Button(action: {
                        Task {
                            await viewModel.interruptResponse()
                        }
                    }) {
                        ZStack {
                            Circle()
                                .fill(Color.orange)
                                .frame(width: 60, height: 60)
                            Image(systemName: "stop.fill")
                                .font(.system(size: 25))
                                .foregroundColor(.white)
                        }
                    }
                    .transition(.scale)
                }
            }
            .padding(.bottom, 30)

            // Error display
            if let error = viewModel.errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
                    .multilineTextAlignment(.center)
            }

            // Instructions
            VStack(spacing: 6) {
                Text(instructionText)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)

                Text("⚠️ This feature is under active development")
                    .font(.caption2)
                    .foregroundColor(.orange)
                    .italic()
            }
            .padding(.horizontal)
            .padding(.bottom)
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
        case .connecting: return .yellow
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .red  // Red when speaking so user can dismiss
        default: return .blue
        }
    }

    private var statusColor: Color {
        switch viewModel.sessionState {
        case .disconnected: return .gray
        case .connecting: return .yellow
        case .connected: return .green
        case .listening: return .red
        case .processing: return .orange
        case .speaking: return .blue
        case .error: return .red
        }
    }

    private var statusText: String {
        switch viewModel.sessionState {
        case .disconnected: return "Disconnected"
        case .connecting: return "Connecting..."
        case .connected: return "Ready"
        case .listening: return "Listening..."
        case .processing: return "Thinking..."
        case .speaking: return "Speaking..."
        case .error: return "Error"
        }
    }

    private var instructionText: String {
        switch viewModel.sessionState {
        case .disconnected, .connected:
            return "Tap the microphone to start a conversation"
        case .connecting:
            return "Connecting to voice service..."
        case .listening:
            return "Speak now... Tap mic to stop"
        case .processing:
            return "Processing your request..."
        case .speaking:
            return "Assistant is responding... Tap stop to interrupt"
        case .error:
            return "An error occurred. Tap mic to try again"
        }
    }
}

// Preview
struct VoiceAssistantView_Previews: PreviewProvider {
    static var previews: some View {
        VoiceAssistantView()
    }
}
