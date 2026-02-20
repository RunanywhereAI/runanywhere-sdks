//
//  DocumentRAGView.swift
//  RunAnywhereAI
//
//  SwiftUI view for the RAG document Q&A feature.
//  Handles model selection, document picking, loading state, and Q&A chat interface.
//

import SwiftUI
import UniformTypeIdentifiers
import RunAnywhere

// MARK: - Document RAG View

struct DocumentRAGView: View {
    @State private var viewModel = RAGViewModel()
    @State private var isShowingFilePicker = false
    @State private var isShowingEmbeddingModelPicker = false
    @State private var isShowingLLMModelPicker = false
    @State private var isErrorBannerVisible = false
    @State private var selectedEmbeddingModel: ModelInfo?
    @State private var selectedLLMModel: ModelInfo?
    @FocusState private var isInputFocused: Bool

    private var areModelsReady: Bool {
        selectedEmbeddingModel?.localPath != nil && selectedLLMModel?.localPath != nil
    }

    /// Resolve the actual embedding model file path.
    ///
    /// Multi-file models (like all-minilm-l6-v2) set localPath to the folder after download.
    /// In that case we return the path to model.onnx inside that folder.
    private func resolveEmbeddingFilePath(localPath: URL) -> String {
        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: localPath.path, isDirectory: &isDir), isDir.boolValue {
            return localPath.appendingPathComponent("model.onnx").path
        }
        return localPath.path
    }

    /// Resolve the actual LLM model file path.
    ///
    /// Single-file LlamaCpp models are stored inside a directory named after the model ID.
    /// In that case we return the path to the first `.gguf` file found in the directory.
    private func resolveLLMFilePath(localPath: URL) -> String {
        var isDir: ObjCBool = false
        guard FileManager.default.fileExists(atPath: localPath.path, isDirectory: &isDir),
              isDir.boolValue else {
            return localPath.path
        }
        let ggufFile = (try? FileManager.default.contentsOfDirectory(at: localPath, includingPropertiesForKeys: nil))?
            .first { $0.pathExtension.lowercased() == "gguf" }
        return ggufFile?.path ?? localPath.path
    }

    /// Resolve the vocab file path for the embedding model.
    ///
    /// Multi-file embedding models (localPath = folder) have vocab.txt directly inside
    /// the folder. Single-file models fall back to the sibling-file convention.
    private func resolveVocabPath(for embeddingModel: ModelInfo) -> String? {
        guard let embeddingPath = embeddingModel.localPath else { return nil }

        var isDir: ObjCBool = false
        if FileManager.default.fileExists(atPath: embeddingPath.path, isDirectory: &isDir), isDir.boolValue {
            // Multi-file model: vocab.txt is in the same folder as model.onnx
            return embeddingPath.appendingPathComponent("vocab.txt").path
        }

        // Single-file model: vocab.txt is a sibling of the model file
        return embeddingPath.deletingLastPathComponent().appendingPathComponent("vocab.txt").path
    }

    private var ragConfig: RAGConfiguration? {
        guard
            let embeddingModel = selectedEmbeddingModel,
            let embeddingLocalPath = embeddingModel.localPath,
            let llmLocalPath = selectedLLMModel?.localPath
        else { return nil }

        // embeddingConfigJSON is set asynchronously via loadDocument(url:config:) after
        // vocab path is resolved. Here we build the base config; vocab is injected by the
        // ViewModel when it calls loadDocument.
        return RAGConfiguration(
            embeddingModelPath: resolveEmbeddingFilePath(localPath: embeddingLocalPath),
            llmModelPath: resolveLLMFilePath(localPath: llmLocalPath)
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                modelSetupSection
                documentStatusBar
                errorBanner
                messagesArea
                inputBar
            }
            .background(AppColors.backgroundGrouped)
            .navigationTitle("Document Q&A")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
        }
        #if os(iOS)
        .navigationViewStyle(.stack)
        #endif
        .fileImporter(
            isPresented: $isShowingFilePicker,
            allowedContentTypes: [.pdf, .json],
            allowsMultipleSelection: false
        ) { result in
            handleFileImport(result)
        }
        .adaptiveSheet(isPresented: $isShowingEmbeddingModelPicker) {
            ModelSelectionSheet(context: .ragEmbedding) { model in
                selectedEmbeddingModel = model
            }
        }
        .adaptiveSheet(isPresented: $isShowingLLMModelPicker) {
            ModelSelectionSheet(context: .ragLLM) { model in
                selectedLLMModel = model
            }
        }
        .onChange(of: viewModel.error != nil) { _, hasError in
            withAnimation {
                isErrorBannerVisible = hasError
            }
        }
    }
}

