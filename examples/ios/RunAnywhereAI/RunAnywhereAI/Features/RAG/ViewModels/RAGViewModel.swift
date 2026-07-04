//
//  RAGViewModel.swift
//  RunAnywhereAI
//
//  ViewModel for the RAG feature. Orchestrates document loading,
//  text extraction, SDK pipeline lifecycle, and query flow.
//

import Foundation
import Observation
import RunAnywhere
import os.log

// MARK: - Message Role

enum MessageRole {
    case user
    case assistant
    case system
}

// MARK: - RAG Message

struct RAGMessage: Identifiable {
    let id = UUID()
    let role: MessageRole
    let text: String
    let thinkingContent: String?

    init(role: MessageRole, text: String, thinkingContent: String? = nil) {
        self.role = role
        self.text = text
        self.thinkingContent = thinkingContent
    }

}

// MARK: - RAG View Model

@MainActor
@Observable
final class RAGViewModel {
    // MARK: - Document State

    private(set) var documentName: String?
    private(set) var isDocumentLoaded = false
    private(set) var isLoadingDocument = false

    // MARK: - Query State

    private(set) var messages: [RAGMessage] = []
    private(set) var isQuerying = false
    /// Settable from the view layer to surface file-picker failures in the error banner.
    var error: Error?

    // MARK: - Input

    var currentQuestion = ""

    // MARK: - Retrieval Options

    /// Rerank is a pipeline setting (RARAGConfiguration); multi-query is a
    /// per-query option (RARAGQueryOptions).
    private(set) var rerankEnabled = false
    var multiQueryEnabled = false

    // MARK: - Private

    private let logger = Logger(subsystem: "com.runanywhere.RunAnywhereAI", category: "RAGViewModel")

    // MARK: - Computed Properties

    var canAskQuestion: Bool {
        isDocumentLoaded
        && !isQuerying
        && !currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Public Methods

    /// Load a document: extract text, create RAG pipeline, ingest text.
    ///
    /// - Parameters:
    ///   - url: Security-scoped URL of the document (PDF or JSON).
    ///   - embeddingModel: Registry model selected for embeddings.
    ///   - llmModel: Registry model selected for answer generation.
    func loadDocument(
        url: URL,
        embeddingModel: RAModelInfo,
        llmModel: RAModelInfo
    ) async {
        isLoadingDocument = true
        error = nil

        defer {
            isLoadingDocument = false
        }

        do {
            logger.info("Extracting text from document: \(url.lastPathComponent)")
            let extractedText = try DocumentService.extractText(from: url)

            logger.info("Creating RAG pipeline")
            // Canonical defaults do the right thing: commons derives the
            // embedding dimension from the loaded embedding model, and the
            // retrieval/chunking values come from idl/rag.proto rac_defaults.
            var configuration = RARAGConfiguration.defaults()
            configuration.rerankResults = rerankEnabled
            try await RunAnywhere.ragCreatePipeline(
                embeddingModel: embeddingModel,
                llmModel: llmModel,
                baseConfiguration: configuration
            )

            logger.info("Ingesting document text (\(extractedText.count) chars)")
            try await RunAnywhere.ragIngest(text: extractedText)

            documentName = url.lastPathComponent
            isDocumentLoaded = true
            logger.info("Document loaded successfully: \(url.lastPathComponent)")
        } catch {
            self.error = error
            logger.error("Failed to load document: \(error.localizedDescription)")
        }
    }

    /// Query the loaded document with the current question.
    ///
    /// Appends the user question and the assistant answer to `messages`.
    /// Guards against empty questions and unloaded documents.
    func askQuestion() async {
        let question = currentQuestion.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !question.isEmpty else { return }
        guard isDocumentLoaded else { return }

        messages.append(RAGMessage(role: .user, text: question))
        currentQuestion = ""
        isQuerying = true
        error = nil

        defer {
            isQuerying = false
        }

        do {
            let settings = SettingsViewModel.shared
            var options = RARAGQueryOptions.defaults(question: question)
            // Structured flag — commons applies the model's no-think
            // directive; the app never injects control tokens into prompts.
            options.disableThinking =
                settings.loadedModelSupportsThinking && !settings.thinkingModeEnabled
            options.enableMultiQuery = multiQueryEnabled

            logger.info("Querying RAG pipeline: \(question)")
            let result = try await RunAnywhere.ragQuery(options)
            messages.append(RAGMessage(
                role: .assistant,
                text: result.answer,
                thinkingContent: result.hasThinkingContent ? result.thinkingContent : nil
            ))
            logger.info("Query complete (\(Double(result.totalTimeMs), format: .fixed(precision: 0))ms)")
        } catch {
            self.error = error
            messages.append(RAGMessage(role: .assistant, text: "Error: \(error.localizedDescription)"))
            logger.error("Query failed: \(error.localizedDescription)")
        }
    }

    /// Clear the loaded document and destroy the RAG pipeline.
    ///
    /// Resets all document and conversation state.
    func clearDocument() async {
        await RunAnywhere.ragDestroyPipeline()

        documentName = nil
        isDocumentLoaded = false
        messages = []
        error = nil
        currentQuestion = ""

        logger.info("Document cleared and pipeline destroyed")
    }

    /// Rerank is a pipeline setting, so changing it rebuilds the pipeline. With a
    /// document loaded, this resets the session (re-add the document) — matching
    /// how changing models resets the pipeline.
    func setRerankEnabled(_ value: Bool) async {
        guard rerankEnabled != value else { return }
        rerankEnabled = value
        if isDocumentLoaded {
            await clearDocument()
        }
    }
}
