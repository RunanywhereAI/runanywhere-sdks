//
//  ChatMessageEnhanced.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation

// Enhanced ChatMessage with framework and metrics support
extension ChatMessage {
    var framework: LLMFramework?
    var generationMetrics: GenerationMetrics?
    var isError: Bool

    init(id: UUID = UUID(),
         role: MessageRole,
         content: String,
         timestamp: Date = Date(),
         framework: LLMFramework? = nil,
         generationMetrics: GenerationMetrics? = nil,
         isError: Bool = false) {
        self.init(id: id, role: role, content: content, timestamp: timestamp)
        self.framework = framework
        self.generationMetrics = generationMetrics
        self.isError = isError
    }
}

// Make ChatMessage support the additional properties
private var frameworkKey: UInt8 = 0
private var metricsKey: UInt8 = 0
private var errorKey: UInt8 = 0

extension ChatMessage {
    var framework: LLMFramework? {
        get {
            objc_getAssociatedObject(self, &frameworkKey) as? LLMFramework
        }
        set {
            objc_setAssociatedObject(self, &frameworkKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var generationMetrics: GenerationMetrics? {
        get {
            objc_getAssociatedObject(self, &metricsKey) as? GenerationMetrics
        }
        set {
            objc_setAssociatedObject(self, &metricsKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var isError: Bool {
        get {
            objc_getAssociatedObject(self, &errorKey) as? Bool ?? false
        }
        set {
            objc_setAssociatedObject(self, &errorKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}