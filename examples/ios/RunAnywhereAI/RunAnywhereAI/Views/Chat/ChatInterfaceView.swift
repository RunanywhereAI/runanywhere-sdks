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
    @State private var showingNoModelAlert = false
    @State private var showingConversationList = false
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
                    .onTapGesture {
                        isTextFieldFocused = false
                    }
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
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(action: { showingConversationList = true }) {
                        Image(systemName: "sidebar.left")
                    }
                }
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(action: { showingSettings = true }) {
                        Image(systemName: "gear")
                    }
                }
            }
            .onTapGesture {
                isTextFieldFocused = false
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
            .alert("No Model Selected", isPresented: $showingNoModelAlert) {
                Button("Select Model") {
                    showingModelPicker = true
                }
                Button("Cancel", role: .cancel) {}
            } message: {
                Text("Please select a \(viewModel.selectedFramework.displayName) model to start chatting.")
            }
            .sheet(isPresented: $showingConversationList) {
                ConversationListView()
            }
        }
    }

    // MARK: - Subviews

    private var frameworkSelectorBar: some View {
        VStack(spacing: 12) {
            // Model selection section
            VStack(spacing: 8) {
                // Current model display
                if let model = viewModel.selectedModel {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            Text("Current Model")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                            Text(model.name)
                                .font(.headline)
                                .foregroundColor(.primary)
                                .lineLimit(1)
                        }
                        
                        Spacer()
                        
                        // Model info
                        HStack(spacing: 12) {
                            if let quantization = model.quantization {
                                Text(quantization)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 4)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .cornerRadius(6)
                            }
                            
                            Text(model.displaySize)
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    .padding(.horizontal)
                    .padding(.vertical, 8)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                } else {
                    // No model selected prompt
                    VStack(spacing: 4) {
                        Text("No Model Selected")
                            .font(.headline)
                            .foregroundColor(.secondary)
                        Text("Tap below to select a model")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color(.systemGray6))
                    .cornerRadius(10)
                }
                
                // Selection buttons
                HStack(spacing: 8) {
                    // Framework selector
                    Button(action: { showingFrameworkPicker = true }) {
                        HStack {
                            Image(systemName: frameworkIcon(for: viewModel.selectedFramework))
                            Text(viewModel.selectedFramework.displayName)
                            Image(systemName: "chevron.down")
                        }
                        .font(.subheadline)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                    
                    // Model selector
                    Button(action: { showingModelPicker = true }) {
                        HStack {
                            Image(systemName: "cube.box.fill")
                            Text("Select Model")
                            Image(systemName: "chevron.right")
                        }
                        .font(.subheadline)
                        .foregroundColor(viewModel.selectedModel == nil ? .white : .accentColor)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(viewModel.selectedModel == nil ? Color.accentColor : Color(.tertiarySystemBackground))
                        .cornerRadius(8)
                    }
                    .disabled(viewModel.isGenerating)
                }
            }
            .padding(.horizontal)
            
            // Performance metrics bar
            if viewModel.isGenerating {
                HStack {
                    HStack(spacing: 8) {
                        ProgressView()
                            .scaleEffect(0.7)
                        Text("Generating...")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                    
                    if let tokensPerSecond = viewModel.currentTokensPerSecond {
                        Label("\(String(format: "%.1f", tokensPerSecond)) tokens/s", systemImage: "speedometer")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                .padding(.horizontal)
            }
            
            // Model loading indicator
            if viewModel.isLoadingModel {
                HStack(spacing: 8) {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text(viewModel.modelLoadingProgress)
                        .font(.caption)
                        .foregroundColor(.secondary)
                    Spacer()
                }
                .padding(.horizontal)
                .padding(.vertical, 8)
                .background(Color.orange.opacity(0.1))
                .cornerRadius(8)
                .padding(.horizontal)
            }
        }
        .padding(.vertical, 8)
        .background(Color(.secondarySystemBackground))
    }
    
    private func frameworkIcon(for framework: LLMFramework) -> String {
        switch framework {
        case .coreML: return "brain.head.profile"
        case .mlx: return "cube.fill"
        case .onnxRuntime: return "cpu.fill"
        case .tensorFlowLite: return "network"
        case .foundationModels: return "star.fill"
        default: return "cpu"
        }
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
                .toolbar {
                    ToolbarItemGroup(placement: .keyboard) {
                        Spacer()
                        Button("Done") {
                            isTextFieldFocused = false
                        }
                    }
                }

            // Send button
            Button(action: sendMessage) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.system(size: 32))
                    .foregroundColor(messageText.isEmpty ? .gray : .accentColor)
            }
            .disabled(messageText.isEmpty || viewModel.isGenerating || viewModel.isLoadingModel)
        }
        .padding()
        .background(Color(.secondarySystemBackground))
    }

    // MARK: - Actions

    private func sendMessage() {
        guard !messageText.isEmpty else { return }
        
        // Check if a model is selected
        guard viewModel.selectedModel != nil else {
            showingNoModelAlert = true
            return
        }

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
                    VStack(alignment: .leading, spacing: 4) {
                        // Model info section
                        if let modelName = message.modelName {
                            Button(action: {
                                onModelInfoTap(message)
                            }) {
                                HStack(spacing: 6) {
                                    Image(systemName: "cube.box.fill")
                                        .font(.system(size: 10))
                                        .foregroundColor(.accentColor)
                                    
                                    Text(modelName)
                                        .font(.caption)
                                        .fontWeight(.medium)
                                        .foregroundColor(.accentColor)
                                        .lineLimit(1)
                                    
                                    Image(systemName: "chevron.right")
                                        .font(.system(size: 8))
                                        .foregroundColor(.accentColor.opacity(0.7))
                                }
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(Color.accentColor.opacity(0.1))
                                .cornerRadius(6)
                            }
                            .buttonStyle(PlainButtonStyle())
                        }
                        
                        // Performance metrics
                        if let metrics = message.generationMetrics as? EnhancedGenerationMetrics {
                            HStack(spacing: 8) {
                                Label("\(metrics.tokenCount) tokens", systemImage: "text.word.spacing")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                Label("\(String(format: "%.1f", metrics.tokensPerSecond)) t/s", systemImage: "speedometer")
                                    .font(.caption2)
                                    .foregroundColor(.secondary)
                                
                                if metrics.totalTime > 0 {
                                    Label("\(String(format: "%.1fs", metrics.totalTime))", systemImage: "clock")
                                        .font(.caption2)
                                        .foregroundColor(.secondary)
                                }
                            }
                        }
                    }
                }
                
                Text(message.timestamp.formatted(date: .omitted, time: .shortened))
                    .font(.caption2)
                    .foregroundColor(.secondary)
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
        
        // Get all models for this framework
        var allModels: [ModelInfo] = []
        
        // First, get downloaded models
        let frameworkDownloaded = modelManager.downloadedModels.filter { $0.framework == framework }
        
        // Also check available models that are downloaded
        let availableDownloaded = modelManager.availableModels.filter { model in
            model.framework == framework && 
            modelManager.isModelDownloaded(model.name, framework: framework)
        }
        
        // Combine both sources
        allModels = frameworkDownloaded + availableDownloaded
        
        // Remove duplicates based on name similarity
        var uniqueModels: [ModelInfo] = []
        var seenNames: Set<String> = []
        
        for model in allModels {
            let normalizedName = normalizeModelName(model.name)
            if !seenNames.contains(normalizedName) {
                seenNames.insert(normalizedName)
                uniqueModels.append(model)
            }
        }
        
        // Filter for chat-compatible models only
        downloadedModels = uniqueModels.filter { model in
            isChatCompatibleModel(model)
        }
        
        // DEBUG: Log what we found
        print("Downloaded models for \(framework.displayName): \(downloadedModels.map { $0.name })")
        print("Filtered out non-chat models: \(uniqueModels.filter { !isChatCompatibleModel($0) }.map { $0.name })")
    }
    
    private func normalizeModelName(_ name: String) -> String {
        // Normalize model names to detect duplicates
        return name.lowercased()
            .replacingOccurrences(of: "quantized-", with: "")
            .replacingOccurrences(of: "-4bit", with: "")
            .replacingOccurrences(of: "_4bit", with: "")
            .replacingOccurrences(of: "-it", with: "")
            .replacingOccurrences(of: ".mlpackage", with: "")
            .replacingOccurrences(of: ".gguf", with: "")
            .replacingOccurrences(of: ".onnx", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
    }
    
    private func isChatCompatibleModel(_ model: ModelInfo) -> Bool {
        // Use the model type to determine if it's compatible with chat
        return model.modelType?.supportedInChat ?? true
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
        Group {
            if downloadedModels.isEmpty {
                VStack(spacing: 20) {
                    ContentUnavailableView(
                        "No Models Available",
                        systemImage: "cube.box",
                        description: Text("You need to download \(framework.displayName) models to start chatting")
                    )
                    
                    Button(action: {
                        // Dismiss the sheet and switch to Models tab
                        dismiss()
                        NotificationCenter.default.post(name: Notification.Name("SwitchToModelsTab"), object: nil)
                    }) {
                        Label("Go to Models", systemImage: "arrow.right.circle.fill")
                            .font(.headline)
                            .foregroundColor(.white)
                            .padding(.horizontal, 24)
                            .padding(.vertical, 12)
                            .background(Color.accentColor)
                            .cornerRadius(10)
                    }
                }
            } else {
                ScrollView {
                    VStack(spacing: 16) {
                        // Show a help message if only non-chat models are available
                        let nonChatModels = modelManager.downloadedModels.filter { model in
                            model.framework == framework && !isChatCompatibleModel(model)
                        }
                        
                        if !nonChatModels.isEmpty && downloadedModels.isEmpty {
                            VStack(spacing: 8) {
                                Image(systemName: "info.circle.fill")
                                    .font(.largeTitle)
                                    .foregroundColor(.orange)
                                
                                Text("No Chat Models Available")
                                    .font(.headline)
                                
                                Text("You have \(nonChatModels.count) model(s) downloaded, but they are not suitable for text chat:")
                                    .font(.caption)
                                    .multilineTextAlignment(.center)
                                    .foregroundColor(.secondary)
                                    .padding(.horizontal)
                                
                                VStack(alignment: .leading, spacing: 2) {
                                    ForEach(nonChatModels.prefix(3), id: \.id) { model in
                                        Text("• \(model.name)")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                    if nonChatModels.count > 3 {
                                        Text("• and \(nonChatModels.count - 3) more...")
                                            .font(.caption2)
                                            .foregroundColor(.secondary)
                                    }
                                }
                                .padding(.vertical, 4)
                                
                                Text("For chat, please download one of these \(framework.displayName) models:")
                                    .font(.caption)
                                    .fontWeight(.medium)
                                    .foregroundColor(.secondary)
                                    .padding(.top, 4)
                                
                                VStack(alignment: .leading, spacing: 4) {
                                    if framework == .coreML {
                                        Text("• GPT2-CoreML.mlpackage (548MB)")
                                        Text("• DistilGPT2-CoreML.mlpackage (267MB)")
                                        Text("• OpenELM-270M.mlpackage (312MB)")
                                    } else if framework == .mlx {
                                        Text("• Mistral-7B-Instruct (4-bit)")
                                        Text("• Phi-2 MLX")
                                        Text("• Gemma-2B (4-bit)")
                                    } else if framework == .onnxRuntime {
                                        Text("• Phi-3-mini ONNX")
                                        Text("• Llama-2-7B ONNX")
                                        Text("• GPT2 ONNX")
                                    }
                                }
                                .font(.caption)
                                .foregroundColor(.secondary)
                            }
                            .padding()
                            .background(Color.orange.opacity(0.1))
                            .cornerRadius(12)
                        }
                        
                        ForEach(downloadedModels) { model in
                            downloadedModelCard(model)
                        }
                    }
                    .padding()
                }
                .background(Color(.systemGroupedBackground))
            }
        }
    }

    private func downloadedModelCard(_ model: ModelInfo) -> some View {
        Button(action: {
            selectedModel = model
            dismiss()
        }) {
            VStack(alignment: .leading, spacing: 0) {
                // Selected indicator
                if model.id == selectedModel?.id {
                    HStack {
                        Label("Currently Selected", systemImage: "checkmark.circle.fill")
                            .font(.caption)
                            .foregroundColor(.white)
                        Spacer()
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color.accentColor)
                }
                
                HStack {
                    // Model icon
                    ZStack {
                        Circle()
                            .fill(model.id == selectedModel?.id ? Color.accentColor.opacity(0.2) : Color(.systemGray5))
                            .frame(width: 50, height: 50)
                        
                        Image(systemName: "cube.box.fill")
                            .font(.title2)
                            .foregroundColor(model.id == selectedModel?.id ? .accentColor : .secondary)
                    }
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Text(model.name)
                            .font(.headline)
                            .foregroundColor(.primary)
                            .lineLimit(2)
                            .multilineTextAlignment(.leading)

                        HStack(spacing: 12) {
                            // Size
                            HStack(spacing: 4) {
                                Image(systemName: "internaldrive")
                                    .font(.caption2)
                                Text(model.displaySize)
                                    .font(.caption)
                            }
                            .foregroundColor(.secondary)
                            
                            // Quantization
                            if let quantization = model.quantization {
                                Text(quantization)
                                    .font(.caption)
                                    .padding(.horizontal, 8)
                                    .padding(.vertical, 2)
                                    .background(Color(.tertiarySystemGroupedBackground))
                                    .cornerRadius(4)
                            }
                        }
                        
                        // Additional info
                        if let contextLength = model.contextLength {
                            Label("\(contextLength) token context", systemImage: "text.alignleft")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                        }
                        
                        // Downloaded file name if available
                        if let fileName = model.downloadedFileName {
                            Label(fileName, systemImage: "doc")
                                .font(.caption2)
                                .foregroundColor(.secondary)
                                .lineLimit(1)
                        }
                    }

                    Spacer()
                    
                    // Selection indicator
                    Image(systemName: model.id == selectedModel?.id ? "checkmark.circle.fill" : "circle")
                        .font(.title2)
                        .foregroundColor(model.id == selectedModel?.id ? .accentColor : .secondary)
                }
                .padding()
            }
            .background(Color(.secondarySystemBackground))
            .cornerRadius(12)
            .overlay(
                RoundedRectangle(cornerRadius: 12)
                    .stroke(model.id == selectedModel?.id ? Color.accentColor : Color.clear, lineWidth: 2)
            )
        }
        .buttonStyle(PlainButtonStyle())
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
