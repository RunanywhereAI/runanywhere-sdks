//
//  GPT2CoreMLAdapter.swift
//  RunAnywhereAI
//
//  Created by Sanchit Monga on 7/28/25.
//

import Foundation
import CoreML

// MARK: - GPT-2 Core ML Adapter

@available(iOS 17.0, *)
class GPT2CoreMLAdapter: CoreMLModelAdapter {
    let modelInfo: ModelInfo
    let maxSequenceLength = 512  // GPT-2 fixed sequence length
    let vocabularySize: Int? = 50257  // GPT-2 vocabulary size
    let inputNames = ["input_ids", "position_ids"]
    let outputNames = ["logits", "output", "prediction", "scores"]

    private let padTokenId: Int32 = 0

    init(modelInfo: ModelInfo) {
        self.modelInfo = modelInfo
    }

    func createInputArrays(from tokens: [Int32]) throws -> [String: MLMultiArray] {
        let inputIds = try createInputIdsArray(from: tokens)
        let positionIds = try createPositionIdsArray(for: tokens)

        return [
            "input_ids": inputIds,
            "position_ids": positionIds
        ]
    }

    func sampleNextToken(from prediction: MLFeatureProvider, lastTokenPosition: Int, temperature: Double) throws -> Int32 {
        // Based on Hugging Face reference, the output is typically named "var_0" or similar
        // First try common output names including var_0
        let extendedOutputNames = ["var_0", "output", "logits", "prediction", "scores"]

        for outputName in extendedOutputNames {
            if let feature = prediction.featureValue(for: outputName),
               let logitsArray = feature.multiArrayValue {
                print("GPT-2: Using output '\(outputName)' with shape: \(logitsArray.shape)")

                // Following the reference implementation pattern:
                // Get logits for the last actual token position (not padded position)
                return extractAndSampleLastToken(from: logitsArray, actualTokenCount: lastTokenPosition + 1, temperature: temperature)
            }
        }

        // Fallback: try any available output
        let availableOutputs = prediction.featureNames
        print("GPT-2: Available outputs: \(availableOutputs)")

        for outputName in availableOutputs {
            if let feature = prediction.featureValue(for: outputName),
               let logitsArray = feature.multiArrayValue {
                print("GPT-2: Fallback using output '\(outputName)' with shape: \(logitsArray.shape)")
                return extractAndSampleLastToken(from: logitsArray, actualTokenCount: lastTokenPosition + 1, temperature: temperature)
            }
        }

        throw LLMError.inferenceError("No suitable output found for GPT-2 model")
    }

    func isCompatible(with model: MLModel) -> Bool {
        let description = model.modelDescription
        let inputs = description.inputDescriptionsByName
        let outputs = description.outputDescriptionsByName

        // Check for GPT-2 specific inputs
        let hasInputIds = inputs.keys.contains { $0.contains("input") }
        let hasPositionIds = inputs.keys.contains { $0.contains("position") }

        // Check for typical GPT-2 output
        let hasLogitsOutput = outputs.keys.contains { outputNames.contains($0) }

        // Check if model name suggests GPT-2
        let modelNameSuggests = modelInfo.name.lowercased().contains("gpt") ||
                               modelInfo.id.lowercased().contains("gpt")

        print("GPT-2 Compatibility Check:")
        print("- Has input_ids: \(hasInputIds)")
        print("- Has position_ids: \(hasPositionIds)")
        print("- Has logits output: \(hasLogitsOutput)")
        print("- Model name suggests GPT-2: \(modelNameSuggests)")

        return hasInputIds && (hasPositionIds || modelNameSuggests)
    }

    func createTokenizer(modelPath: String) -> Tokenizer? {
        return TokenizerFactory.createForFramework(.coreML, modelPath: modelPath)
    }

    // MARK: - Private GPT-2 Specific Methods

