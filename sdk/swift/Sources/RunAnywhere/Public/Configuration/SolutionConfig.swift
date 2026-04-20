// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

/// Top-level solution selector passed to `RunAnywhere.solution(_:)`.
public enum SolutionConfig: Sendable {
    case voiceAgent(VoiceAgentConfig)
    case rag(RAGConfig)
    case wakeWord(WakeWordConfig)
}