// MARK: - Model Setup Section

extension DocumentRAGView {
    @ViewBuilder
    private var modelSetupSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppSpacing.smallMedium) {
                modelPickerRow(
                    label: "Embedding Model",
                    systemImage: "brain",
                    model: selectedEmbeddingModel,
                    action: { isShowingEmbeddingModelPicker = true }
                )
                modelPickerRow(
                    label: "LLM Model",
                    systemImage: "text.bubble",
                    model: selectedLLMModel,
                    action: { isShowingLLMModelPicker = true }
                )
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.mediumLarge)
            Divider()
        }
        .background(AppColors.backgroundPrimary)
    }

    private func modelPickerRow(
        label: String,
        systemImage: String,
        model: ModelInfo?,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: AppSpacing.mediumLarge) {
                Image(systemName: systemImage)
                    .foregroundColor(AppColors.textSecondary)
                    .frame(width: 20)

                Text(label)
                    .font(.subheadline)
                    .foregroundColor(AppColors.textSecondary)

                Spacer()

                if let model {
                    Text(model.name)
                        .font(.subheadline)
                        .fontWeight(.medium)
                        .foregroundColor(AppColors.textPrimary)
                        .lineLimit(1)
                        .truncationMode(.middle)

                    Image(systemName: "checkmark.circle.fill")
                        .foregroundColor(AppColors.primaryGreen)
                        .font(.caption)
                } else {
                    Text("Not selected")
                        .font(.subheadline)
                        .foregroundColor(AppColors.primaryAccent)

                    Image(systemName: "chevron.right")
                        .foregroundColor(AppColors.textTertiary)
                        .font(.caption)
                }
            }
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Document Status Bar

extension DocumentRAGView {
    @ViewBuilder
    private var documentStatusBar: some View {
        VStack(spacing: 0) {
            if viewModel.isLoadingDocument {
                loadingStatusView
            } else if viewModel.isDocumentLoaded, let documentName = viewModel.documentName {
                loadedStatusView(documentName: documentName)
            } else {
                noDocumentStatusView
            }
            Divider()
        }
        .background(AppColors.backgroundPrimary)
    }

    private var noDocumentStatusView: some View {
        HStack {
            Spacer()
            Button {
                isShowingFilePicker = true
            } label: {
                Label("Select Document", systemImage: "doc.badge.plus")
                    .font(.headline)
                    .foregroundColor(.white)
                    .padding(.horizontal, AppSpacing.xLarge)
                    .padding(.vertical, AppSpacing.mediumLarge)
                    .background(areModelsReady ? AppColors.primaryAccent : AppColors.statusGray)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
            }
            .disabled(!areModelsReady)
            Spacer()
        }
        .padding(AppSpacing.large)
    }

