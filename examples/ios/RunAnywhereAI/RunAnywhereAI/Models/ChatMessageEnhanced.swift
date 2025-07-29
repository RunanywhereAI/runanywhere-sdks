//
//  ChatMessageEnhanced.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/27/25.
//

import Foundation

// Make ChatMessage support the additional properties
private var frameworkKey: UInt8 = 0
private var metricsKey: UInt8 = 0
private var errorKey: UInt8 = 0
private var modelNameKey: UInt8 = 0
private var modelIdKey: UInt8 = 0
private var modelInfoKey: UInt8 = 0

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
    
    var modelName: String? {
        get {
            objc_getAssociatedObject(self, &modelNameKey) as? String
        }
        set {
            objc_setAssociatedObject(self, &modelNameKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var modelId: String? {
        get {
            objc_getAssociatedObject(self, &modelIdKey) as? String
        }
        set {
            objc_setAssociatedObject(self, &modelIdKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
    
    var modelInfo: ModelInfo? {
        get {
            objc_getAssociatedObject(self, &modelInfoKey) as? ModelInfo
        }
        set {
            objc_setAssociatedObject(self, &modelInfoKey, newValue, .OBJC_ASSOCIATION_RETAIN)
        }
    }
}