    private func createInputIdsArray(from tokens: [Int32]) throws -> MLMultiArray {
        // Create 1D array with shape [512] - model expects rank 1
        let inputShape = [maxSequenceLength] as [NSNumber]
        let inputArray = try MLMultiArray(shape: inputShape, dataType: .int32)

        // Initialize all positions with padding token (0)
        for i in 0..<maxSequenceLength {
            inputArray[i] = NSNumber(value: padTokenId)
        }

        // Fill with actual tokens (left-padded approach for better generation)
        let tokenCount = min(tokens.count, maxSequenceLength)
        let startIndex = maxSequenceLength - tokenCount  // Right-align tokens
        for i in 0..<tokenCount {
            inputArray[startIndex + i] = NSNumber(value: tokens[i])
        }

        print("GPT-2: Created input_ids array with shape: \(inputArray.shape), filled \(tokenCount) tokens starting at position \(startIndex)")
        return inputArray
    }

    private func createPositionIdsArray(for tokens: [Int32]) throws -> MLMultiArray {
        // Create 1D array with shape [512] - rank 1 as required by the model
        let positionShape = [maxSequenceLength] as [NSNumber]
        let positionArray = try MLMultiArray(shape: positionShape, dataType: .int32)

        // Position IDs are sequential indices: [0, 1, 2, 3, ..., 511]
        // This is required for all 512 positions, even padded ones
        for i in 0..<maxSequenceLength {
            positionArray[i] = NSNumber(value: i)
        }

        print("GPT-2: Created position_ids array with shape: \(positionArray.shape)")
        return positionArray
    }

    private func extractAndSampleLastToken(from logitsArray: MLMultiArray, actualTokenCount: Int, temperature: Double) -> Int32 {
        // Following Hugging Face reference: logits[tokens.count - 1]
        let shape = logitsArray.shape.map { $0.intValue }
        print("GPT-2: Extracting logits from shape \(shape) for token position \(actualTokenCount - 1)")

        // Handle different output shapes
        if shape.count == 2 && shape[0] == maxSequenceLength {
            // Shape [seqLen, vocab] - most common for GPT-2
            // Get logits for the last actual token (not padding)
            let position = actualTokenCount - 1
            let vocabSize = shape[1]

            var logits: [Float] = []
            for vocabIdx in 0..<vocabSize {
                let indices = [position, vocabIdx] as [NSNumber]
                logits.append(logitsArray[indices].floatValue)
            }

            return sampleFromLogitsArray(logits, temperature: temperature)

        } else if shape.count == 3 {
            // Shape [batch, seqLen, vocab]
            let position = actualTokenCount - 1
            let vocabSize = shape[2]

            var logits: [Float] = []
            for vocabIdx in 0..<vocabSize {
                let indices = [0, position, vocabIdx] as [NSNumber]
                logits.append(logitsArray[indices].floatValue)
            }

            return sampleFromLogitsArray(logits, temperature: temperature)

        } else {
            // Fallback to previous implementation
            return sampleFromGPT2Logits(logitsArray, lastTokenPosition: actualTokenCount - 1, temperature: temperature)
        }
    }

