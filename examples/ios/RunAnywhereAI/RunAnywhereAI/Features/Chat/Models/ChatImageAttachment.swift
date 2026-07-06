//
//  ChatImageAttachment.swift
//  RunAnywhereAI
//
//  Pending image attachment for chat-first VLM questions.
//

import Foundation
import RunAnywhere

struct ChatImageAttachment: Identifiable {
    let id = UUID()
    let data: Data
    let image: RAVLMImage
    let filename: String
}
