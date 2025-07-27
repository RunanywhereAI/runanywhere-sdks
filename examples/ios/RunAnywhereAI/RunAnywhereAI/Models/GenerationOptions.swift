//
//  GenerationOptions.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

struct GenerationOptions {
    var maxTokens: Int
    var temperature: Float
    var topP: Float
    var topK: Int
    var repetitionPenalty: Float
    var stopSequences: [String]

    static let `default` = GenerationOptions(
        maxTokens: 150,
        temperature: 0.7,
        topP: 0.95,
        topK: 40,
        repetitionPenalty: 1.1,
        stopSequences: []
    )
}
