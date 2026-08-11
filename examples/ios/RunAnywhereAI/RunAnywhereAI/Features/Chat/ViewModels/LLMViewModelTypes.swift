//
//  LLMViewModelTypes.swift
//  RunAnywhereAI
//
//  Supporting types for LLMViewModel
//

import Foundation

// MARK: - LLM Error

enum LLMError: LocalizedError {
    case noModelLoaded
    case custom(String)

    var errorDescription: String? {
        switch self {
        case .noModelLoaded:
            return "No model is loaded. Please select and load a model from the Models tab first."
        case .custom(let message):
            return message
        }
    }
}

// MARK: - Document RAG

struct ChatDocumentRAGPipelineKey: Equatable {
    let documentID: UUID
    let embeddingModelID: String
    let answerModelID: String
}

/// How far the attached document has got towards being answerable.
///
/// Indexing is lazy — it runs on the first question, not on attach — so
/// "the models are chosen" and "the document is searchable" are separate facts
/// and only the second one may be shown as ready.
enum ChatDocumentIndexState: Equatable {
    /// Attached, not yet indexed. Indexing starts with the first question.
    case notIndexed
    /// Chunking + embedding in flight.
    case indexing
    /// Embeddings are in the index; questions can be answered.
    case indexed
    /// Indexing was attempted and failed, carrying the reason commons gave.
    case failed(String)

    /// What the composer's document chip is allowed to say.
    ///
    /// Only `.indexed` licenses "Ready for questions". Choosing two models used
    /// to be enough to claim it, so a document whose embedding step later failed
    /// had already been announced as answerable — and still read "Ready for
    /// questions" underneath the failure.
    func chipSubtitle(modelsReady: Bool) -> String {
        guard modelsReady else { return "Choose document models" }
        switch self {
        case .notIndexed: return "Ask a question to index this document"
        case .indexing: return "Indexing…"
        case .indexed: return "Ready for questions"
        case .failed(let reason): return reason
        }
    }

    /// True only when a question can actually be answered right now.
    func isChipReady(modelsReady: Bool) -> Bool {
        modelsReady && self == .indexed
    }
}
