//
//  ModelListView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import SwiftUI

struct ModelListView: View {
    @StateObject private var viewModel = ModelListViewModel()
    @State private var selectedFramework: LLMFramework?
    @State private var showingImportView = false
    @State private var showingDownloadView = false
    @State private var showingDeviceInfo = false
    @State private var expandedFramework: LLMFramework?
    
    var body: some View {
        NavigationView {
            ScrollView {
                VStack(spacing: 20) {
                    // Device Info Card
                    DeviceInfoCard(showingDeviceInfo: $showingDeviceInfo)
                        .padding(.horizontal)
                    
                    // Framework Selection Section
                    VStack(alignment: .leading, spacing: 12) {
                        HStack {
                            Text("Select Framework")
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
                                    showingDownloadView = true
                                }) {
                                    Label("Download Model", systemImage: "arrow.down.circle")
                                }
                            } label: {
                                Image(systemName: "plus.circle.fill")
                                    .font(.title2)
                                    .foregroundColor(.blue)
                            }
                        }
                        .padding(.horizontal)
                        
                        // Available Frameworks
                        VStack(spacing: 12) {
                            ForEach(LLMFramework.availableFrameworks.filter { !$0.isDeferred }, id: \.self) { framework in
                                FrameworkCard(
                                    framework: framework,
                                    isExpanded: expandedFramework == framework,
                                    viewModel: viewModel,
                                    onTap: {
                                        withAnimation(.spring()) {
                                            if expandedFramework == framework {
                                                expandedFramework = nil
                                            } else {
                                                expandedFramework = framework
                                                selectedFramework = framework
                                                selectServiceForFramework(framework)
                                            }
                                        }
                                    }
                                )
                            }
                        }
                        .padding(.horizontal)
                        
                        // Coming Soon Section
                        if !LLMFramework.allCases.filter({ $0.isDeferred }).isEmpty {
                            VStack(alignment: .leading, spacing: 12) {
                                Text("Coming Soon")
                                    .font(.headline)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                
                                ScrollView(.horizontal, showsIndicators: false) {
                                    HStack(spacing: 12) {
                                        ForEach(LLMFramework.allCases.filter { $0.isDeferred }, id: \.self) { framework in
                                            ComingSoonCard(framework: framework)
                                        }
                                    }
                                    .padding(.horizontal)
                                }
                            }
                            .padding(.top)
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
            }
            .alert("Error", isPresented: $viewModel.showError) {
                Button("OK", role: .cancel) { }
            } message: {
                Text(viewModel.errorMessage)
            }
            .sheet(isPresented: $showingImportView) {
                ModelImportView()
            }
            .sheet(isPresented: $showingDownloadView) {
                ModelDownloadView()
            }
            .sheet(isPresented: $showingDeviceInfo) {
                DeviceInfoView()
            }
        }
    }
    
    private func selectServiceForFramework(_ framework: LLMFramework) {
        if let service = viewModel.availableServices.first(where: { 
            $0.name == framework.displayName || $0.name.lowercased() == framework.rawValue.lowercased() 
        }) {
            viewModel.selectService(service)
        }
    }
}

struct DeviceInfoCard: View {
    @Binding var showingDeviceInfo: Bool
    @StateObject private var deviceInfoService = DeviceInfoService.shared
    
