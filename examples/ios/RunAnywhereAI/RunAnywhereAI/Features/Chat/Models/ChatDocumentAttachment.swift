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

    var metadataJSON: String? {
        let payload = [
            "source": filename,
            "filename": filename
        ]
        guard let data = try? JSONSerialization.data(
            withJSONObject: payload,
            options: [.sortedKeys]
        ) else {
            return nil
        }
        return String(data: data, encoding: .utf8)
    }
}
