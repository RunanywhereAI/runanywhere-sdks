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
    @State private var hasCompletedOnboarding = SharedDataBridge.shared.defaults?.bool(
        forKey: SharedConstants.Keys.hasCompletedOnboarding
    ) ?? false

    var body: some Scene {
        WindowGroup {
            Group {
                if isSDKInitialized {
                    if hasCompletedOnboarding {
                        homeContent
                    } else {
                        OnboardingView {
                            withAnimation(.easeInOut(duration: 0.4)) {
                                hasCompletedOnboarding = true
                            }
                        }
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

    // MARK: - Home Content

    private var homeContent: some View {
        TabView {
            ContentView()
                .environmentObject(flowSession)
                .tabItem {
                    Label("Home", systemImage: "house")
                }

            PlaygroundView()
                .tabItem {
                    Label("Playground", systemImage: "waveform")
                }

            NotepadView()
                .tabItem {
                    Label("Notepad", systemImage: "note.text")
                }
        }
        .tint(AppColors.ctaOrange)
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
        VStack(spacing: 24) {
            Image("yaprun_logo")
                .resizable()
                .aspectRatio(contentMode: .fit)
                .frame(width: 80, height: 80)
                .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))

            Text("YapRun")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(AppColors.textPrimary)

            ProgressView()
                .tint(.white)
                .scaleEffect(1.1)
                .padding(.top, 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimaryDark)
    }

    private func errorView(_ message: String) -> some View {
        VStack(spacing: 20) {
            Image(systemName: "exclamationmark.triangle")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.ctaOrange)
            Text("Setup Failed")
                .font(.title2.bold())
                .foregroundStyle(AppColors.textPrimary)
            Text(message)
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal)
            Button("Retry") {
                initializationError = nil
                Task { await initializeSDK() }
            }
            .buttonStyle(.borderedProminent)
            .tint(.white)
            .foregroundStyle(.black)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.backgroundPrimaryDark)
    }
}
