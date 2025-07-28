//
//  CoreMLModelAdapter.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import Foundation
import CoreML

// MARK: - Core ML Model Adapter Protocol

/// Protocol for model-specific Core ML adapters
/// This allows the CoreMLService to be model-agnostic while supporting different model formats
@available(iOS 17.0, *)
protocol CoreMLModelAdapter {
    /// The model this adapter supports
    var modelInfo: ModelInfo { get }
    
    /// Maximum sequence length supported by the model
    var maxSequenceLength: Int { get }
    
    /// Expected vocabulary size (if applicable)
    var vocabularySize: Int? { get }
    
    /// Model-specific input names
    var inputNames: [String] { get }
    
    /// Model-specific output names  
    var outputNames: [String] { get }
    
    /// Create input arrays for the model from tokens
    func createInputArrays(from tokens: [Int32]) throws -> [String: MLMultiArray]
    
    /// Sample next token from model output
    func sampleNextToken(from prediction: MLFeatureProvider, lastTokenPosition: Int, temperature: Double) throws -> Int32
    
    /// Validate if a Core ML model is compatible with this adapter
    func isCompatible(with model: MLModel) -> Bool
    
    /// Get model-specific tokenizer if available
    func createTokenizer(modelPath: String) -> Tokenizer?
}

// MARK: - Adapter Factory

@available(iOS 17.0, *)
class CoreMLAdapterFactory {
    static func createAdapter(for modelInfo: ModelInfo, model: MLModel) -> CoreMLModelAdapter? {
        // Try adapters in order of specificity
        let adapters: [CoreMLModelAdapter] = [
            GPT2CoreMLAdapter(modelInfo: modelInfo),
            // Add more model-specific adapters here
            // StableDiffusionCoreMLAdapter(modelInfo: modelInfo),
            // BERTCoreMLAdapter(modelInfo: modelInfo),
        ]
        
        return adapters.first { $0.isCompatible(with: model) }
    }
}