    var body: some View {
        Button(action: {
            showingDeviceInfo = true
        }) {
            VStack(spacing: 12) {
                HStack {
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Device Info")
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let info = deviceInfoService.deviceInfo {
                            Text("\(info.modelName) • \(info.osVersion)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                            
                            HStack(spacing: 12) {
                                Label(info.availableMemory, systemImage: "memorychip")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                
                                if info.neuralEngineAvailable {
                                    Label("Neural Engine", systemImage: "cpu")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                }
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: "info.circle.fill")
                        .font(.title2)
                        .foregroundColor(.blue)
                }
                .padding()
                .background(Color(.secondarySystemGroupedBackground))
                .cornerRadius(12)
            }
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct FrameworkCard: View {
    let framework: LLMFramework
    let isExpanded: Bool
    let viewModel: ModelListViewModel
    @State private var isLoading = false
    let onTap: () -> Void
    
    private var service: LLMService? {
        viewModel.availableServices.first { service in
            service.name == framework.displayName || service.name.lowercased() == framework.rawValue.lowercased()
        }
    }
    
    private var frameworkIcon: String {
        switch framework {
        case .coreML: return "brain.head.profile"
        case .mlx: return "cube.fill"
        case .onnxRuntime: return "cpu.fill"
        case .tensorFlowLite: return "square.stack.3d.up.fill"
        case .foundationModels: return "sparkles"
        default: return "cube"
        }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            // Framework Header
            Button(action: onTap) {
                HStack {
                    Image(systemName: frameworkIcon)
                        .font(.title2)
                        .foregroundColor(.blue)
                        .frame(width: 40)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(framework.displayName)
                            .font(.headline)
                            .foregroundColor(.primary)
                        
                        if let service = service {
                            HStack(spacing: 8) {
                                if service.isInitialized {
                                    Label("Ready", systemImage: "checkmark.circle.fill")
                                        .font(.caption)
                                        .foregroundColor(.green)
                                } else {
                                    Label("Not initialized", systemImage: "circle")
                                        .font(.caption)
                                        .foregroundColor(.secondary)
                                }
                                
                                Text("•")
                                    .foregroundColor(.secondary)
                                
                                Text("\(service.supportedModels.count) models")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                    }
                    
                    Spacer()
                    
                    Image(systemName: isExpanded ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
                .padding()
                .contentShape(Rectangle())
            }
            .buttonStyle(PlainButtonStyle())
            
            // Expanded Model List
            if isExpanded, let service = service {
                Divider()
                
                if service.supportedModels.isEmpty {
                    VStack(spacing: 12) {
                        Image(systemName: "doc.text.magnifyingglass")
                            .font(.largeTitle)
                            .foregroundColor(.secondary)
                        
                        Text("No models available")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        
                        Text("Import or download models to get started")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .multilineTextAlignment(.center)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 30)
                } else {
                    VStack(spacing: 0) {
                        ForEach(service.supportedModels) { model in
                            ModelItemRow(model: model, viewModel: viewModel)
                            
                            if model.id != service.supportedModels.last?.id {
                                Divider()
                                    .padding(.leading, 56)
                            }
                        }
                    }
                }
            }
        }
        .background(Color(.secondarySystemGroupedBackground))
        .cornerRadius(12)
        .shadow(color: Color.black.opacity(0.05), radius: 5, x: 0, y: 2)
    }
}

struct ModelItemRow: View {
    let model: ModelInfo
    let viewModel: ModelListViewModel
    @State private var isLoading = false
    @State private var showingCompatibility = false
    @State private var showingNoURLAlert = false
    @State private var showingDownloadView = false
    @State private var showingDownloadProgress = false
    @State private var selectedDownloadInfo: ModelDownloadInfo?
    @State private var downloadProgress: Double = 0
    @State private var isDownloading = false
    
    @StateObject private var downloadManager = ModelDownloadManager.shared
    
    private var hasDownloadURL: Bool {
        // Check if there's a URL in ModelURLRegistry for this model
        let registry = ModelURLRegistry.shared
        let modelsWithURLs = registry.getAllModels(for: model.framework)
        
        // More flexible matching - check if names are similar
        return modelsWithURLs.contains { downloadInfo in
            // Exact match
            if downloadInfo.name == model.name || downloadInfo.id == model.id {
                return true
            }
            
            // Check if the model name contains key parts of the download name
            let modelNameLower = model.name.lowercased()
            let downloadNameLower = downloadInfo.name.lowercased()
            
            // Check for common patterns
            if modelNameLower.contains("phi") && downloadNameLower.contains("phi") {
                return true
            }
            if modelNameLower.contains("tinyllama") && downloadNameLower.contains("tinyllama") {
                return true
            }
            if modelNameLower.contains("llama-3.2") && downloadNameLower.contains("llama-3.2") {
                return true
            }
            if modelNameLower.contains("mistral") && downloadNameLower.contains("mistral") {
                return true
            }
            
            return false
        }
    }
    
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "doc.fill")
                .font(.title3)
                .foregroundColor(.secondary)
                .frame(width: 40)
            
            VStack(alignment: .leading, spacing: 4) {
                Text(model.name)
                    .font(.subheadline)
                    .fontWeight(.medium)
                    .foregroundColor(.primary)
                
                HStack(spacing: 8) {
                    Text(model.displaySize)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    if let quantization = model.quantization {
                        Text("•")
                            .foregroundColor(.secondary)
                        Text(quantization)
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    if model.isCompatible {
                        Text("•")
                            .foregroundColor(.secondary)
                        Label("Compatible", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    }
                    
                    if model.isLocal {
                        Text("•")
                            .foregroundColor(.secondary)
                        Label("Downloaded", systemImage: "checkmark.icloud.fill")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
                
            }
            
            Spacer()
            
            // Action buttons
            HStack(spacing: 8) {
                // Download button
                if !model.isLocal {
                    Button(action: {
                        if hasDownloadURL {
                            showingDownloadView = true
                        } else {
                            showingNoURLAlert = true
                        }
                    }) {
                        Image(systemName: isDownloading ? "stop.circle.fill" : "arrow.down.circle.fill")
                            .font(.title2)
                            .foregroundColor(isDownloading ? .red : .blue)
                    }
                    .disabled(isDownloading && false) // Allow cancellation
                }
                
                // Load button
                if model.isLocal {
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Button(action: {
                            Task {
                                isLoading = true
                                await viewModel.loadModel(model)
                                isLoading = false
                            }
                        }) {
                            Text("Load")
                                .font(.caption)
                                .fontWeight(.medium)
                                .foregroundColor(.white)
                                .padding(.horizontal, 16)
                                .padding(.vertical, 6)
                                .background(model.isCompatible ? Color.blue : Color.gray)
                                .cornerRadius(15)
                        }
                        .disabled(!model.isCompatible || isLoading)
                    }
                }
            }
        }
        .padding()
        .contentShape(Rectangle())
        .onTapGesture {
            showingCompatibility = true
        }
        .sheet(isPresented: $showingCompatibility) {
            NavigationView {
                ModelCompatibilityView(
                    model: model,
                    framework: model.framework
                )
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            showingCompatibility = false
                        }
                    }
                }
            }
        }
        .sheet(isPresented: $showingDownloadView) {
            ModelDownloadConfirmationView(
                model: model,
                onDownload: { downloadInfo in
                    selectedDownloadInfo = downloadInfo
                    showingDownloadProgress = true
                }
            )
        }
        .fullScreenCover(isPresented: $showingDownloadProgress) {
            if let downloadInfo = selectedDownloadInfo {
                ModelDownloadProgressView(
                    model: model,
                    downloadInfo: downloadInfo,
                    isPresented: $showingDownloadProgress
                )
            }
        }
        .alert("No Download URL Available", isPresented: $showingNoURLAlert) {
            Button("OK", role: .cancel) { }
            Button("Add Custom URL") {
                // TODO: Show custom URL input
            }
        } message: {
            Text("This model doesn't have a pre-configured download URL. You can add a custom URL or download it manually.")
        }
    }
    
    private func startDownload(_ downloadInfo: ModelDownloadInfo) {
        isDownloading = true
        downloadProgress = 0
        
        downloadManager.downloadModel(downloadInfo, progress: { progress in
            Task { @MainActor in
                self.downloadProgress = progress.fractionCompleted
            }
        }, completion: { result in
            Task { @MainActor in
                self.isDownloading = false
                switch result {
                case .success(let url):
                    // Update model to mark as local
                    await viewModel.refreshServices()
                case .failure(let error):
                    print("Download failed: \(error)")
                }
            }
        })
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
    ModelListView()
}