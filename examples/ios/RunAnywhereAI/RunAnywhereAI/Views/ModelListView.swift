//
//  ModelListView.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import SwiftUI

struct ModelListView: View {
    @StateObject private var viewModel = ModelListViewModel()
    @State private var selectedService: String?
    @State private var showingImportView = false
    @State private var showingDownloadView = false
    
    var body: some View {
        List {
            Section("Available Services") {
                ForEach(viewModel.availableServices, id: \.name) { service in
                    ServiceRow(
                        service: service,
                        isSelected: selectedService == service.name
                    )                        {
                            selectService(service)
                        }
                }
            }
            
            if let currentService = viewModel.currentService {
                Section("Available Models") {
                    ForEach(currentService.supportedModels) { model in
                        ModelRow(model: model) {
                            Task {
                                await viewModel.loadModel(model)
                            }
                        }
                    }
                }
            }
        }
        .navigationTitle("Models")
        .navigationBarTitleDisplayMode(.large)
        .toolbar {
            ToolbarItem(placement: .navigationBarTrailing) {
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
                    Image(systemName: "plus")
                }
            }
        }
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
        .onAppear {
            if selectedService == nil {
                selectedService = viewModel.availableServices.first?.name
                if let firstService = viewModel.availableServices.first {
                    selectService(firstService)
                }
            }
        }
    }
    
    private func selectService(_ service: LLMService) {
        selectedService = service.name
        viewModel.selectService(service)
    }
}

struct ServiceRow: View {
    let service: LLMService
    let isSelected: Bool
    let onSelect: () -> Void
    
    var body: some View {
        Button(action: onSelect) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(service.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    if service.isInitialized {
                        Label("Ready", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.green)
                    } else {
                        Label("Not initialized", systemImage: "exclamationmark.circle")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }
                
                Spacer()
                
                if isSelected {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.blue)
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
    }
}

struct ModelRow: View {
    let model: ModelInfo
    let onSelect: () -> Void
    @State private var isLoading = false
    @State private var showingCompatibility = false
    @StateObject private var unifiedService = UnifiedLLMService.shared
    
    var body: some View {
        Button(action: {
            isLoading = true
            onSelect()
        }) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(model.name)
                        .font(.headline)
                        .foregroundColor(.primary)
                    
                    Spacer()
                    
                    if isLoading {
                        ProgressView()
                            .scaleEffect(0.8)
                    } else {
                        Text(model.displaySize)
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.secondarySystemBackground))
                            .cornerRadius(8)
                    }
                }
                
                Text(model.description)
                    .font(.caption)
                    .foregroundColor(.secondary)
                    .lineLimit(2)
                
                HStack {
                    if let quantization = model.quantization {
                        Label(quantization, systemImage: "square.compress")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if model.isCompatible {
                        Label("Compatible", systemImage: "checkmark.circle")
                            .font(.caption2)
                            .foregroundColor(.green)
                    } else {
                        Label("Requires more memory", systemImage: "exclamationmark.triangle")
                            .font(.caption2)
                            .foregroundColor(.orange)
                    }
                }
                
                // Compatibility Check Button
                HStack {
                    Spacer()
                    Button(action: {
                        showingCompatibility = true
                    }) {
                        Label("Check Compatibility", systemImage: "checkmark.shield")
                            .font(.caption)
                            .foregroundColor(.blue)
                    }
                }
            }
            .padding(.vertical, 4)
            .contentShape(Rectangle())
        }
        .buttonStyle(PlainButtonStyle())
        .disabled(!model.isCompatible || isLoading)
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
    }
}

#Preview {
    NavigationView {
        ModelListView()
    }
}
