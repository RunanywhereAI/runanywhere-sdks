// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

import Foundation

public struct RAGConfig: Sendable {
    public var embedModel:  String
    public var rerankModel: String
    public var llm:         String
    public var vectorStorePath: String
    public var retrieveK:   Int
    public var rerankTop:   Int

    public init(
        embedModel:  String = "bge-small-en-v1.5",
        rerankModel: String = "bge-reranker-v2-m3",
        llm:         String = "qwen3-4b",
        vectorStorePath: String = "",
        retrieveK:  Int = 24,
        rerankTop:  Int = 6
    ) {
        self.embedModel       = embedModel
        self.rerankModel      = rerankModel
        self.llm              = llm
        self.vectorStorePath  = vectorStorePath
        self.retrieveK        = retrieveK
        self.rerankTop        = rerankTop
    }
}
