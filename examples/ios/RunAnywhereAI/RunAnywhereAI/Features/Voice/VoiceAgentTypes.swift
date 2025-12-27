//
//  VoiceAgentTypes.swift
//  RunAnywhereAI
//
//  Supporting types for VoiceAgentViewModel.
//  Extracted to reduce file length and improve organization.
//

import SwiftUI
import RunAnywhere

// MARK: - Model Selection State

/// Represents a selected model with its framework, name, and ID
/// Used instead of tuple to comply with SwiftLint large_tuple rule
struct SelectedModelInfo: Equatable {
    let framework: InferenceFramework
    let name: String
    let id: String
}

// MARK: - Session State

/// Represents the current state of the voice session
enum VoiceSessionState: Equatable {
    case disconnected       // Not connected, ready to start
    case connecting         // Initializing session
    case connected          // Session established, idle
    case listening          // Actively listening for speech
    case processing         // Processing transcribed speech
    case speaking           // Playing back TTS response
    case error(String)      // Error state

    var displayName: String {
        switch self {
        case .disconnected: return "Ready"
        case .connecting: return "Connecting"
        case .connected: return "Ready"
        case .listening: return "Listening"
        case .processing: return "Thinking"
        case .speaking: return "Speaking"
        case .error: return "Error"
        }
    }
}

// MARK: - Status Colors

/// Color indicator for status
enum StatusColor {
    case gray, orange, green, red, blue

    var swiftUIColor: Color {
        switch self {
        case .gray: return .gray
        case .orange: return AppColors.primaryAccent
        case .green: return .green
        case .red: return .red
        case .blue: return AppColors.primaryAccent
        }
    }
}

/// Color for microphone button
enum MicButtonColor {
    case orange, red, blue, green

    var swiftUIColor: Color {
        switch self {
        case .orange: return AppColors.primaryAccent
        case .red: return .red
        case .blue: return AppColors.primaryAccent
        case .green: return .green
        }
    }
}

// MARK: - Model Type

/// Enum for identifying model types in VoiceAgentViewModel
enum ModelTypeEnum {
    case stt
    case llm
    case tts
}
