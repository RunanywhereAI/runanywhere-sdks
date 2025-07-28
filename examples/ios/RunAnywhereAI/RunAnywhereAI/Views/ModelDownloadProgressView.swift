//
//  ModelDownloadProgressView.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/28/25.
//

import SwiftUI
import Combine
import CryptoKit
import ZIPFoundation

enum DownloadStep: String, CaseIterable {
    case preparing = "Preparing"
    case downloading = "Downloading"
    case verifying = "Verifying"
    case extracting = "Extracting"
    case installing = "Installing"
    case complete = "Complete"

    var icon: String {
        switch self {
        case .preparing: return "gear"
        case .downloading: return "arrow.down.circle"
        case .verifying: return "checkmark.shield"
        case .extracting: return "doc.zipper"
        case .installing: return "square.and.arrow.down"
        case .complete: return "checkmark.circle.fill"
        }
    }

    var description: String {
        switch self {
        case .preparing: return "Checking storage and preparing download..."
        case .downloading: return "Downloading model from server..."
        case .verifying: return "Verifying model integrity..."
        case .extracting: return "Extracting model files..."
        case .installing: return "Installing model and tokenizer files..."
        case .complete: return "Model ready to use!"
        }
    }
}

struct ModelDownloadProgressView: View {
    let model: ModelInfo
    let downloadInfo: ModelDownloadInfo
    @Binding var isPresented: Bool

    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var currentStep: DownloadStep = .preparing
    @State private var downloadProgress: Double = 0
    @State private var downloadSpeed: String = ""
    @State private var timeRemaining: String = ""
    @State private var error: Error?
    @State private var showingError = false
    @State private var downloadTask: AnyCancellable?
    @State private var isComplete = false
    @State private var downloadedSize: String = "0 MB"
    @State private var totalSize: String = "0 MB"

