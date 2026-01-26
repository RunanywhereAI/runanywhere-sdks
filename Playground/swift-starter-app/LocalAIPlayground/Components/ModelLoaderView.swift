//
//  ModelLoaderView.swift
//  LocalAIPlayground
//
//  =============================================================================
//  MODEL LOADER VIEW - DOWNLOAD & LOADING PROGRESS UI
//  =============================================================================
//
//  A reusable component for displaying model download and loading progress.
//  Used throughout the app whenever AI models need to be fetched or initialized.
//
//  FEATURES:
//  - Progress bar with percentage
//  - Model size and ETA display
//  - State-based appearance (downloading, loading, ready, error)
//  - Retry functionality for failed downloads
//
//  =============================================================================

import SwiftUI

// =============================================================================
// MARK: - Model Loader View
// =============================================================================
/// Displays the loading state and progress of an AI model.
///
/// This component handles all states of model loading:
/// - Not loaded (with load button)
/// - Downloading (with progress)
/// - Loading into memory
/// - Ready (success indicator)
/// - Error (with retry option)
// =============================================================================
struct ModelLoaderView: View {
    /// Name of the model being loaded
    let modelName: String
    
    /// Description of the model
    let modelDescription: String
    
    /// Approximate size of the model
    let modelSize: String
    
    /// Current state of the model
    let state: ModelState
    
    /// Action to trigger loading
    let onLoad: () -> Void
    
    /// Action to retry after error
    let onRetry: () -> Void
    
    @Environment(\.colorScheme) var colorScheme
    
