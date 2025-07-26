//
//  ModelLoadingView.swift
//  RunAnywhereAI
//

import SwiftUI

struct ModelLoadingView: View {
    @StateObject private var loader = ModelLoader.shared
    @Binding var isPresented: Bool
    let model: ModelInfo
    let onSuccess: () -> Void
    
    @State private var hasStartedLoading = false
    
    var body: some View {
        VStack(spacing: 24) {
            // Header
            VStack(spacing: 8) {
                Image(systemName: "cpu")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                    .symbolEffect(.pulse, options: .repeating)
                
                Text("Loading Model")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(model.name)
                    .font(.subheadline)
                    .foregroundColor(.secondary)
            }
            
            // Progress
            VStack(spacing: 12) {
                ProgressView(value: loader.loadingProgress)
                    .progressViewStyle(LinearProgressViewStyle())
                    .frame(height: 8)
                    .scaleEffect(x: 1, y: 2, anchor: .center)
                
                HStack {
                    Text(loader.loadingStatus)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    
                    Spacer()
                    
                    Text("\(Int(loader.loadingProgress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .fontWeight(.medium)
                }
            }
            .padding(.horizontal)
            
            // Model Info
            VStack(alignment: .leading, spacing: 8) {
                InfoRow(label: "Format", value: model.format.displayName)
                InfoRow(label: "Framework", value: model.framework.displayName)
                InfoRow(label: "Size", value: model.size)
                if let quantization = model.quantization {
                    InfoRow(label: "Quantization", value: quantization)
                }
            }
            .padding()
            .background(Color.gray.opacity(0.1))
            .cornerRadius(12)
            
            // Error Display
            if let error = loader.error {
                VStack(spacing: 8) {
                    Label("Loading Failed", systemImage: "exclamationmark.triangle.fill")
                        .foregroundColor(.red)
                        .font(.headline)
                    
                    Text(error.localizedDescription)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .multilineTextAlignment(.center)
                    
                    if let llmError = error as? LLMError,
                       let recovery = llmError.recoverySuggestion {
                        Text(recovery)
                            .font(.caption2)
                            .foregroundColor(.blue)
                            .multilineTextAlignment(.center)
                    }
                }
                .padding()
                .background(Color.red.opacity(0.1))
                .cornerRadius(12)
            }
            
            // Actions
            HStack(spacing: 16) {
                if loader.error != nil {
                    Button("Retry") {
                        Task {
                            await loadModel()
                        }
                    }
                    .buttonStyle(.bordered)
                }
                
                Button(loader.isLoading ? "Cancel" : "Close") {
                    if loader.isLoading {
                        // In real implementation, would cancel the loading task
                    }
                    isPresented = false
                }
                .buttonStyle(.bordered)
            }
        }
        .padding(24)
        .frame(maxWidth: 400)
        .background(Color(UIColor.systemBackground))
        .cornerRadius(20)
        .shadow(radius: 20)
        .overlay(
            RoundedRectangle(cornerRadius: 20)
                .stroke(Color.gray.opacity(0.2), lineWidth: 1)
        )
        .onAppear {
            if !hasStartedLoading {
                hasStartedLoading = true
                Task {
                    await loadModel()
                }
            }
        }
    }
    
    private func loadModel() async {
        do {
            let success = try await loader.loadModel(
                at: model.path ?? "",
                format: model.format,
                framework: model.framework
            )
            
            if success {
                withAnimation {
                    onSuccess()
                    isPresented = false
                }
            }
        } catch {
            // Error is already set in loader
        }
    }
}

// MARK: - Info Row

private struct InfoRow: View {
    let label: String
    let value: String
    
    var body: some View {
        HStack {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Spacer()
            
            Text(value)
                .font(.caption)
                .fontWeight(.medium)
        }
    }
}

// MARK: - Loading Overlay Modifier

struct ModelLoadingModifier: ViewModifier {
    @Binding var isLoading: Bool
    let model: ModelInfo?
    let onSuccess: () -> Void
    
    func body(content: Content) -> some View {
        content
            .overlay(
                Group {
                    if isLoading, let model = model {
                        Color.black.opacity(0.4)
                            .ignoresSafeArea()
                        
                        ModelLoadingView(
                            isPresented: $isLoading,
                            model: model,
                            onSuccess: onSuccess
                        )
                    }
                }
            )
    }
}

extension View {
    func modelLoading(
        isLoading: Binding<Bool>,
        model: ModelInfo?,
        onSuccess: @escaping () -> Void
    ) -> some View {
        modifier(ModelLoadingModifier(
            isLoading: isLoading,
            model: model,
            onSuccess: onSuccess
        ))
    }
}

// MARK: - Preview

struct ModelLoadingView_Previews: PreviewProvider {
    static var previews: some View {
        ModelLoadingView(
            isPresented: .constant(true),
            model: ModelInfo(
                name: "TinyLlama-1.1B",
                format: .gguf,
                size: "637 MB",
                framework: .llamaCpp,
                quantization: "Q4_K_M"
            ),
            onSuccess: {}
        )
        .previewLayout(.sizeThatFits)
        .background(Color.gray.opacity(0.3))
    }
}