    var body: some View {
        NavigationView {
            ZStack {
                // Background
                Color(.systemBackground)
                    .ignoresSafeArea()

                ScrollView {
                    VStack(spacing: 0) {
                    // Header with model info
                    VStack(spacing: 12) {
                        Image(systemName: "doc.fill")
                            .font(.system(size: 48))
                            .foregroundColor(.blue)

                        Text(model.name)
                            .font(.title2)
                            .fontWeight(.bold)

                        HStack {
                            Label(model.framework.displayName, systemImage: "cpu")
                            Text("•")
                            Label(model.displaySize, systemImage: "internaldrive")
                        }
                        .font(.caption)
                        .foregroundColor(.secondary)
                    }
                    .padding(.top, 20)
                    .padding(.bottom, 30)

                    // Progress Steps
                    VStack(spacing: 0) {
                        ForEach(Array(DownloadStep.allCases.enumerated()), id: \.offset) { index, step in
                            DownloadStepRow(
                                step: step,
                                isActive: step == currentStep,
                                isCompleted: DownloadStep.allCases.firstIndex(of: step)! < DownloadStep.allCases.firstIndex(of: currentStep)!,
                                progress: step == .downloading ? downloadProgress : nil
                            )

                            if index < DownloadStep.allCases.count - 1 {
                                StepConnector(
                                    isCompleted: DownloadStep.allCases.firstIndex(of: step)! < DownloadStep.allCases.firstIndex(of: currentStep)!
                                )
                            }
                        }
                    }
                    .padding(.horizontal)

                    // Download Details
                    if currentStep == .downloading {
                        VStack(spacing: 16) {
                            // Progress bar
                            VStack(alignment: .leading, spacing: 8) {
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(LinearProgressViewStyle())
                                    .tint(.blue)
                                    .scaleEffect(y: 2)

                                HStack {
                                    Text("\(Int(downloadProgress * 100))%")
                                        .font(.caption)
                                        .fontWeight(.medium)

                                    Spacer()

                                    Text("\(downloadedSize) / \(totalSize)")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }

                            // Speed and time
                            HStack {
                                if !downloadSpeed.isEmpty {
                                    Label(downloadSpeed, systemImage: "speedometer")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }

                                Spacer()

                                if !timeRemaining.isEmpty {
                                    Label(timeRemaining, systemImage: "clock")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                        .padding()
                        .background(Color(.secondarySystemGroupedBackground))
                        .cornerRadius(12)
                        .padding()
                    }

                    // Current step description
                    if !isComplete {
                        Text(currentStep.description)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                            .padding(.horizontal)
                            .padding(.top, 20)
                    }

                    // Spacer for proper spacing in ScrollView
                    Color.clear.frame(height: 80)

                    // Action buttons
                    if isComplete {
                        Button(action: {
                            isPresented = false
                        }) {
                            Text("Done")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color.blue)
                                .foregroundColor(.white)
                                .cornerRadius(12)
                        }
                        .padding()
                    } else {
                        Button(action: cancelDownload) {
                            Text("Cancel Download")
                                .fontWeight(.medium)
                                .frame(maxWidth: .infinity)
                                .padding()
                                .background(Color(.systemGray5))
                                .foregroundColor(.red)
                                .cornerRadius(12)
                        }
                        .padding()
                    }
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .navigationTitle("Downloading Model")
            .navigationBarTitleDisplayMode(.inline)
            .navigationBarHidden(isComplete)
        }
        .interactiveDismissDisabled(true)
        .onAppear {
            startDownload()
        }
        .alert("Download Error", isPresented: $showingError) {
            Button("Retry") {
                startDownload()
            }
            Button("Cancel", role: .cancel) {
                isPresented = false
            }
        } message: {
            Text(error?.localizedDescription ?? "Unknown error occurred")
        }
    }

    private func startDownload() {
        currentStep = .preparing

        Task {
            // Simulate preparing phase
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            await MainActor.run {
                currentStep = .downloading
            }

            // Check if this is a Kaggle model and handle separately
            if downloadInfo.requiresAuth && downloadInfo.url.host?.contains("kaggle") == true {
                try await downloadKaggleModel()
            } else {
                // Start regular download
                downloadManager.downloadModel(downloadInfo, progress: { progress in
                    Task { @MainActor in
                        self.downloadProgress = progress.fractionCompleted

                        // Format download speed
                        let formatter = ByteCountFormatter()
                        formatter.countStyle = .binary
                        let speed = formatter.string(fromByteCount: Int64(progress.downloadSpeed))
                        self.downloadSpeed = "\(speed)/s"

                        // Format sizes
                        self.downloadedSize = formatter.string(fromByteCount: progress.bytesWritten)
                        self.totalSize = formatter.string(fromByteCount: progress.totalBytes)

                        // Format time remaining
                        if let timeRemaining = progress.estimatedTimeRemaining {
                            let formatter = DateComponentsFormatter()
                            formatter.unitsStyle = .abbreviated
                            formatter.allowedUnits = [.hour, .minute, .second]
                            if let timeString = formatter.string(from: timeRemaining) {
                                self.timeRemaining = timeString
                            }
                        }
                    }
                }, completion: { result in
                    Task { @MainActor in
                        switch result {
                        case .success(let tempURL):
                            print("Download succeeded, temp URL: \(tempURL.path)")
                            print("File exists: \(FileManager.default.fileExists(atPath: tempURL.path))")
                            // Continue with post-download steps
                            await self.processDownloadedModel(at: tempURL)
                        case .failure(let error):
                            print("Download failed with error: \(error.localizedDescription)")
                            self.error = error
                            self.showingError = true
                        }
                    }
                })
            }
        }
    }

    private func downloadKaggleModel() async throws {
        // Use separate Kaggle download service
        let authService = KaggleAuthService.shared

        let tempURL = try await authService.downloadModel(from: downloadInfo.url) { progress in
            Task { @MainActor in
                self.downloadProgress = progress

                // Format progress details
                let formatter = ByteCountFormatter()
                formatter.countStyle = .binary
                self.downloadedSize = formatter.string(fromByteCount: Int64(progress * 100_000_000)) // Estimate
                self.totalSize = formatter.string(fromByteCount: 100_000_000) // Estimate
            }
        }

        // Continue with post-download processing
        await processDownloadedModel(at: tempURL)
    }

    private func processDownloadedModel(at url: URL) async {
        do {
            // First, ensure the file exists and is accessible
            guard FileManager.default.fileExists(atPath: url.path) else {
                throw ModelDownloadError.networkError(NSError(
                    domain: "ModelDownload",
                    code: -1,
                    userInfo: [NSLocalizedDescriptionKey: "Downloaded file not found at expected location"]
                ))
            }
            
            // Verifying step
            currentStep = .verifying
            try? await Task.sleep(nanoseconds: 1_500_000_000) // 1.5 seconds

            // Verify checksum if available
            if let expectedHash = downloadInfo.sha256 {
                do {
                    let data = try Data(contentsOf: url)
                    let hash = SHA256.hash(data: data)
                    let hashString = hash.compactMap { String(format: "%02x", $0) }.joined()

                    guard hashString == expectedHash else {
                        throw ModelDownloadError.invalidChecksum
                    }
                } catch {
                    print("Failed to verify checksum: \(error.localizedDescription)")
                    // Continue without checksum verification if file reading fails
                }
            }

            // Get models directory
            let documentsURL = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first!
            let modelsDirectory = documentsURL.appendingPathComponent("Models")
            let modelDirectory = modelsDirectory.appendingPathComponent(model.framework.displayName)

            try FileManager.default.createDirectory(at: modelDirectory, withIntermediateDirectories: true)

            // Check if extraction is needed
            if downloadInfo.requiresUnzip {
                currentStep = .extracting
                try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

                // Extract the file
                if url.pathExtension == "zip" {
                    try FileManager.default.unzipItem(at: url, to: modelDirectory)
                } else {
                    // For other compressed formats, just copy for now
                    let destinationURL = modelDirectory.appendingPathComponent(url.lastPathComponent)
                    try FileManager.default.copyItem(at: url, to: destinationURL)
                }
            } else {
                // Just copy the file
                let destinationURL = modelDirectory.appendingPathComponent(downloadInfo.name)
                if FileManager.default.fileExists(atPath: destinationURL.path) {
                    try FileManager.default.removeItem(at: destinationURL)
                }
                
                // Ensure source file exists before copying
                guard FileManager.default.fileExists(atPath: url.path) else {
                    throw ModelDownloadError.networkError(NSError(
                        domain: "ModelDownload",
                        code: -2,
                        userInfo: [NSLocalizedDescriptionKey: "Source file not found: \(url.lastPathComponent)"]
                    ))
                }
                
                print("Moving downloaded file:")
                print("  From: \(url.path)")
                print("  To: \(destinationURL.path)")
                
                do {
                    // Try to move first, as it's more efficient
                    try FileManager.default.moveItem(at: url, to: destinationURL)
                    print("Successfully moved model to: \(destinationURL.path)")
                } catch {
                    print("Move failed, trying copy: \(error.localizedDescription)")
                    // If move fails, try copy
                    do {
                        try FileManager.default.copyItem(at: url, to: destinationURL)
                        // Clean up source file after successful copy
                        try? FileManager.default.removeItem(at: url)
                        print("Successfully copied model to: \(destinationURL.path)")
                    } catch {
                        print("Failed to copy file: \(error.localizedDescription)")
                        print("Source: \(url.path)")
                        print("Destination: \(destinationURL.path)")
                        throw error
                    }
                }
            }

            // Installing step (download tokenizers if needed)
            currentStep = .installing
            try? await Task.sleep(nanoseconds: 1_000_000_000) // 1 second

            // Download tokenizers for frameworks that need them
            if shouldDownloadTokenizers() {
                let tokenizerFiles = ModelURLRegistry.shared.getTokenizerFiles(for: model.id)
                for file in tokenizerFiles {
                    do {
                        let (tokenizerURL, _) = try await URLSession.shared.download(from: file.url)
                        let destinationURL = modelDirectory.appendingPathComponent(file.name)

                        if FileManager.default.fileExists(atPath: destinationURL.path) {
                            try FileManager.default.removeItem(at: destinationURL)
                        }

                        try FileManager.default.moveItem(at: tokenizerURL, to: destinationURL)
                    } catch {
                        print("Failed to download tokenizer file \(file.name): \(error)")
                    }
                }
            }

            // Complete
            currentStep = .complete
            isComplete = true

            // Haptic feedback
            let impactFeedback = UIImpactFeedbackGenerator(style: .medium)
            impactFeedback.impactOccurred()
            
            // Refresh model list to show downloaded status
            await ModelManager.shared.refreshModelList()
        } catch {
            await MainActor.run {
                self.error = error
                self.showingError = true
            }
        }
    }

    private func shouldDownloadTokenizers() -> Bool {
        switch model.framework {
        case .coreML, .mlx, .onnxRuntime:
            return true
        case .llamaCpp, .tensorFlowLite:
            return false // Usually embedded in model
        default:
            return false
        }
    }

    private func cancelDownload() {
        downloadManager.cancelDownload(downloadInfo.id)
        isPresented = false
    }
}

struct DownloadStepRow: View {
    let step: DownloadStep
    let isActive: Bool
    let isCompleted: Bool
    let progress: Double?

    var body: some View {
        HStack(spacing: 16) {
            // Step icon
            ZStack {
                Circle()
                    .fill(backgroundColor)
                    .frame(width: 44, height: 44)

                if isActive && step == .downloading, let progress = progress {
                    CircularProgressView(progress: progress)
                        .frame(width: 44, height: 44)
                }

                Image(systemName: step.icon)
                    .font(.system(size: 20))
                    .foregroundColor(iconColor)
            }

            // Step info
            VStack(alignment: .leading, spacing: 4) {
                Text(step.rawValue)
                    .font(.headline)
                    .foregroundColor(isActive || isCompleted ? .primary : .secondary)

                if isActive {
                    Text(step.description)
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }

            Spacer()

            // Status indicator
            if isCompleted {
                Image(systemName: "checkmark")
                    .font(.caption)
                    .fontWeight(.bold)
                    .foregroundColor(.green)
            } else if isActive {
                ProgressView()
                    .scaleEffect(0.8)
            }
        }
        .padding(.vertical, 12)
    }

    private var backgroundColor: Color {
        if isCompleted {
            return .green.opacity(0.2)
        } else if isActive {
            return .blue.opacity(0.2)
        } else {
            return Color(.systemGray5)
        }
    }

    private var iconColor: Color {
        if isCompleted {
            return .green
        } else if isActive {
            return .blue
        } else {
            return .secondary
        }
    }
}

struct StepConnector: View {
    let isCompleted: Bool

    var body: some View {
        Rectangle()
            .fill(isCompleted ? Color.green : Color(.systemGray5))
            .frame(width: 2, height: 30)
            .padding(.leading, 22)
    }
}

struct CircularProgressView: View {
    let progress: Double

    var body: some View {
        ZStack {
            Circle()
                .stroke(Color.blue.opacity(0.3), lineWidth: 3)

            Circle()
                .trim(from: 0, to: progress)
                .stroke(Color.blue, lineWidth: 3)
                .rotationEffect(.degrees(-90))
                .animation(.linear(duration: 0.2), value: progress)
        }
    }
}

struct ModelDownloadProgressView_Previews: PreviewProvider {
    static var previews: some View {
        ModelDownloadProgressView(
            model: ModelInfo(
                name: "Llama 3.2 3B",
                format: .gguf,
                size: "2.4 GB",
                framework: .llamaCpp,
                quantization: "Q4_K_M"
            ),
            downloadInfo: ModelDownloadInfo(
                id: "llama-3.2-3b",
                name: "Llama-3.2-3B-Instruct-Q4_K_M.gguf",
                url: URL(string: "https://example.com")!,
                sha256: nil,
                requiresUnzip: false,
                requiresAuth: false
            ),
            isPresented: .constant(true)
        )
    }
}