    private var loadingStatusView: some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            ProgressView()
            Text("Loading document...")
                .font(.subheadline)
                .foregroundColor(AppColors.textSecondary)
        }
        .padding(AppSpacing.large)
        .frame(maxWidth: .infinity)
    }

    private func loadedStatusView(documentName: String) -> some View {
        HStack(spacing: AppSpacing.mediumLarge) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundColor(AppColors.primaryGreen)
                .font(.title3)

            Text(documentName)
                .font(.subheadline)
                .fontWeight(.medium)
                .foregroundColor(AppColors.textPrimary)
                .lineLimit(1)
                .truncationMode(.middle)

            Spacer()

            Button {
                Task {
                    await viewModel.clearDocument()
                    isShowingFilePicker = true
                }
            } label: {
                Text("Change")
                    .font(.caption)
                    .foregroundColor(AppColors.primaryAccent)
            }
        }
        .padding(.horizontal, AppSpacing.large)
        .padding(.vertical, AppSpacing.mediumLarge)
    }
}

// MARK: - Error Banner

extension DocumentRAGView {
    @ViewBuilder
    private var errorBanner: some View {
        if isErrorBannerVisible, let error = viewModel.error {
            HStack(spacing: AppSpacing.mediumLarge) {
                Image(systemName: "exclamationmark.triangle.fill")
                    .foregroundColor(AppColors.primaryRed)
                Text(error.localizedDescription)
                    .font(.caption)
                    .foregroundColor(AppColors.primaryRed)
                    .lineLimit(2)
                Spacer()
                Button {
                    withAnimation {
                        isErrorBannerVisible = false
                    }
                } label: {
                    Image(systemName: "xmark")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.smallMedium)
            .background(AppColors.primaryRed.opacity(0.1))
            Divider()
        }
    }
}

// MARK: - Messages Area

extension DocumentRAGView {
    private var messagesArea: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if viewModel.messages.isEmpty {
                    emptyStateView
                        .frame(maxWidth: .infinity, minHeight: 300)
                } else {
                    messageList
                }
            }
            .background(AppColors.backgroundGrouped)
            .contentShape(Rectangle())
            .onTapGesture {
                isInputFocused = false
            }
            .onChange(of: viewModel.messages.count) { _, _ in
                scrollToBottom(proxy: proxy)
            }
        }
    }

    @ViewBuilder
    private var emptyStateView: some View {
        VStack(spacing: AppSpacing.large) {
            Spacer(minLength: AppSpacing.xxxLarge)
            Image(systemName: "doc.text.magnifyingglass")
                .font(.system(size: AppSpacing.iconXXLarge))
                .foregroundColor(AppColors.textTertiary)

            VStack(spacing: AppSpacing.smallMedium) {
                if viewModel.isDocumentLoaded {
                    Text("Document loaded")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Ask a question below to get started")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                } else if !areModelsReady {
                    Text("Select models to get started")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Choose an embedding model and an LLM model above, then pick a document")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxxLarge)
                } else {
                    Text("No document selected")
                        .font(.headline)
                        .foregroundColor(AppColors.textPrimary)
                    Text("Pick a PDF or JSON document to start asking questions")
                        .font(.subheadline)
                        .foregroundColor(AppColors.textSecondary)
                        .multilineTextAlignment(.center)
                        .padding(.horizontal, AppSpacing.xxxLarge)
                }
            }
            Spacer(minLength: AppSpacing.xxxLarge)
        }
        .frame(maxWidth: .infinity)
        .padding(AppSpacing.large)
    }

    private var messageList: some View {
        LazyVStack(spacing: AppSpacing.large) {
            Spacer(minLength: AppSpacing.large)
                .id("top-spacer")

            ForEach(Array(viewModel.messages.enumerated()), id: \.offset) { index, message in
                RAGMessageBubble(message: message)
                    .id(index)
            }

            if viewModel.isQuerying {
                HStack {
                    ProgressView()
                        .scaleEffect(0.8)
                    Text("Searching document...")
                        .font(.caption)
                        .foregroundColor(AppColors.textSecondary)
                    Spacer()
                }
                .padding(.horizontal, AppSpacing.large)
                .id("querying")
            }

            Spacer(minLength: AppSpacing.large)
                .id("bottom-spacer")
        }
        .padding(.horizontal, AppSpacing.large)
    }

    private func scrollToBottom(proxy: ScrollViewProxy) {
        withAnimation(.easeInOut(duration: AppLayout.animationFast)) {
            if viewModel.isQuerying {
                proxy.scrollTo("querying", anchor: .bottom)
            } else if !viewModel.messages.isEmpty {
                proxy.scrollTo(viewModel.messages.count - 1, anchor: .bottom)
            }
        }
    }
}

