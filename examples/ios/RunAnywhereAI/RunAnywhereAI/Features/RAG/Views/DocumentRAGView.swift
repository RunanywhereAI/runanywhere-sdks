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
    @State private var selectedEmbeddingModel: RAModelInfo?
    @State private var selectedLLMModel: RAModelInfo?
    @FocusState private var isInputFocused: Bool

    private var areModelsReady: Bool {
        selectedEmbeddingModel?.isAvailableForUse == true
            && selectedLLMModel?.isAvailableForUse == true
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
                modelSetupSection
                documentStatusBar
                retrievalOptionsSection
                errorBanner
                messagesArea
                inputBar
            }
            .background(AppColors.backgroundGrouped)
            .navigationTitle("Document Q&A")
            #if os(iOS)
            .navigationBarTitleDisplayModeCompat(.inline)
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
    @ViewBuilder private var modelSetupSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppSpacing.smallMedium) {
                modelPickerRow(
                    label: "Embedding Model",
                    systemImage: "brain",
                    model: selectedEmbeddingModel
                ) {
                    isShowingEmbeddingModelPicker = true
                }
                modelPickerRow(
                    label: "LLM Model",
                    systemImage: "text.bubble",
                    model: selectedLLMModel
                ) {
                    isShowingLLMModelPicker = true
                }
            }
            .padding(.horizontal, AppSpacing.large)
            .padding(.vertical, AppSpacing.mediumLarge)
            Divider()
        }
        .background(AppColors.backgroundPrimary)
    }

    // Retrieval-quality toggles backed by the public SDK RAG options: rerank
    // (RARAGConfiguration.rerankResults) and multi-query (RARAGQueryOptions.enableMultiQuery).
    @ViewBuilder private var retrievalOptionsSection: some View {
        VStack(spacing: 0) {
            VStack(spacing: AppSpacing.smallMedium) {
                Toggle(isOn: Binding(
                    get: { viewModel.rerankEnabled },
                    set: { newValue in Task { await viewModel.setRerankEnabled(newValue) } }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Rerank results")
                        Text("LLM re-scores retrieved chunks for relevance")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
                Toggle(isOn: Binding(
                    get: { viewModel.multiQueryEnabled },
                    set: { viewModel.multiQueryEnabled = $0 }
                )) {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Multi-query expansion")
                        Text("Rewrites the question into variants, fuses results")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                }
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
        model: RAModelInfo?,
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
    @ViewBuilder private var documentStatusBar: some View {
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
    @ViewBuilder private var errorBanner: some View {
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

    @ViewBuilder private var emptyStateView: some View {
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

            ForEach(viewModel.messages) { message in
                RAGMessageBubble(message: message)
                    .id(message.id)
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
            } else if let lastMessage = viewModel.messages.last {
                proxy.scrollTo(lastMessage.id, anchor: .bottom)
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
            guard
                let url = urls.first,
                let embeddingModel = selectedEmbeddingModel,
                let llmModel = selectedLLMModel
            else { return }
            Task {
                await viewModel.loadDocument(
                    url: url,
                    embeddingModel: embeddingModel,
                    llmModel: llmModel
                )
            }
        case .failure(let error):
            viewModel.error = error
        }
    }
}

// MARK: - RAG Message Bubble

private struct RAGMessageBubble: View {
    let message: RAGMessage
    @State private var isThinkingExpanded = false

    private var isUser: Bool {
        message.role == .user
    }

    private var hasThinking: Bool {
        message.thinkingContent != nil && !(message.thinkingContent?.isEmpty ?? true)
    }

    var body: some View {
        HStack(alignment: .bottom, spacing: AppSpacing.smallMedium) {
            if isUser { Spacer(minLength: AppSpacing.xxxLarge) }

            VStack(alignment: .leading, spacing: 4) {
                if !isUser && hasThinking {
                    thinkingSection
                }

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
            }

            if !isUser { Spacer(minLength: AppSpacing.xxxLarge) }
        }
    }

    // MARK: - Thinking Section

    private var thinkingSection: some View {
        VStack(alignment: .leading, spacing: AppSpacing.small) {
            Button {
                withAnimation(.easeInOut(duration: AppLayout.animationFast)) {
                    isThinkingExpanded.toggle()
                }
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "lightbulb.min")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)

                    Text(isThinkingExpanded ? "Hide reasoning" : thinkingSummary)
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.primaryPurple)
                        .lineLimit(1)

                    Spacer()

                    Image(systemName: isThinkingExpanded ? "chevron.up" : "chevron.right")
                        .font(AppTypography.caption2)
                        .foregroundColor(AppColors.primaryPurple.opacity(0.6))
                }
                .padding(.horizontal, AppSpacing.regular)
                .padding(.vertical, AppSpacing.padding9)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
                        .fill(
                            LinearGradient(
                                colors: [
                                    AppColors.primaryPurple.opacity(0.1),
                                    AppColors.primaryPurple.opacity(0.05)
                                ],
                                startPoint: .topLeading,
                                endPoint: .bottomTrailing
                            )
                        )
                        .shadow(color: AppColors.primaryPurple.opacity(0.2), radius: 2, x: 0, y: 1)
                        .overlay(
                            RoundedRectangle(cornerRadius: AppSpacing.mediumLarge)
                                .strokeBorder(
                                    AppColors.primaryPurple.opacity(0.2),
                                    lineWidth: AppSpacing.strokeThin
                                )
                        )
                )
            }
            .buttonStyle(PlainButtonStyle())

            if isThinkingExpanded {
                ScrollView {
                    Text(message.thinkingContent ?? "")
                        .font(AppTypography.caption)
                        .foregroundColor(AppColors.textSecondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .fixedSize(horizontal: false, vertical: true)
                        .multilineTextAlignment(.leading)
                }
                .frame(maxHeight: AppSpacing.minFrameHeight)
                .padding(AppSpacing.mediumLarge)
                .background(
                    RoundedRectangle(cornerRadius: AppSpacing.medium)
                        .fill(AppColors.backgroundGray6)
                )
                .transition(.asymmetric(
                    insertion: .opacity.combined(with: .slide),
                    removal: .opacity.combined(with: .slide)
                ))
            }
        }
    }

    private var thinkingSummary: String {
        guard let thinking = message.thinkingContent?
            .trimmingCharacters(in: .whitespacesAndNewlines) else {
            return ""
        }

        let sentences = thinking.components(separatedBy: CharacterSet(charactersIn: ".!?"))
            .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

        if sentences.count >= 2 {
            let firstSentence = sentences[0].trimmingCharacters(in: .whitespacesAndNewlines)
            if firstSentence.count > 20 {
                return firstSentence + "..."
            }
        }

        if thinking.count > 80 {
            let truncated = String(thinking.prefix(80))
            if let lastSpace = truncated.lastIndex(of: " ") {
                return String(truncated[..<lastSpace]) + "..."
            }
            return truncated + "..."
        }

        return thinking
    }
}


#Preview {
    DocumentRAGView()
}