    private func sampleFromGPT2Logits(_ logitsArray: MLMultiArray, lastTokenPosition: Int, temperature: Double) -> Int32 {
        // Handle GPT-2 Core ML model output format
        let shape = logitsArray.shape.map { $0.intValue }
        print("GPT-2: Sampling from logits with shape: \(shape) at position: \(lastTokenPosition)")

        guard let expectedVocabSize = vocabularySize else {
            return sampleFromLogits(logitsArray, temperature: temperature)
        }

        if shape.count == 1 {
            // 1D output: might be flattened [seq_len * vocab_size] or [vocab_size]
            let totalSize = shape[0]

            if totalSize == expectedVocabSize {
                // Direct vocabulary size - use as is
                return sampleFromLogits(logitsArray, temperature: temperature)
            } else if totalSize == maxSequenceLength * expectedVocabSize {
                // Flattened [seq_len * vocab_size] - extract position
                return sampleFromFlattenedLogits(logitsArray, position: lastTokenPosition, vocabSize: expectedVocabSize, temperature: temperature)
            } else {
                // Unknown format - try as direct vocabulary
                return sampleFromLogits(logitsArray, temperature: temperature)
            }

        } else if shape.count == 2 {
            // 2D output: [seq_len, vocab_size]
            let seqLen = shape[0]
            let vocabSize = shape[1]

            if vocabSize == expectedVocabSize || vocabSize > 1000 {
                // Extract logits for the specific position
                var logits: [Float] = []
                let positionToUse = min(lastTokenPosition, seqLen - 1)

                for tokenId in 0..<vocabSize {
                    let indices = [positionToUse, tokenId] as [NSNumber]
                    let logitValue = logitsArray[indices].floatValue
                    logits.append(logitValue)
                }

                return sampleFromLogitsArray(logits, temperature: temperature)
            } else {
                // Might be [batch, vocab] - use last dimension
                return sampleFromLogits(logitsArray, temperature: temperature)
            }

        } else if shape.count == 3 {
            // 3D output: [batch, seq_len, vocab_size]
            let _ = shape[0]  // batchSize - unused but available if needed
            let seqLen = shape[1]
            let vocabSize = shape[2]

            // Extract logits for the specified position
            var logits: [Float] = []
            let positionToUse = min(lastTokenPosition, seqLen - 1)

            for tokenId in 0..<vocabSize {
                let indices = [0, positionToUse, tokenId] as [NSNumber]
                let logitValue = logitsArray[indices].floatValue
                logits.append(logitValue)
            }

            return sampleFromLogitsArray(logits, temperature: temperature)
        }

        // Fallback to generic sampling
        return sampleFromLogits(logitsArray, temperature: temperature)
    }

    private func sampleFromFlattenedLogits(_ logitsArray: MLMultiArray, position: Int, vocabSize: Int, temperature: Double) -> Int32 {
        // Extract logits from flattened array at specific position
        var logits: [Float] = []
        let startIndex = position * vocabSize

        for i in 0..<vocabSize {
            let flatIndex = startIndex + i
            if flatIndex < logitsArray.count {
                logits.append(logitsArray[flatIndex].floatValue)
            } else {
                logits.append(0.0) // Padding
            }
        }

        return sampleFromLogitsArray(logits, temperature: temperature)
    }

    private func sampleFromLogits(_ logitsArray: MLMultiArray, temperature: Double) -> Int32 {
        // Convert MLMultiArray to Swift array
        let count = logitsArray.count
        var logits: [Float] = []

        for i in 0..<count {
            logits.append(logitsArray[i].floatValue)
        }

        return sampleFromLogitsArray(logits, temperature: temperature)
    }

    private func sampleFromLogitsArray(_ logits: [Float], temperature: Double) -> Int32 {
        // If temperature is 0 or very close to 0, use greedy sampling (argmax)
        if temperature < 0.01 {
            // Greedy sampling - just pick the highest probability token
            if let maxIndex = logits.enumerated().max(by: { $0.element < $1.element })?.offset {
                return Int32(maxIndex)
            }
            return 0
        }

        var processedLogits = logits

        // Apply temperature scaling
        for i in 0..<processedLogits.count {
            processedLogits[i] = processedLogits[i] / Float(temperature)
        }

        // Apply softmax to get probabilities
        let maxLogit = processedLogits.max() ?? 0
        for i in 0..<processedLogits.count {
            processedLogits[i] = exp(processedLogits[i] - maxLogit)
        }

        let sumExp = processedLogits.reduce(0, +)
        guard sumExp > 0 else {
            // Fallback for edge case
            return Int32.random(in: 0..<Int32(processedLogits.count))
        }

        for i in 0..<processedLogits.count {
            processedLogits[i] = processedLogits[i] / sumExp
        }

        // Sample from the probability distribution
        let randomValue = Float.random(in: 0...1)
        var cumulativeProb: Float = 0

        for (index, prob) in processedLogits.enumerated() {
            cumulativeProb += prob
            if randomValue <= cumulativeProb {
                return Int32(index)
            }
        }

        // Fallback to the last token
        return Int32(processedLogits.count - 1)
    }
}
