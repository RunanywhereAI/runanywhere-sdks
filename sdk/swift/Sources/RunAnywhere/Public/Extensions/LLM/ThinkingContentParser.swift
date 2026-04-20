// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Static helpers for `ThinkingContentParser` so call sites can just write:
//
//     let answer = ThinkingContentParser.strip(from: raw)
//     let (think, answer) = ThinkingContentParser.extract(from: raw)
//
// The instance-method shape in `RunAnywhere+ToolCalling.swift` remains the
// canonical implementation; these are thin pass-throughs to match main.

import Foundation

public extension ThinkingContentParser {
    /// Static-method form of `extract(from:)`.
    static func extract(from text: String) -> (thinking: String, answer: String) {
        ThinkingContentParser().extract(from: text)
    }

    /// Static-method form of `strip(from:)`.
    static func strip(from text: String) -> String {
        ThinkingContentParser().strip(from: text)
    }
}
