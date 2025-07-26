//
//  Constants.swift
//  RunAnywhereAI
//
//  Created on 7/26/25.
//

import Foundation

enum Constants {
    enum App {
        static let name = "RunAnywhereAI"
        static let version = "1.0.0"
        static let bundleId = "com.runanywhere.ai.demo"
    }
    
    enum Storage {
        static let modelsDirectory = "Models"
        static let cacheDirectory = "Cache"
    }
    
    enum Generation {
        static let defaultMaxTokens = 150
        static let defaultTemperature: Float = 0.7
        static let defaultTopP: Float = 0.95
        static let defaultTopK = 40
        static let defaultRepetitionPenalty: Float = 1.1
    }
    
    enum Memory {
        static let minimumRequiredMemory: Int64 = 1_000_000_000 // 1GB
        static let recommendedMemory: Int64 = 2_000_000_000 // 2GB
    }
    
    enum UI {
        static let messageMaxWidth: Double = 0.75
        static let typingIndicatorDelay: Double = 0.2
        static let streamingTokenDelay: TimeInterval = 0.1
    }
}