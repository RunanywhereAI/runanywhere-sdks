//
//  FrameworkInfo.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/26/25.
//

import Foundation

/// Information about an LLM framework
struct FrameworkInfo {
    let name: String
    let version: String
    let developer: String
    let description: String
    let website: URL?
    let documentation: URL?
    let minimumOSVersion: String
    let requiredCapabilities: [String]
    let optimizedFor: [OptimizationTarget]
    let features: [FrameworkFeature]
}

/// Optimization targets for frameworks
enum OptimizationTarget: String, CaseIterable {
    case appleNeuralEngine = "Apple Neural Engine"
    case metalPerformanceShaders = "Metal Performance Shaders"
    case cpuOptimized = "CPU Optimized"
    case memoryEfficient = "Memory Efficient"
    case lowLatency = "Low Latency"
    case highThroughput = "High Throughput"
    case edgeDevice = "Edge Device"
    case realTime = "Real-Time"
}

/// Special features offered by frameworks
enum FrameworkFeature: String, CaseIterable {
    // Core Features
    case onDeviceInference = "On-Device Inference"
    case cloudFallback = "Cloud Fallback"
    case hybridExecution = "Hybrid Execution"
    
    // Model Support
    case multiModal = "Multi-Modal Support"
    case customModels = "Custom Models"
    case pretrainedModels = "Pre-trained Models"
    case modelConversion = "Model Conversion"
    
    // Performance
    case quantization = "Quantization"
    case pruning = "Model Pruning"
    case caching = "Response Caching"
    case batching = "Batch Processing"
    
    // Advanced Features
    case fineTuning = "Fine-Tuning"
    case federatedLearning = "Federated Learning"
    case differentialPrivacy = "Differential Privacy"
    case customOperators = "Custom Operators"
    
    // Integration
    case swiftPackageManager = "Swift Package Manager"
    case cocoaPods = "CocoaPods Support"
    case xcframework = "XCFramework"
    case openSource = "Open Source"
    
    // Specialized
    case voiceOptimized = "Voice Optimized"
    case visionOptimized = "Vision Optimized"
    case lowPowerMode = "Low Power Mode"
    case offlineCapable = "Offline Capable"
}