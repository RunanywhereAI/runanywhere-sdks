import SwiftUI
import RunAnywhereSDK
import AVFoundation

struct VoiceAssistantView: View {
    @StateObject private var viewModel = VoiceAssistantViewModel()
    @State private var isListening = false
    @State private var transcribedText = ""
    @State private var responseText = ""
    @State private var errorMessage: String?
    @State private var isProcessing = false

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

            // Transcribed text display
            VStack(alignment: .leading, spacing: 8) {
                Text("You said:")
                    .font(.headline)
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(transcribedText.isEmpty ? "Tap the microphone to speak..." : transcribedText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
                .frame(maxHeight: 150)
            }
            .padding(.horizontal)

            // Response text display
            VStack(alignment: .leading, spacing: 8) {
                Text("Assistant response:")
                    .font(.headline)
                    .foregroundColor(.secondary)

                ScrollView {
                    Text(responseText.isEmpty ? "Waiting for your input..." : responseText)
                        .font(.body)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding()
                        .background(Color(.secondarySystemBackground))
                        .cornerRadius(10)
                }
                .frame(maxHeight: 150)
            }
            .padding(.horizontal)

            // Error message
            if let error = errorMessage {
                Text(error)
                    .font(.caption)
                    .foregroundColor(.red)
                    .padding(.horizontal)
            }

            Spacer()

            // Microphone button
            Button(action: {
                Task {
                    await handleMicrophoneTap()
                }
            }) {
                ZStack {
                    Circle()
                        .fill(isListening ? Color.red : Color.blue)
                        .frame(width: 80, height: 80)

                    if isProcessing {
                        ProgressView()
                            .progressViewStyle(CircularProgressViewStyle(tint: .white))
                            .scaleEffect(1.5)
                    } else {
                        Image(systemName: isListening ? "mic.fill" : "mic")
                            .font(.system(size: 35))
                            .foregroundColor(.white)
                    }
                }
            }
            .disabled(isProcessing)
            .scaleEffect(isListening ? 1.2 : 1.0)
            .animation(.easeInOut(duration: 0.2), value: isListening)

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

    private var statusColor: Color {
        if isProcessing {
            return .orange
        } else if isListening {
            return .red
        } else {
            return .green
        }
    }

    private var statusText: String {
        if isProcessing {
            return "Processing..."
        } else if isListening {
            return "Listening..."
        } else {
            return "Ready"
        }
    }

    private var instructionText: String {
        if isProcessing {
            return "Please wait while processing your request..."
        } else if isListening {
            return "Speak now... Tap again to stop"
        } else {
            return "Tap the microphone to start speaking"
        }
    }

    private func handleMicrophoneTap() async {
        if isListening {
            // Stop recording and process
            isListening = false
            isProcessing = true
            errorMessage = nil

            do {
                let result = try await viewModel.stopRecordingAndProcess()
                transcribedText = result.inputText
                responseText = result.outputText

                // Speak the response
                await viewModel.speakResponse(responseText)
            } catch {
                errorMessage = error.localizedDescription
            }

            isProcessing = false
        } else {
            // Start recording
            do {
                try await viewModel.startRecording()
                isListening = true
                transcribedText = ""
                responseText = ""
                errorMessage = nil
            } catch {
                errorMessage = error.localizedDescription
            }
        }
    }
}
