//
//  UnifiedModelsView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import SwiftUI

struct UnifiedModelsView: View {
    @StateObject private var viewModel = ModelListViewModel()
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    @StateObject private var downloadManager = ModelDownloadManager.shared
    @StateObject private var modelURLRegistry = ModelURLRegistry.shared
    
    @State private var expandedFramework: LLMFramework?
    @State private var selectedModel: ModelInfo?
    @State private var showingModelDetails = false
    @State private var showingDownloadProgress = false
    @State private var selectedDownloadInfo: ModelDownloadInfo?
    @State private var showingImportView = false
    @State private var showingDeviceInfo = false
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Device Status Overview
                    DeviceStatusCard(
                        deviceInfo: deviceInfoService.deviceInfo,
                        downloadedModelsCount: downloadedModelsCount,
                        activeDownloadsCount: downloadManager.activeDownloads.count,
                        showingDeviceInfo: $showingDeviceInfo
                    )
                    .padding(.horizontal)
                    
                    // Frameworks Section
                    VStack(alignment: .leading, spacing: 16) {
                        HStack {
                            Text("Models & Downloads")
                                .font(.title2)
                                .fontWeight(.semibold)
                            
                            Spacer()
                            
                            Menu {
                                Button(action: {
                                    showingImportView = true
                                }) {
                                    Label("Import Model", systemImage: "doc.badge.plus")
                                }
                                
                                Button(action: {
                                    Task {
                                        await modelURLRegistry.validateAllURLs()
                                    }
                                }) {
                                    Label("Refresh URLs", systemImage: "arrow.clockwise")
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Framework Cards
                        VStack(spacing: 12) {
                            ForEach(LLMFramework.availableFrameworks.filter { !$0.isDeferred }, id: \.self) { framework in
                                UnifiedFrameworkCard(
                                    framework: framework,
                                    isExpanded: expandedFramework == framework,
                                    viewModel: viewModel,
                                    onTap: {
                                        withAnimation(.spring()) {
                                            if expandedFramework == framework {
                                                expandedFramework = nil
                                            } else {
                                                expandedFramework = framework
                                            }
                                        }
                                    },
                                    onModelTap: { model in
                                        selectedModel = model
                                        showingModelDetails = true
                                    },
                                    onDownload: { downloadInfo in
                                        startDownload(downloadInfo)
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Coming Soon Section
                        if !LLMFramework.allCases.filter({ $0.isDeferred }).isEmpty {
                            ComingSoonSection()
                                .padding(.horizontal)
                        }
                    }
                }
                .padding(.vertical)
            }
            .navigationTitle("Models")
            .navigationBarTitleDisplayMode(.large)
            .background(Color(.systemGroupedBackground))
            .refreshable {
                await viewModel.refreshServices()
                await modelURLRegistry.validateAllURLs()
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $showingImportView) {
                ModelImportView()
            }
            .sheet(isPresented: $showingDeviceInfo) {
                DeviceInfoView()
            }
            .sheet(isPresented: $showingModelDetails) {
                if let model = selectedModel {
                    NavigationView {
                        UnifiedModelDetailsView(
                            model: model,
                            onDownload: { downloadInfo in
                                startDownload(downloadInfo)
                                showingModelDetails = false
                            }
                        )
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    showingModelDetails = false
                                }
                            }
                        }
                    }
                }
            }
            .fullScreenCover(isPresented: $showingDownloadProgress) {
                if let downloadInfo = selectedDownloadInfo {
                    let model = createModelInfo(from: downloadInfo)
                    ModelDownloadProgressView(
                        model: model,
                        downloadInfo: downloadInfo,
                        isPresented: $showingDownloadProgress
                    )
                } else {
                    // Fallback content to prevent black screen
                    VStack {
                        Text("Error loading download information")
                        Button("Close") {
                            showingDownloadProgress = false
                        }
                    }
                    .padding()
                }
            }
        }
    }
    
    private var downloadedModelsCount: Int {
        let allServices = viewModel.availableServices
        return allServices.reduce(0) { count, service in
            count + service.supportedModels.filter { $0.isLocal }.count
        }
    }
    
    private func createModelInfo(from downloadInfo: ModelDownloadInfo) -> ModelInfo {
        let format = ModelFormat.from(extension: downloadInfo.url.pathExtension)
        let framework = LLMFramework.forFormat(format)
        
        return ModelInfo(
            id: downloadInfo.id,
            name: downloadInfo.name,
            format: format,
            size: "Unknown",
            framework: framework,
            downloadURL: downloadInfo.url
        )
    }
    
    private func startDownload(_ downloadInfo: ModelDownloadInfo) {
        // First, start the actual download process
        downloadManager.downloadModel(downloadInfo, progress: { progress in
            // Progress updates handled by the download manager
        }, completion: { result in
            // Completion handled by the download manager
        })
        
        // Then show the progress view
        selectedDownloadInfo = downloadInfo
        showingDownloadProgress = true
    }
}

// MARK: - Device Status Card

struct DeviceStatusCard: View {
    let deviceInfo: SystemDeviceInfo?
    let downloadedModelsCount: Int
    let activeDownloadsCount: Int
    @Binding var showingDeviceInfo: Bool
    
    var body: some View {
        Button(action: {
            showingDeviceInfo = true
        }) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device Status")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let info = deviceInfo {
                            Text("\(info.modelName) • \(info.osVersion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    Spacer()
                    
                    VStack(alignment: .trailing, spacing: 4) {
                        Text("\(downloadedModelsCount) models")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if activeDownloadsCount > 0 {
                            Label("\(activeDownloadsCount) downloading", systemImage: "arrow.down.circle")
                                .font(.caption)
                                .foregroundColor(.blue)
                        }
                    }
                }
                
                if let info = deviceInfo {
                    HStack(spacing: 16) {
                        Label(info.availableMemory, systemImage: "memorychip")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        if info.neuralEngineAvailable {
                            Label("Neural Engine", systemImage: "cpu")
                                .font(.caption)
                                .foregroundColor(.green)
                        }
                        
                        Spacer()
                        
                        Image(systemName: "info.circle.fill")
                            .font(.title2)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding()
            .background(Color(.secondarySystemGroupedBackground))
            .cornerRadius(12)
        }
        .buttonStyle(PlainButtonStyle())
    }
}

// MARK: - Coming Soon Section

struct ComingSoonSection: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Coming Soon")
                .font(.headline)
                .foregroundColor(.secondary)
            
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 12) {
                    ForEach(LLMFramework.allCases.filter { $0.isDeferred }, id: \.self) { framework in
                        ComingSoonCard(framework: framework)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
    }
}

struct ComingSoonCard: View {
    let framework: LLMFramework
    
    private var frameworkIcon: String {
        switch framework {
        case .llamaCpp: return "cube.fill"
        case .execuTorch: return "bolt.fill"
        case .mlc: return "square.stack.3d.up.fill"
        case .picoLLM: return "ant.fill"
        case .swiftTransformers: return "swift"
        default: return "cube"
        }
    }
    
    var body: some View {
        VStack(spacing: 8) {
            Image(systemName: frameworkIcon)
                .font(.title)
                .foregroundColor(.orange)
            
            Text(framework.displayName)
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.primary)
                .multilineTextAlignment(.center)
            
            Label("Coming Soon", systemImage: "clock.fill")
                .font(.caption2)
                .foregroundColor(.orange)
        }
        .frame(width: 120)
        .padding()
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .opacity(0.7)
    }
}

#Preview {
    UnifiedModelsView()
}