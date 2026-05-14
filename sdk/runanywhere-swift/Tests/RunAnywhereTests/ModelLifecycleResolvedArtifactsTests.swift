//
//  ModelLifecycleResolvedArtifactsTests.swift
//  RunAnywhere SDK
//
//  Focused tests for lifecycle resolved_artifacts role helpers.
//

import XCTest

@testable import RunAnywhere

final class ModelLifecycleResolvedArtifactsTests: XCTestCase {
    func testLoadResultResolvesPrimaryAndVisionProjectorByRole() {
        let result = makeLoadResult(artifacts: [
            descriptor(role: .visionProjector, localPath: "/models/qwen/mmproj.gguf"),
            descriptor(role: .primaryModel, localPath: "/models/qwen/model.gguf")
        ])

        XCTAssertEqual(result.resolvedPrimaryModelPath, "/models/qwen/model.gguf")
        XCTAssertEqual(result.resolvedVisionProjectorPath, "/models/qwen/mmproj.gguf")
        XCTAssertNil(result.resolvedModelFilePath(role: .tokenizer))
    }

    func testCurrentModelResultResolvesArtifactsByRole() {
        var result = RACurrentModelResult()
        result.found = true
        result.modelID = "qwen-vl"
        result.resolvedArtifacts = [
            descriptor(role: .primaryModel, localPath: "/models/qwen/model.gguf"),
            descriptor(role: .visionProjector, localPath: "/models/qwen/mmproj.gguf")
        ]

        XCTAssertEqual(result.resolvedPrimaryModelPath, "/models/qwen/model.gguf")
        XCTAssertEqual(result.resolvedVisionProjectorPath, "/models/qwen/mmproj.gguf")
    }

    func testRoleHelpersDoNotFallBackToResolvedPathOrDescriptorNames() {
        var result = makeLoadResult(artifacts: [
            descriptor(role: .primaryModel, localPath: "", filename: "model.gguf")
        ])
        result.resolvedPath = "/models/qwen/model.gguf"

        XCTAssertNil(result.resolvedPrimaryModelPath)
    }

    func testLifecyclePrimaryArtifactPathFallsBackToResolvedPathForConsumers() {
        var result = makeLoadResult(artifacts: [])
        result.resolvedPath = "/models/diffusion/model.mlpackage"

        XCTAssertEqual(result.lifecyclePrimaryArtifactPath, "/models/diffusion/model.mlpackage")
    }

    /// D-6: RAGConfiguration carries model ids and the path resolution is
    /// owned by commons. `resolvingLifecycleArtifacts` now only stamps the
    /// resolved-model ids onto the configuration; filesystem paths never
    /// appear on the Swift-side proto message.
    func testRAGConfigurationUsesLifecycleModelIds() throws {
        let embedding = makeLoadResult(
            modelId: "minilm",
            category: .embedding,
            artifacts: [
                descriptor(role: .primaryModel, localPath: "/models/minilm/model.onnx"),
                descriptor(role: .vocabulary, localPath: "/models/minilm/vocab.txt")
            ]
        )
        let llm = makeLoadResult(
            modelId: "tinyllama",
            category: .language,
            artifacts: [
                descriptor(role: .primaryModel, localPath: "/models/tinyllama/model.gguf")
            ]
        )

        let config = try RARAGConfiguration.defaults()
            .resolvingLifecycleArtifacts(embedding: embedding, llm: llm)

        XCTAssertEqual(config.embeddingModelID, "minilm")
        XCTAssertEqual(config.llmModelID, "tinyllama")
    }

    private func makeLoadResult(
        modelId: String = "qwen-vl",
        category: RAModelCategory = .multimodal,
        artifacts: [RAModelFileDescriptor]
    ) -> RAModelLoadResult {
        var result = RAModelLoadResult()
        result.success = true
        result.modelID = modelId
        result.category = category
        result.framework = .llamaCpp
        result.resolvedArtifacts = artifacts
        return result
    }

    private func descriptor(
        role: RAModelFileRole,
        localPath: String,
        filename: String = ""
    ) -> RAModelFileDescriptor {
        var descriptor = RAModelFileDescriptor()
        descriptor.role = role
        descriptor.localPath = localPath
        descriptor.filename = filename
        return descriptor
    }
}
