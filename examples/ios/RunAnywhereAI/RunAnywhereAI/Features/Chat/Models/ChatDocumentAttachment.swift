//
//  ChatDocumentAttachment.swift
//  RunAnywhereAI
//
//  Pending document attachment for chat-first RAG questions.
//

import Foundation

struct ChatDocumentAttachment: Identifiable {
    let id = UUID()
    let filename: String
    let text: String

    var characterCount: Int {
        text.count
    }
}
