//
//  ComponentProtocols.swift
//  RunAnywhere SDK
//
//  Core Swift protocols for components.  SDKComponent is a typealias for the
//  canonical proto-generated RASDKComponent (sdk_events.proto).
//

import Foundation
import SwiftProtobuf

// MARK: - Component Protocols

public protocol ComponentConfiguration: Sendable {
    var modelId: String? { get }
    var preferredFramework: InferenceFramework? { get }
    func validate() throws
}

extension ComponentConfiguration {
    public var preferredFramework: InferenceFramework? { nil }
}

public protocol ComponentOutput: Sendable {
    var timestamp: Date { get }
}

// MARK: - SDKComponent

public typealias SDKComponent = RASDKComponent

public extension RASDKComponent {
    var displayName: String {
        switch self {
        case .llm:                return "Language Model"
        case .vlm:                return "Vision Language Model"
        case .stt:                return "Speech to Text"
        case .tts:                return "Text to Speech"
        case .vad:                return "Voice Activity Detection"
        case .voiceAgent:         return "Voice Agent"
        case .embeddings:         return "Embedding"
        case .diffusion:          return "Image Generation"
        case .rag:                return "Retrieval-Augmented Generation"
        case .wakeword:           return "Wake Word"
        case .speakerDiarization: return "Speaker Diarization"
        default:                  return "Unknown"
        }
    }

    var analyticsKey: String {
        switch self {
        case .llm:                return "llm"
        case .vlm:                return "vlm"
        case .stt:                return "stt"
        case .tts:                return "tts"
        case .vad:                return "vad"
        case .voiceAgent:         return "voice"
        case .embeddings:         return "embedding"
        case .diffusion:          return "diffusion"
        case .rag:                return "rag"
        case .wakeword:           return "wakeword"
        case .speakerDiarization: return "speaker_diarization"
        default:                  return "unknown"
        }
    }
}
