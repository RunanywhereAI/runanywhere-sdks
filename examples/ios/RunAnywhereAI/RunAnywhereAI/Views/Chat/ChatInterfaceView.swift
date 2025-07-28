//
//  ChatInterfaceView.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import SwiftUI

struct ChatInterfaceView: View {
    @StateObject private var viewModel = ChatViewModelEnhanced()
    @State private var messageText = ""
    @State private var showingFrameworkPicker = false
    @State private var showingModelPicker = false
    @State private var showingSettings = false
    @State private var selectedMessageForModelInfo: ChatMessage?
    @FocusState private var isTextFieldFocused: Bool

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                // Framework selector bar
                frameworkSelectorBar

                // Chat messages
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            ForEach(viewModel.messages) { message in
                                MessageBubbleView(
                                    message: message,
                                    onModelInfoTap: { msg in
                                        selectedMessageForModelInfo = msg
                                    }
                                )
                                .id(message.id)
                            }

                            if viewModel.isGenerating {
                                TypingIndicatorView()
                                    .id("typing")
                            }
                        }
                        .padding()
                    }
                    .background(Color(.systemGroupedBackground))
                    .onChange(of: viewModel.messages.count) { _ in
                        withAnimation {
                            if let lastMessage = viewModel.messages.last {
                                proxy.scrollTo(lastMessage.id, anchor: .bottom)
                            } else {
                                proxy.scrollTo("typing", anchor: .bottom)
                            }
                        }
                    }
                }

                // Input area
                inputArea
            }
            .navigationTitle("LLM Chat")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .sheet(isPresented: $showingFrameworkPicker) {
                FrameworkPickerView(selectedFramework: $viewModel.selectedFramework)
            }
            .sheet(isPresented: $showingModelPicker) {
                ModelPickerView(
                    selectedModel: $viewModel.selectedModel,
                    framework: viewModel.selectedFramework
                )
            }
            .sheet(isPresented: $showingSettings) {
                ChatSettingsView(settings: $viewModel.settings)
            }
            .sheet(item: $selectedMessageForModelInfo) { message in
                if let modelInfo = message.modelInfo {
                    NavigationView {
                        UnifiedModelDetailsView(
                            model: modelInfo,
                            onDownload: { _ in }
                        )
                        .toolbar {
                            ToolbarItem(placement: .navigationBarTrailing) {
                                Button("Done") {
                                    selectedMessageForModelInfo = nil
                                }
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var frameworkSelectorBar: some View {
        HStack {
            // Framework button
            Button(action: { showingFrameworkPicker = true }) {
                HStack {
                    Image(systemName: "cpu")
                    Text(viewModel.selectedFramework.displayName)
                    Image(systemName: "chevron.down")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }

            // Model button
            Button(action: { showingModelPicker = true }) {
                HStack {
                    Image(systemName: "doc.text")
                    Text(viewModel.selectedModel?.name ?? "Select Model")
                    Image(systemName: "chevron.down")
                }
                .font(.caption)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(8)
            }

            Spacer()

            // Performance metrics
            if viewModel.isGenerating {
                HStack(spacing: 8) {
                    if let tokensPerSecond = viewModel.currentTokensPerSecond {
                        Label("\(String(format: "%.1f", tokensPerSecond)) t/s", systemImage: "speedometer")
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }

                    ProgressView()
                        .scaleEffect(0.8)
                }
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }

    private var inputArea: some View {
        HStack(alignment: .bottom, spacing: 8) {
            // Text field
            TextField("Type a message...", text: $messageText, axis: .vertical)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color(.tertiarySystemBackground))
                .cornerRadius(20)
                .focused($isTextFieldFocused)
                .onSubmit {
                    sendMessage()
                }

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.isEmpty ? .gray : .accentColor)
            }
            .disabled(messageText.isEmpty || viewModel.isGenerating)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty else { return }

        let text = messageText
        messageText = ""

        Task {
            viewModel.currentInput = text
            await viewModel.sendMessage()
        }
    }
}

// MARK: - Message Bubble View

struct MessageBubbleView: View {
    let message: ChatMessage
    let onModelInfoTap: (ChatMessage) -> Void

    var body: some View {
        HStack {
            if message.role == .user {
                Spacer()
            }

            VStack(alignment: message.role == .user ? .trailing : .leading, spacing: 4) {
                // Message content
                Text(message.content)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(message.role == .user ? Color.accentColor : Color(.tertiarySystemBackground))
                    .foregroundColor(message.role == .user ? .white : .primary)
                    .cornerRadius(16)

                // Metadata
                if message.role == .assistant {
                    HStack(spacing: 6) {
                        // Model info button
                        if let modelName = message.modelName {
                            Button(action: {
                                onModelInfoTap(message)
                            }) {
                                HStack(spacing: 4) {
                                    Image(systemName: "info.circle")
                                        .font(.caption2)
                                    Text(modelName)
                                        .font(.caption2)
                                        .lineLimit(1)
                                }
                                .foregroundColor(.blue)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        if let metrics = message.generationMetrics as? EnhancedGenerationMetrics {
                            Text("•")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                            
                            Text("\(metrics.tokenCount) tokens")
                                .font(.caption2)
                                .foregroundColor(.secondary)

                            Text("•")
                                .foregroundColor(.secondary)
                                .font(.caption2)
                            
                            Text("\(String(format: "%.1f", metrics.tokensPerSecond)) t/s")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        Spacer()
                        
                        Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                            .font(.caption2)
                            .foregroundColor(.secondary)
                    }
                }
            }
            .frame(maxWidth: UIScreen.main.bounds.width * 0.75, alignment: message.role == .user ? .trailing : .leading)

            if message.role == .assistant {
                Spacer()
            }
        }
    }
}

// MARK: - Typing Indicator

struct TypingIndicatorView: View {
    @State private var animating = false

    var body: some View {
        HStack {
            HStack(spacing: 4) {
                ForEach(0..<3) { index in
                    Circle()
                        .fill(Color.secondary)
                        .frame(width: 8, height: 8)
                        .scaleEffect(animating ? 1.0 : 0.5)
                        .animation(
                            Animation.easeInOut(duration: 0.6)
                                .repeatForever()
                                .delay(Double(index) * 0.2),
                            value: animating
                        )
                }
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(Color(.tertiarySystemBackground))
            .cornerRadius(16)

            Spacer()
        }
        .onAppear {
            animating = true
        }
    }
}

// MARK: - Framework Picker

struct FrameworkPickerView: View {
    @Binding var selectedFramework: LLMFramework
    @Environment(\.dismiss) private var dismiss
    @StateObject private var compatibility = ModelCompatibilityMatrix.shared

    var body: some View {
        navigationWrapper
    }

    private var navigationWrapper: some View {
        NavigationView {
            frameworkList
                .navigationTitle("Select Framework")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }

    private var frameworkList: some View {
        List {
            ForEach(Array(LLMFramework.allCases), id: \.self) { framework in
                frameworkButton(framework)
            }
        }
    }

    private func frameworkButton(_ framework: LLMFramework) -> some View {
        Button(action: {
            if !framework.isDeferred {
                selectedFramework = framework
                dismiss()
            }
        }) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(framework.displayName)
                        .foregroundColor(framework.isDeferred ? .secondary : .primary)
                    if framework.isDeferred {
                        Text("Coming Soon")
                            .font(.caption)
                            .foregroundColor(.orange)
                    }
                }

                Spacer()

                if framework == selectedFramework && !framework.isDeferred {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                } else if framework.isDeferred {
                    Image(systemName: "clock.badge.exclamationmark")
                        .foregroundColor(.orange)
                        .font(.caption)
                }
            }
            .padding(.vertical, 4)
        }
        .disabled(framework.isDeferred)
    }
}

// MARK: - Model Picker

struct ModelPickerView: View {
    @Binding var selectedModel: ModelInfo?
    let framework: LLMFramework
    @Environment(\.dismiss) private var dismiss
    @StateObject private var modelManager = ModelManager.shared
    @State private var downloadedModels: [ModelInfo] = []

    var body: some View {
        modelNavigationView
            .task {
                await loadModels()
            }
    }
    
    private func loadModels() async {
        await modelManager.refreshModelList()
        
        // Filter models for the selected framework
        downloadedModels = modelManager.downloadedModels.filter { model in
            model.framework == framework
        }
        
        // Also include available models that are downloaded
        let availableDownloaded = modelManager.availableModels.filter { model in
            model.framework == framework && modelManager.isModelDownloaded(model.name, framework: framework)
        }
        
        // Merge and deduplicate
        for model in availableDownloaded {
            if !downloadedModels.contains(where: { $0.name == model.name }) {
                downloadedModels.append(model)
            }
        }
    }

    private var modelNavigationView: some View {
        NavigationView {
            modelList
                .navigationTitle("Select \(framework.displayName) Model")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .navigationBarTrailing) {
                        Button("Done") {
                            dismiss()
                        }
                    }
                }
        }
    }

    private var modelList: some View {
        List {
            if downloadedModels.isEmpty {
                ContentUnavailableView(
                    "No Models Available",
                    systemImage: "doc.badge.arrow.up",
                    description: Text("Download \(framework.displayName) models from the Models tab")
                )
            } else {
                ForEach(downloadedModels) { model in
                    downloadedModelButton(model)
                }
            }
        }
    }

    private func downloadedModelButton(_ model: ModelInfo) -> some View {
        Button(action: {
            selectedModel = model
            dismiss()
        }) {
            HStack {
                // Model icon
                Image(systemName: "doc.text.fill")
                    .font(.title3)
                    .foregroundColor(.blue)
                    .frame(width: 40)
                
                VStack(alignment: .leading, spacing: 4) {
                    Text(model.name)
                        .foregroundColor(.primary)
                        .lineLimit(1)

                    HStack(spacing: 8) {
                        // Size
                        Label(model.displaySize, systemImage: "internaldrive")
                            .font(.caption)
                            .foregroundColor(.secondary)
                        
                        // Quantization
                        if let quantization = model.quantization {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text(quantization)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                        
                        // Context length
                        if let contextLength = model.contextLength {
                            Text("•")
                                .foregroundColor(.secondary)
                            Text("\(contextLength) ctx")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                }

                Spacer()

                if model.id == selectedModel?.id {
                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(.accentColor)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

// MARK: - Chat Settings

struct ChatSettingsView: View {
    @Binding var settings: ChatSettings
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationView {
            Form {
                Section("Generation") {
                    HStack {
                        Text("Max Tokens")
                        Spacer()
                        TextField("", value: $settings.maxTokens, format: .number)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 80)
                            .multilineTextAlignment(.trailing)
                    }

                    VStack(alignment: .leading) {
                        Text("Temperature: \(String(format: "%.2f", settings.temperature))")
                        Slider(value: $settings.temperature, in: 0...2, step: 0.1)
                    }

                    Toggle("Stream Responses", isOn: $settings.streamResponses)
                }

                Section("Performance") {
                    Toggle("Show Metrics", isOn: $settings.showMetrics)
                    Toggle("Enable Profiling", isOn: $settings.enableProfiling)
                }
            }
            .navigationTitle("Chat Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("Done") {
                        dismiss()
                    }
                }
            }
        }
    }
}
