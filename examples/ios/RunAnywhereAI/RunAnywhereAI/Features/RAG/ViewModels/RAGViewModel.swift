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

    // MARK: - Think Tag Helpers

    /// Extract the content inside `<think>...</think>` tags.
    static func extractThinkingContent(from text: String) -> String? {
        guard let startRange = text.range(of: "<think>"),
              let endRange = text.range(of: "</think>"),
              startRange.upperBound <= endRange.lowerBound else {
            return nil
        }
        let content = String(text[startRange.upperBound..<endRange.lowerBound])
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return content.isEmpty ? nil : content
    }

    /// Strip all `<think>...</think>` blocks and trailing incomplete `<think>` tags.
    static func stripThinkTags(from text: String) -> String {
        var result = text
        while let startRange = result.range(of: "<think>"),
              let endRange = result.range(of: "</think>"),
              startRange.upperBound <= endRange.lowerBound {
            result.removeSubrange(startRange.lowerBound..<endRange.upperBound)
        }
        if let trailingStart = result.range(of: "<think>", options: .backwards),
           result.range(of: "</think>", range: trailingStart.upperBound..<result.endIndex) == nil {
            result = String(result[result.startIndex..<trailingStart.lowerBound])
        }
        return result.trimmingCharacters(in: .whitespacesAndNewlines)
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

        messages.append(RAGMessage(role: .user, text: question))
        currentQuestion = ""
        isQuerying = true
        error = nil

        defer {
            isQuerying = false
        }

        do {
            let settings = SettingsViewModel.shared
            let effectiveQuestion: String
            if settings.loadedModelSupportsThinking && !settings.thinkingModeEnabled {
                effectiveQuestion = "/no_think\n\(question)"
            } else {
                effectiveQuestion = question
            }

            logger.info("Querying RAG pipeline: \(question)")
            let result = try await RunAnywhere.ragQuery(question: effectiveQuestion)
            let thinkingContent = RAGMessage.extractThinkingContent(from: result.answer)
            let displayText = RAGMessage.stripThinkTags(from: result.answer)
            messages.append(RAGMessage(role: .assistant, text: displayText, thinkingContent: thinkingContent))
            logger.info("Query complete (\(result.totalTimeMs, format: .fixed(precision: 0))ms)")
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
}
