import SwiftUI

struct ModelDownloadStatusView: View {
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @State private var showingDownloadView = false
    
    var body: some View {
        NavigationView {
            VStack {
                if downloadManager.activeDownloads.isEmpty {
                    emptyStateView
                } else {
                    activeDownloadsList
                }
            }
            .navigationTitle("Downloads")
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingDownloadView = true }) {
                        Image(systemName: "plus")
                    }
                }
            }
            .sheet(isPresented: $showingDownloadView) {
                ModelDownloadView()
            }
        }
    }
    
    private var emptyStateView: some View {
        VStack(spacing: 20) {
            Image(systemName: "arrow.down.circle")
                .font(.system(size: 60))
                .foregroundColor(.gray)
            
            Text("No Active Downloads")
                .font(.headline)
                .foregroundColor(.secondary)
            
            Text("Tap + to download models")
                .font(.caption)
                .foregroundColor(.secondary)
            
            Button(action: { showingDownloadView = true }) {
                Text("Browse Models")
                    .foregroundColor(.white)
                    .padding(.horizontal, 20)
                    .padding(.vertical, 10)
                    .background(Color.blue)
                    .cornerRadius(8)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
    
    private var activeDownloadsList: some View {
        List {
            ForEach(Array(downloadManager.activeDownloads.keys), id: \.self) { modelId in
                if let progress = downloadManager.activeDownloads[modelId] {
                    DownloadProgressRow(
                        modelId: modelId,
                        progress: progress,
                        onPause: {
                            downloadManager.pauseDownload(modelId)
                        },
                        onResume: {
                            downloadManager.resumeDownload(modelId)
                        },
                        onCancel: {
                            downloadManager.cancelDownload(modelId)
                        }
                    )
                }
            }
            
            if !downloadManager.downloadQueue.isEmpty {
                Section(header: Text("Queued")) {
                    ForEach(downloadManager.downloadQueue) { model in
                        HStack {
                            VStack(alignment: .leading) {
                                Text(model.name)
                                    .font(.headline)
                                Text(model.size)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            
                            Spacer()
                            
                            Image(systemName: "clock")
                                .foregroundColor(.orange)
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
    }
}

struct DownloadProgressRow: View {
    let modelId: String
    let progress: DownloadProgress
    let onPause: () -> Void
    let onResume: () -> Void
    let onCancel: () -> Void
    
    @State private var isPaused = false
    
    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text(modelId)
                    .font(.headline)
                
                Spacer()
                
                HStack(spacing: 12) {
                    Button(action: {
                        if isPaused {
                            onResume()
                        } else {
                            onPause()
                        }
                        isPaused.toggle()
                    }) {
                        Image(systemName: isPaused ? "play.circle" : "pause.circle")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                    
                    Button(action: onCancel) {
                        Image(systemName: "xmark.circle")
                            .font(.title2)
                            .foregroundColor(.red)
                    }
                }
            }
            
            ProgressView(value: progress.fractionCompleted) {
                Text(ModelDownloadManager.formatProgress(progress))
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
            .progressViewStyle(LinearProgressViewStyle())
            
            HStack {
                if progress.downloadSpeed > 0 {
                    Label(formatSpeed(progress.downloadSpeed), systemImage: "speedometer")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
                
                Spacer()
                
                if let timeRemaining = progress.estimatedTimeRemaining {
                    Label(formatTime(timeRemaining), systemImage: "clock")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                }
            }
        }
        .padding(.vertical, 4)
    }
    
    private func formatSpeed(_ bytesPerSecond: Double) -> String {
        let formatter = ByteCountFormatter()
        formatter.countStyle = .binary
        return "\(formatter.string(fromByteCount: Int64(bytesPerSecond)))/s"
    }
    
    private func formatTime(_ seconds: TimeInterval) -> String {
        let formatter = DateComponentsFormatter()
        formatter.unitsStyle = .abbreviated
        formatter.allowedUnits = [.hour, .minute, .second]
        return formatter.string(from: seconds) ?? ""
    }
}

struct ModelDownloadStatusView_Previews: PreviewProvider {
    static var previews: some View {
        ModelDownloadStatusView()
    }
}