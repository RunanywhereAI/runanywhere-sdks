//
//  BaseFrameworkAdapter.swift
//  RunAnywhereAI
//
//  Base adapter for framework implementations in the sample app
//

import Foundation
// Import SDK when available
// import RunAnywhere

// MARK: - Base Framework Adapter
// This is a sample app implementation that will implement SDK's FrameworkAdapter protocol

class BaseFrameworkAdapter {
    let framework: LLMFramework
    let supportedFormats: [ModelFormat]
    
    init(framework: LLMFramework, formats: [ModelFormat]) {
        self.framework = framework
        self.supportedFormats = formats
    }
    
    // When SDK is available, this class will implement FrameworkAdapter protocol
    // and use SDK's components like HardwareCapabilityManager, ProgressTracker, etc.
}