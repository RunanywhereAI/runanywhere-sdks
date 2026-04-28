/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * JVM/Android actual implementations for RAG (Retrieval-Augmented Generation).
 *
 * Wave 2 KOTLIN: Stubbed to notImplemented while the proto-canonical RAG bridge
 * is being wired up. The legacy hand-rolled RAGConfiguration / RAGQueryOptions /
 * RAGResult types have been replaced with proto types.
 */

package com.runanywhere.sdk.public.extensions

import ai.runanywhere.proto.v1.RAGConfiguration
import ai.runanywhere.proto.v1.RAGQueryOptions
import ai.runanywhere.proto.v1.RAGResult
import com.runanywhere.sdk.foundation.errors.SDKException
import com.runanywhere.sdk.public.RunAnywhere

actual suspend fun RunAnywhere.ragCreatePipeline(config: RAGConfiguration) {
    throw SDKException.notImplemented("RAG pipeline (proto-canonical) is being wired up")
}

actual suspend fun RunAnywhere.ragDestroyPipeline() {
    throw SDKException.notImplemented("RAG pipeline (proto-canonical) is being wired up")
}

actual suspend fun RunAnywhere.ragIngest(text: String, metadataJson: String?) {
    throw SDKException.notImplemented("RAG pipeline (proto-canonical) is being wired up")
}

actual suspend fun RunAnywhere.ragClearDocuments() {
    throw SDKException.notImplemented("RAG pipeline (proto-canonical) is being wired up")
}

actual val RunAnywhere.ragDocumentCount: Int
    get() = 0

actual suspend fun RunAnywhere.ragQuery(
    question: String,
    options: RAGQueryOptions?,
): RAGResult {
    throw SDKException.notImplemented("RAG pipeline (proto-canonical) is being wired up")
}
