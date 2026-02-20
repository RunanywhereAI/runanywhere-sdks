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

// MARK: - RAG View Model

@MainActor
@Observable
final class RAGViewModel {

    // MARK: - Document State

    private(set) var documentName: String?
    private(set) var isDocumentLoaded = false
    private(set) var isLoadingDocument = false

    // MARK: - Query State

    private(set) var messages: [(role: MessageRole, text: String)] = []
    private(set) var isQuerying = false
    private(set) var error: Error?

    // MARK: - Input

    var currentQuestion = ""

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
    ///   - config: RAG pipeline configuration with model paths and tuning parameters.
    func loadDocument(url: URL, config: RAGConfiguration) async {
        isLoadingDocument = true
        error = nil

        defer {
            isLoadingDocument = false
        }

        do {
            logger.info("Extracting text from document: \(url.lastPathComponent)")
            let extractedText = try DocumentService.extractText(from: url)

            logger.info("Creating RAG pipeline")
            try await RunAnywhere.ragCreatePipeline(config: config)

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

        messages.append((role: .user, text: question))
        currentQuestion = ""
        isQuerying = true
        error = nil

        defer {
            isQuerying = false
        }

        do {
            logger.info("Querying RAG pipeline: \(question)")
            let result = try await RunAnywhere.ragQuery(question: question)
            messages.append((role: .assistant, text: result.answer))
            logger.info("Query complete (\(result.totalTimeMs, format: .fixed(precision: 0))ms)")
        } catch {
            self.error = error
            messages.append((role: .assistant, text: "Error: \(error.localizedDescription)"))
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
}