    var body: some View {
        VStack(alignment: .leading, spacing: AISpacing.md) {
            // Header with model info
            HStack(spacing: AISpacing.md) {
                // Model icon
                modelIcon
                
                // Model details
                VStack(alignment: .leading, spacing: AISpacing.xs) {
                    Text(modelName)
                        .font(.aiHeadingSmall)
                    
                    Text(modelDescription)
                        .font(.aiBodySmall)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }
                
                Spacer()
                
                // Size badge
                Text(modelSize)
                    .font(.aiCaption)
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, AISpacing.sm)
                    .padding(.vertical, AISpacing.xs)
                    .background(
                        Capsule()
                            .fill(Color.secondary.opacity(0.15))
                    )
            }
            
            // State-specific content
            stateContent
        }
        .padding(AISpacing.md)
        .background(
            RoundedRectangle(cornerRadius: AIRadius.lg)
                .fill(colorScheme == .dark 
                      ? Color(white: 0.1) 
                      : Color(white: 0.98))
                .stroke(strokeColor, lineWidth: 1)
        )
    }
    
    // -------------------------------------------------------------------------
    // MARK: - Model Icon
    // -------------------------------------------------------------------------
    
    @ViewBuilder
    private var modelIcon: some View {
        ZStack {
            RoundedRectangle(cornerRadius: AIRadius.md)
                .fill(iconBackgroundColor)
                .frame(width: 48, height: 48)
            
            Group {
                switch state {
                case .notLoaded:
                    Image(systemName: "arrow.down.circle")
                case .downloading:
                    ProgressView()
                        .tint(.white)
                case .loading:
                    ProgressView()
                        .tint(.white)
                case .ready:
                    Image(systemName: "checkmark.circle.fill")
                case .error:
                    Image(systemName: "exclamationmark.circle.fill")
                }
            }
            .font(.system(size: 20, weight: .medium))
            .foregroundStyle(.white)
        }
    }
    
    private var iconBackgroundColor: Color {
        switch state {
        case .notLoaded:
            return .secondary
        case .downloading, .loading:
            return Color.aiWarning
        case .ready:
            return Color.aiSuccess
        case .error:
            return Color.aiError
        }
    }
    
    private var strokeColor: Color {
        switch state {
        case .notLoaded:
            return Color.secondary.opacity(0.2)
        case .downloading, .loading:
            return Color.aiWarning.opacity(0.3)
        case .ready:
            return Color.aiSuccess.opacity(0.3)
        case .error:
            return Color.aiError.opacity(0.3)
        }
    }
    
    // -------------------------------------------------------------------------
    // MARK: - State Content
    // -------------------------------------------------------------------------
    
    @ViewBuilder
    private var stateContent: some View {
        switch state {
        case .notLoaded:
            notLoadedContent
            
        case .downloading(let progress):
            downloadingContent(progress: progress)
            
        case .loading:
            loadingContent
            
        case .ready:
            readyContent
            
        case .error(let message):
            errorContent(message: message)
        }
    }
    
    // Not loaded state
    private var notLoadedContent: some View {
        Button(action: onLoad) {
            HStack {
                Image(systemName: "arrow.down.circle.fill")
                Text("Download Model")
            }
            .frame(maxWidth: .infinity)
        }
        .buttonStyle(.aiPrimary)
    }
    
    // Downloading state with progress
    private func downloadingContent(progress: Double) -> some View {
        VStack(alignment: .leading, spacing: AISpacing.sm) {
            // Progress bar
            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    // Background
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.secondary.opacity(0.2))
                        .frame(height: 8)
                    
                    // Progress fill
                    RoundedRectangle(cornerRadius: 4)
                        .fill(Color.aiPrimary)
                        .frame(width: max(0, geometry.size.width * CGFloat(progress)), height: 8)
                        .animation(.linear(duration: 0.2), value: progress)
                }
            }
            .frame(height: 8)
            
            // Progress text
            HStack {
                Text("Downloading...")
                    .font(.aiBodySmall)
                    .foregroundStyle(.secondary)
                
                Spacer()
                
                Text("\(Int(progress * 100))%")
                    .font(.aiMono)
                    .foregroundStyle(.primary)
            }
        }
    }
    
    // Loading into memory state
    private var loadingContent: some View {
        HStack(spacing: AISpacing.sm) {
            ProgressView()
                .scaleEffect(0.8)
            
            Text("Loading model into memory...")
                .font(.aiBodySmall)
                .foregroundStyle(.secondary)
            
            Spacer()
        }
    }
    
    // Ready state
    private var readyContent: some View {
        HStack(spacing: AISpacing.sm) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(Color.aiSuccess)
            
            Text("Model ready")
                .font(.aiBodySmall)
                .foregroundStyle(Color.aiSuccess)
            
            Spacer()
        }
    }
    
    // Error state with retry
    private func errorContent(message: String) -> some View {
        VStack(alignment: .leading, spacing: AISpacing.sm) {
            HStack(spacing: AISpacing.sm) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundStyle(Color.aiError)
                
                Text(message)
                    .font(.aiBodySmall)
                    .foregroundStyle(Color.aiError)
                    .lineLimit(2)
            }
            
            Button(action: onRetry) {
                HStack {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.aiSecondary)
        }
    }
}

// =============================================================================
// MARK: - Compact Model Loader
// =============================================================================
/// A compact version of the model loader for inline use.
// =============================================================================
struct CompactModelLoader: View {
    let modelName: String
    let state: ModelState
    let onLoad: () -> Void
    
    var body: some View {
        HStack(spacing: AISpacing.sm) {
            // Status icon
            Image(systemName: state.statusIcon)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(state.statusColor)
            
            // Model name
            Text(modelName)
                .font(.aiBodySmall)
                .foregroundStyle(.primary)
            
            Spacer()
            
            // Action or status
            switch state {
            case .notLoaded:
                Button("Load", action: onLoad)
                    .font(.aiCaption)
                    .foregroundStyle(Color.aiPrimary)
                
            case .downloading(let progress):
                Text("\(Int(progress * 100))%")
                    .font(.aiMono)
                    .foregroundStyle(.secondary)
                
            case .loading:
                ProgressView()
                    .scaleEffect(0.6)
                
            case .ready:
                Text("Ready")
                    .font(.aiCaption)
                    .foregroundStyle(Color.aiSuccess)
                
            case .error:
                Button("Retry", action: onLoad)
                    .font(.aiCaption)
                    .foregroundStyle(Color.aiError)
            }
        }
        .padding(AISpacing.sm)
        .background(
            RoundedRectangle(cornerRadius: AIRadius.sm)
                .fill(Color.secondary.opacity(0.1))
        )
    }
}

