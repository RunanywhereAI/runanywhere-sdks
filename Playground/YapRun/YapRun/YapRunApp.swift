//
//  YapRunApp.swift
//  YapRun
//
//  On-device voice dictation keyboard powered by RunAnywhere SDK.
//  ASR only — uses Sherpa Whisper Tiny (ONNX) for transcription.
//

import SwiftUI
import RunAnywhere
import ONNXRuntime
import os

@main
struct YapRunApp: App {
    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "App")

    @StateObject private var flowSession = FlowSessionManager.shared
    @State private var showFlowActivation = false
    @State private var isSDKInitialized = false
    @State private var initializationError: String?

    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    ContentView()
                        .environmentObject(flowSession)
                        .onOpenURL { url in
                            guard url.scheme == SharedConstants.urlScheme,
                                  url.host == "startFlow" else { return }
                            logger.info("Received startFlow deep link")
                            showFlowActivation = true
                            Task { await flowSession.handleStartFlow() }
                        }
                        .fullScreenCover(isPresented: $showFlowActivation) {
                            FlowActivationView(isPresented: $showFlowActivation)
                                .environmentObject(flowSession)
                        }
                } else if let error = initializationError {
                    errorView(error)
                } else {
                    loadingView
                }
            }
            .preferredColorScheme(.dark)
            .task {
                await initializeSDK()
            }
        }
    }

    // MARK: - SDK Initialization

    private func initializeSDK() async {
        do {
            ONNX.register(priority: 100)

            try RunAnywhere.initialize()
            logger.info("SDK initialized in development mode")

            // Register the Whisper STT model
            if let whisperURL = URL(string: "https://github.com/RunanywhereAI/sherpa-onnx/releases/download/runanywhere-models-v1/sherpa-onnx-whisper-tiny.en.tar.gz") {
                RunAnywhere.registerModel(
                    id: "sherpa-onnx-whisper-tiny.en",
                    name: "Sherpa Whisper Tiny (ONNX)",
                    url: whisperURL,
                    framework: .onnx,
                    modality: .speechRecognition,
                    artifactType: .archive(.tarGz, structure: .nestedDirectory),
                    memoryRequirement: 75_000_000
                )
            }

            logger.info("STT model registered")
            await MainActor.run { isSDKInitialized = true }
        } catch {
            logger.error("SDK initialization failed: \(error.localizedDescription)")
            await MainActor.run { initializationError = error.localizedDescription }
        }
    }

    // MARK: - Views

    private var loadingView: some View {
        VStack(spacing: 20) {
            ProgressView()
                .tint(AppColors.primaryAccent)
                .scaleEffect(1.3)
            Text("Setting up YapRun...")
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.primaryAccent)
            Text("Setup Failed")
                .font(.title2.bold())
            Text(message)
                .font(.subheadline)
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                initializationError = nil
                Task { await initializeSDK() }
            }
            .buttonStyle(.borderedProminent)
            .tint(AppColors.primaryAccent)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemBackground))
    }
}
