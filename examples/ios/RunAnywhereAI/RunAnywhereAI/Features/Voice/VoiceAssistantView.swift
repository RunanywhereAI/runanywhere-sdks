import SwiftUI
import RunAnywhereSDK
import AVFoundation

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAssistantViewModel()

    var body: some View {
        VStack(spacing: 20) {
            Text("Voice Assistant")
                .font(.largeTitle)
                .fontWeight(.bold)
                .padding(.top)

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

            Spacer()

            // Control buttons
            HStack(spacing: 30) {
                // Mic button - tap to start/stop
                Button(action: {
                    Task {
                        if viewModel.isListening {
                            await viewModel.stopConversation()
                        } else {
                            await viewModel.startConversation()
                        }
                    }
                }) {
                    ZStack {
                        Circle()
                            .fill(viewModel.isListening ? Color.red : Color.blue)
                            .frame(width: 80, height: 80)

                        if viewModel.isProcessing && !viewModel.isListening {
                            ProgressView()
                                .progressViewStyle(CircularProgressViewStyle(tint: .white))
                                .scaleEffect(1.5)
                        } else {
                            Image(systemName: viewModel.isListening ? "mic.fill" : "mic")
                                .font(.system(size: 35))
                                .foregroundColor(.white)
                        }
                    }
                }
                .disabled(viewModel.isProcessing && !viewModel.isListening)
                .scaleEffect(viewModel.isListening ? 1.2 : 1.0)
                .animation(.easeInOut(duration: 0.2), value: viewModel.isListening)

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
            Text(instructionText)
                .font(.caption)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
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