// MARK: - Input Bar

extension DocumentRAGView {
    private var inputBar: some View {
        VStack(spacing: 0) {
            Divider()
            HStack(spacing: AppSpacing.mediumLarge) {
                TextField("Ask a question...", text: $viewModel.currentQuestion, axis: .vertical)
                    .textFieldStyle(.plain)
                    .lineLimit(1...4)
                    .focused($isInputFocused)
                    .disabled(!viewModel.isDocumentLoaded || viewModel.isQuerying)
                    .onSubmit {
                        sendQuestion()
                    }
                    .submitLabel(.send)

                if viewModel.isQuerying {
                    ProgressView()
                        .scaleEffect(0.8)
                } else {
                    Button(action: sendQuestion) {
                        Image(systemName: "arrow.up.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(
                                viewModel.canAskQuestion
                                    ? AppColors.primaryAccent
                                    : AppColors.statusGray
                            )
                    }
                    .disabled(!viewModel.canAskQuestion)
                }
            }
            .padding(AppSpacing.large)
            .background(AppColors.backgroundPrimary)
        }
    }

    private func sendQuestion() {
        guard viewModel.canAskQuestion else { return }
        Task {
            await viewModel.askQuestion()
        }
    }
}

// MARK: - File Import Handler

extension DocumentRAGView {
    private func handleFileImport(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            guard let url = urls.first, let baseConfig = ragConfig else { return }
            Task {
                // Inject the vocab path into embeddingConfigJSON so C++ knows where to find vocab.txt
                var finalConfig = baseConfig
                if let embeddingModel = selectedEmbeddingModel,
                   let vocabPath = resolveVocabPath(for: embeddingModel) {
                    let vocabJSON = "{\"vocab_path\":\"\(vocabPath)\"}"
                    finalConfig = RAGConfiguration(
                        embeddingModelPath: baseConfig.embeddingModelPath,
                        llmModelPath: baseConfig.llmModelPath,
                        embeddingDimension: baseConfig.embeddingDimension,
                        topK: baseConfig.topK,
                        similarityThreshold: baseConfig.similarityThreshold,
                        maxContextTokens: baseConfig.maxContextTokens,
                        chunkSize: baseConfig.chunkSize,
                        chunkOverlap: baseConfig.chunkOverlap,
                        promptTemplate: baseConfig.promptTemplate,
                        embeddingConfigJSON: vocabJSON,
                        llmConfigJSON: baseConfig.llmConfigJSON
                    )
                }
                await viewModel.loadDocument(url: url, config: finalConfig)
            }
        case .failure(let error):
            viewModel.error = error
        }
    }
}

// MARK: - RAG Message Bubble

private struct RAGMessageBubble: View {
    let message: (role: MessageRole, text: String)

    private var isUser: Bool {
        message.role == .user
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.smallMedium) {
            if isUser { Spacer(minLength: AppSpacing.xxxLarge) }

            Text(message.text)
                .font(.body)
                .foregroundColor(isUser ? .white : AppColors.textPrimary)
                .padding(.horizontal, AppSpacing.mediumLarge)
                .padding(.vertical, AppSpacing.smallMedium)
                .background(
                    isUser
                        ? AppColors.messageBubbleUser
                        : AppColors.messageBubbleAssistant
                )
                .cornerRadius(AppSpacing.cornerRadiusBubble)

            if !isUser { Spacer(minLength: AppSpacing.xxxLarge) }
        }
    }
}


#Preview {
    DocumentRAGView()
}
