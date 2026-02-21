//
//  YapRunApp.swift
//  YapRun
//
//  On-device voice dictation powered by RunAnywhere SDK.
//  ASR only — uses Sherpa Whisper Tiny (ONNX) for transcription.
//  Supports both iOS and macOS from a shared codebase.
//

import SwiftUI
import RunAnywhere
import ONNXRuntime
import os

@main
struct YapRunApp: App {
    private let logger = Logger(subsystem: "com.runanywhere.yaprun", category: "App")

    #if os(iOS)
    @StateObject private var flowSession = FlowSessionManager.shared
    @State private var showFlowActivation = false
    #endif

    #if os(macOS)
    @NSApplicationDelegateAdaptor(MacAppDelegate.self) var appDelegate
    #endif

    @State private var isSDKInitialized = false
    @State private var initializationError: String?

    #if os(iOS)
    @State private var hasCompletedOnboarding = SharedDataBridge.shared.defaults?.bool(
        forKey: SharedConstants.Keys.hasCompletedOnboarding
    ) ?? false
    #elseif os(macOS)
    @State private var hasCompletedOnboarding = UserDefaults.standard.bool(forKey: "hasCompletedOnboarding")
    #endif

    var body: some Scene {
        #if os(iOS)
        WindowGroup {
            Group {
                if isSDKInitialized {
                    if hasCompletedOnboarding {
                        iOSHomeContent
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
        #elseif os(macOS)
        // macOS uses agent app pattern — UI driven by MacAppDelegate.
        // Settings scene is a no-op required by SwiftUI App protocol.
        Settings {
            EmptyView()
        }
        .defaultSize(width: 0, height: 0)
        #endif
    }

    // MARK: - iOS Home Content

    #if os(iOS)
    private var iOSHomeContent: some View {
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
    #endif

    // MARK: - SDK Initialization

    func initializeSDK() async {
        do {
            ONNX.register(priority: 100)

            try RunAnywhere.initialize()
            logger.info("SDK initialized in development mode")

            ModelRegistry.registerAll()
            logger.info("ASR models registered")
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
