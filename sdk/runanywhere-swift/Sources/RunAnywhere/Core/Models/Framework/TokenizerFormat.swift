import Foundation

/// Tokenizer formats supported
public enum TokenizerFormat: String, CaseIterable {
    case huggingFace = "huggingface"
    case sentencePiece = "sentencepiece"
    case wordPiece = "wordpiece"
    case bpe = "bpe"
    case tflite = "tflite"
    case coreML = "coreml"
    case custom = "custom"
}
