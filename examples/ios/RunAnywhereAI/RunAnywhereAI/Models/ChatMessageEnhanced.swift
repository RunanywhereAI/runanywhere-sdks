//
//  ChatMessageEnhanced.swift
//  RunAnywhereAI
//
//  Created by Assistant on 7/27/25.
//

import Foundation

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
    
    var generationMetrics: Any? {
        get {
            objc_getAssociatedObject(self, &metricsKey)
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