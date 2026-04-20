// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

public struct WakeWordConfig: Sendable {
    public var model:     String
    public var keyword:   String
    public var threshold: Float
    public var preRollMs: Int

    public init(
        model: String = "kws-zipformer-gigaspeech",
        keyword: String = "hey mycroft",
        threshold: Float = 0.5,
        preRollMs: Int = 250
    ) {
        self.model     = model
        self.keyword   = keyword
        self.threshold = threshold
        self.preRollMs = preRollMs
    }
}
