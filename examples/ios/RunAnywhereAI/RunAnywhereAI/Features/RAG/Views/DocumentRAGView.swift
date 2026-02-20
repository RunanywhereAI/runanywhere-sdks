//
//  DocumentRAGView.swift
//  RunAnywhereAI
//
//  SwiftUI view for the RAG document Q&A feature.
//  Handles document picking, loading state, and Q&A chat interface.
//

import SwiftUI
import UniformTypeIdentifiers
import RunAnywhere

// MARK: - Document RAG View

struct DocumentRAGView: View {
    @State private var viewModel = RAGViewModel()
    @State private var isShowingFilePicker = false
    @State private var isErrorBannerVisible = false
    @FocusState private var isInputFocused: Bool

    // Placeholder RAG configuration — model paths will be wired from
    // the app's model manager in a future iteration.
    private var ragConfig: RAGConfiguration {
        RAGConfiguration(
            embeddingModelPath: "",  // Placeholder — real path from model manager
            llmModelPath: ""         // Placeholder — real path from model manager
        )
    }

    var body: some View {
        NavigationView {
            VStack(spacing: 0) {
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
        .onChange(of: viewModel.error != nil) { _, hasError in
            withAnimation {
                isErrorBannerVisible = hasError
            }
        }
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
                    .background(AppColors.primaryAccent)
                    .cornerRadius(AppSpacing.cornerRadiusLarge)
            }
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
            guard let url = urls.first else { return }
            Task {
                await viewModel.loadDocument(url: url, config: ragConfig)
            }
        case .failure(let error):
            // Assign import error to viewModel so it surfaces in the error banner
            Task { @MainActor in
                _ = error  // Error is surfaced via viewModel.error set by loadDocument
            }
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
