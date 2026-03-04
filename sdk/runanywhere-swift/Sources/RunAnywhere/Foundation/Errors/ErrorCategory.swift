//
//  ErrorCategory.swift
//  RunAnywhere
//
//  Created by RunAnywhere on 2024.
//

import Foundation

/// Category of the error indicating which component/modality it belongs to.
public enum ErrorCategory: String, Sendable, CaseIterable {
    /// General SDK errors not specific to any component
    case general

    /// Speech-to-Text component errors
    case stt

    /// Text-to-Speech component errors
    case tts

    /// Large Language Model component errors
    case llm

    /// Voice Activity Detection component errors
    case vad

    /// Vision Language Model component errors
    case vlm

    /// Speaker Diarization component errors
    case speakerDiarization

    /// Wake Word detection component errors
    case wakeWord

    /// Voice Agent component errors
    case voiceAgent

    /// Retrieval-Augmented Generation component errors
    case rag

    /// Model download and management errors
    case download

    /// File system and storage errors
    case fileManagement

    /// Network and API communication errors
    case network

    /// Authentication and authorization errors
    case authentication

    /// Security and keychain errors
    case security

    /// ONNX and other runtime errors
    case runtime
}