// =============================================================================
// MARK: - Multi-Model Loader
// =============================================================================
/// Displays loading status for multiple models at once.
// =============================================================================
struct MultiModelLoader: View {
    let title: String
    let models: [(name: String, state: ModelState)]
    let onLoadAll: () -> Void
    
    var allReady: Bool {
        models.allSatisfy { $0.state.isReady }
    }
    
    var anyLoading: Bool {
        models.contains { $0.state.isLoading }
    }
    
    var body: some View {
        VStack(alignment: .leading, spacing: AISpacing.md) {
            // Header
            HStack {
                Text(title)
                    .font(.aiHeadingSmall)
                
                Spacer()
                
                if allReady {
                    AIStatusBadge(status: .ready, text: "All Ready")
                } else if anyLoading {
                    AIStatusBadge(status: .loading, text: "Loading...")
                }
            }
            
            // Model list
            VStack(spacing: AISpacing.sm) {
                ForEach(models, id: \.name) { model in
                    HStack(spacing: AISpacing.sm) {
                        Circle()
                            .fill(model.state.statusColor)
                            .frame(width: 8, height: 8)
                        
                        Text(model.name)
                            .font(.aiBodySmall)
                        
                        Spacer()
                        
                        Text(model.state.statusText)
                            .font(.aiCaption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            
            // Load all button (if not all ready)
            if !allReady && !anyLoading {
                Button(action: onLoadAll) {
                    HStack {
                        Image(systemName: "arrow.down.circle.fill")
                        Text("Load All Models")
                    }
                    .frame(maxWidth: .infinity)
                }
                .buttonStyle(.aiPrimary)
            }
        }
        .padding(AISpacing.md)
        .aiCardStyle()
    }
}

// =============================================================================
// MARK: - Previews
// =============================================================================
#Preview("Model Loader - States") {
    ScrollView {
        VStack(spacing: AISpacing.lg) {
            ModelLoaderView(
                modelName: "SmolLM2 360M",
                modelDescription: "Compact language model for on-device text generation",
                modelSize: "~400MB",
                state: .notLoaded,
                onLoad: {},
                onRetry: {}
            )
            
            ModelLoaderView(
                modelName: "Whisper Tiny",
                modelDescription: "Fast speech-to-text transcription",
                modelSize: "~75MB",
                state: .downloading(progress: 0.65),
                onLoad: {},
                onRetry: {}
            )
            
            ModelLoaderView(
                modelName: "Piper TTS",
                modelDescription: "Natural voice synthesis",
                modelSize: "~65MB",
                state: .loading,
                onLoad: {},
                onRetry: {}
            )
            
            ModelLoaderView(
                modelName: "Piper TTS",
                modelDescription: "Natural voice synthesis",
                modelSize: "~65MB",
                state: .ready,
                onLoad: {},
                onRetry: {}
            )
            
            ModelLoaderView(
                modelName: "Large Model",
                modelDescription: "Something went wrong",
                modelSize: "~1GB",
                state: .error(message: "Network connection lost"),
                onLoad: {},
                onRetry: {}
            )
        }
        .padding()
    }
}

#Preview("Compact Loader") {
    VStack(spacing: AISpacing.sm) {
        CompactModelLoader(modelName: "LLM", state: .ready, onLoad: {})
        CompactModelLoader(modelName: "STT", state: .downloading(progress: 0.5), onLoad: {})
        CompactModelLoader(modelName: "TTS", state: .notLoaded, onLoad: {})
    }
    .padding()
}

#Preview("Multi-Model Loader") {
    MultiModelLoader(
        title: "Required Models",
        models: [
            ("LLM - SmolLM2", .ready),
            ("STT - Whisper", .downloading(progress: 0.7)),
            ("TTS - Piper", .notLoaded)
        ],
        onLoadAll: {}
    )
    .padding()
}
