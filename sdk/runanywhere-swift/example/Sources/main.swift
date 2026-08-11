//
//  main.swift
//  runanywhere-minimal
//
//  The smallest useful RunAnywhere consumer: register a backend, initialize,
//  put one model in the catalog, stream one completion to stdout.
//
//  Download and load are automatic — passing `options.model` is enough. Only
//  the catalog entry has to exist first (`ensureLoaded` rejects an unknown id
//  with "Model '…' is not registered").
//

import Foundation
import LlamaCPPRuntime
import RunAnywhere

let modelId = "smollm2-360m-q8_0"
let modelURL = "https://huggingface.co/prithivMLmods/SmolLM2-360M-GGUF/resolve/main/SmolLM2-360M.Q8_0.gguf"
let promptArgument = CommandLine.arguments.dropFirst().joined(separator: " ")
let prompt = promptArgument.isEmpty ? "Name three colours." : promptArgument

LlamaCPP.register()
try RunAnywhere.initialize(environment: .development)

// `try?`: re-running the CLI re-registers the same id, which is not an error
// worth failing the run over.
_ = try? await RunAnywhere.models.register(
    .url(
        modelURL,
        name: "SmolLM2 360M Q8_0",
        framework: .llamaCpp,
        category: .language,
        id: modelId,
        memoryRequirementBytes: 386_404_416
    )
)

let stream = try await RunAnywhere.llm.generateStream(
    prompt: prompt,
    options: LlmOptions(model: modelId, maxOutputTokens: 128)
)

for try await event in stream {
    switch event {
    case .textDelta(_, _, _, _, let text):
        FileHandle.standardOutput.write(Data(text.utf8))
    case .completed(_, let result):
        print("\n--- \(result.outputTokens) tokens, \(result.tokensPerSecond) tok/s, model \(result.model)")
    case .failed(_, _, let error):
        FileHandle.standardError.write(Data("\ngeneration failed: \(error)\n".utf8))
        exit(1)
    default:
        break
    }
}
