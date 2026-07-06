import Foundation
import Darwin
import MLXRuntime
import RunAnywhere

private struct CatalogFile {
    let url: String
    let filename: String
    let isRequired: Bool

    init(_ url: String, _ filename: String, required: Bool = true) {
        self.url = url
        self.filename = filename
        self.isRequired = required
    }
}

private struct CatalogEntry {
    let id: String
    let alias: String
    let name: String
    let category: ModelCategory
    let framework: InferenceFramework
    let files: [CatalogFile]
    let memoryRequirement: Int64
    let contextLength: Int?
    let supportsThinking: Bool
}

private enum MLXCatalog {
    static let qwen3LLM = CatalogEntry(
        id: "mlx-qwen3-0.6b-4bit",
        alias: "mlx-qwen3",
        name: "Qwen3 0.6B 4-bit (MLX)",
        category: .language,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/added_tokens.json", "added_tokens.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/merges.txt", "merges.txt"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/special_tokens_map.json", "special_tokens_map.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/tokenizer.json", "tokenizer.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-0.6B-4bit/resolve/main/vocab.json", "vocab.json"),
        ],
        memoryRequirement: 351_383_618,
        contextLength: 4_096,
        supportsThinking: true
    )

    static let llamaLLM = CatalogEntry(
        id: "mlx-llama-3.2-1b-instruct-4bit",
        alias: "mlx-llama3.2",
        name: "Llama 3.2 1B Instruct 4-bit (MLX)",
        category: .language,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/special_tokens_map.json", "special_tokens_map.json"),
            .init("https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/tokenizer.json", "tokenizer.json"),
            .init("https://huggingface.co/mlx-community/Llama-3.2-1B-Instruct-4bit/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
        ],
        memoryRequirement: 712_575_975,
        contextLength: nil,
        supportsThinking: false
    )

    static let qwen2VLM = CatalogEntry(
        id: "mlx-qwen2-vl-2b-instruct-4bit",
        alias: "mlx-qwen2-vl",
        name: "Qwen2-VL 2B Instruct 4-bit (MLX)",
        category: .multimodal,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/added_tokens.json", "added_tokens.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/chat_template.json", "chat_template.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/merges.txt", "merges.txt"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/preprocessor_config.json", "preprocessor_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/special_tokens_map.json", "special_tokens_map.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/tokenizer.json", "tokenizer.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen2-VL-2B-Instruct-4bit/resolve/main/vocab.json", "vocab.json"),
        ],
        memoryRequirement: 1_261_853_827,
        contextLength: 2_048,
        supportsThinking: false
    )

    static let fastVLM = CatalogEntry(
        id: "mlx-fastvlm-0.5b-bf16",
        alias: "mlx-fastvlm",
        name: "FastVLM 0.5B bf16 (MLX)",
        category: .multimodal,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/added_tokens.json", "added_tokens.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/chat_template.jinja", "chat_template.jinja"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/llava_qwen.py", "llava_qwen.py", required: false),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/merges.txt", "merges.txt"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/preprocessor_config.json", "preprocessor_config.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/processing_fastvlm.py", "processing_fastvlm.py", required: false),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/processor_config.json", "processor_config.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/special_tokens_map.json", "special_tokens_map.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/tokenizer.json", "tokenizer.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
            .init("https://huggingface.co/mlx-community/FastVLM-0.5B-bf16/resolve/main/vocab.json", "vocab.json"),
        ],
        memoryRequirement: 1_256_926_974,
        contextLength: 2_048,
        supportsThinking: false
    )

    static let qwen3Embedding = CatalogEntry(
        id: "mlx-qwen3-embedding-0.6b-4bit-dwq",
        alias: "mlx-qwen3-embed",
        name: "Qwen3 Embedding 0.6B 4-bit DWQ (MLX)",
        category: .embedding,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/added_tokens.json", "added_tokens.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/chat_template.jinja", "chat_template.jinja"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/generation_config.json", "generation_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/merges.txt", "merges.txt"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/special_tokens_map.json", "special_tokens_map.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/tokenizer.json", "tokenizer.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-Embedding-0.6B-4bit-DWQ/resolve/main/vocab.json", "vocab.json"),
        ],
        memoryRequirement: 351_230_811,
        contextLength: nil,
        supportsThinking: false
    )

    static let qwen3ASR = CatalogEntry(
        id: "mlx-qwen3-asr-0.6b-8bit",
        alias: "mlx-qwen3-asr",
        name: "Qwen3-ASR 0.6B 8-bit (MLX)",
        category: .speechRecognition,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/chat_template.json", "chat_template.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/generation_config.json", "generation_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/merges.txt", "merges.txt"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/preprocessor_config.json", "preprocessor_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-ASR-0.6B-8bit/resolve/main/vocab.json", "vocab.json"),
        ],
        memoryRequirement: 1_010_773_761,
        contextLength: nil,
        supportsThinking: false
    )

    static let glmASR = CatalogEntry(
        id: "mlx-glm-asr-nano-2512-4bit",
        alias: "mlx-glm-asr",
        name: "GLM-ASR Nano 2512 4-bit (MLX)",
        category: .speechRecognition,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/configuration_glmasr.py", "configuration_glmasr.py", required: false),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/inference.py", "inference.py", required: false),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/modeling_audio.py", "modeling_audio.py", required: false),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/modeling_glmasr.py", "modeling_glmasr.py", required: false),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/tokenizer.json", "tokenizer.json"),
            .init("https://huggingface.co/mlx-community/GLM-ASR-Nano-2512-4bit/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
        ],
        memoryRequirement: 1_288_437_789,
        contextLength: nil,
        supportsThinking: false
    )

    static let qwen3TTS = CatalogEntry(
        id: "mlx-qwen3-tts-12hz-0.6b-base-8bit",
        alias: "mlx-qwen3-tts",
        name: "Qwen3-TTS 12Hz 0.6B Base 8-bit (MLX)",
        category: .speechSynthesis,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/generation_config.json", "generation_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/merges.txt", "merges.txt"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/preprocessor_config.json", "preprocessor_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/config.json", "speech_tokenizer/config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/configuration.json", "speech_tokenizer/configuration.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/model.safetensors", "speech_tokenizer/model.safetensors"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/speech_tokenizer/preprocessor_config.json", "speech_tokenizer/preprocessor_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
            .init("https://huggingface.co/mlx-community/Qwen3-TTS-12Hz-0.6B-Base-8bit/resolve/main/vocab.json", "vocab.json"),
        ],
        memoryRequirement: 1_991_299_138,
        contextLength: nil,
        supportsThinking: false
    )

    static let sopranoTTS = CatalogEntry(
        id: "mlx-soprano-1.1-80m-5bit",
        alias: "mlx-soprano",
        name: "Soprano 1.1 80M 5-bit (MLX)",
        category: .speechSynthesis,
        framework: .mlx,
        files: [
            .init("https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/config.json", "config.json"),
            .init("https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/generation_config.json", "generation_config.json"),
            .init("https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/model.safetensors", "model.safetensors"),
            .init("https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/model.safetensors.index.json", "model.safetensors.index.json"),
            .init("https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/special_tokens_map.json", "special_tokens_map.json"),
            .init("https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/tokenizer.json", "tokenizer.json"),
            .init("https://huggingface.co/mlx-community/Soprano-1.1-80M-5bit/resolve/main/tokenizer_config.json", "tokenizer_config.json"),
        ],
        memoryRequirement: 82_220_814,
        contextLength: nil,
        supportsThinking: false
    )

    static let entries = [
        qwen3LLM,
        llamaLLM,
        fastVLM,
        qwen2VLM,
        qwen3Embedding,
        qwen3ASR,
        glmASR,
        qwen3TTS,
        sopranoTTS,
    ]

    static func resolve(_ ref: String) -> CatalogEntry? {
        entries.first { $0.id == ref || $0.alias == ref }
    }
}

private enum CLIError: LocalizedError {
    case usage(String)
    case modelNotFound(String)
    case modelUnavailable(String)
    case invalidAudio(String)
    case missingMetalLibrary(String)

    var errorDescription: String? {
        switch self {
        case .usage(let message),
             .modelUnavailable(let message),
             .invalidAudio(let message),
             .missingMetalLibrary(let message):
            return message
        case .modelNotFound(let ref):
            return "Unknown MLX model '\(ref)'. Run `RunAnywhereMLXCLI list` to see supported refs."
        }
    }
}

@main
private struct RunAnywhereMLXCLI {
    static func main() async {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            if args.isEmpty || args.first == "help" || args.first == "--help" {
                printUsage()
                return
            }

            let command = args.removeFirst()
            if command == "modalities" {
                printModalities()
                return
            }

            try prepareMLXMetalLibrary()
            try configureDevSecureStore()
            try RunAnywhere.initialize(environment: .development)
            guard MLX.register(priority: 100) else {
                throw CLIError.modelUnavailable("MLX backend failed to register.")
            }
            RunAnywhere.setHfToken(ProcessInfo.processInfo.environment["HF_TOKEN"])
            await seedCatalog()

            switch command {
            case "list":
                try await listModels()
            case "pull", "download":
                try await requireArgument(args, command: command, usage: "<model>").withModel { entry in
                    _ = try await ensureDownloaded(entry)
                }
            case "load":
                try await requireArgument(args, command: command, usage: "<model>").withModel { entry in
                    let result = await load(entry)
                    printLoad(result)
                    if !result.success { throw CLIError.modelUnavailable(result.errorMessage) }
                    await unload(entry)
                }
            case "run":
                try await runText(args)
            case "embed":
                try await runEmbedding(args)
            case "vlm":
                try await runVLM(args)
            case "stt":
                try await runSTT(args)
            case "tts":
                try await runTTS(args)
            default:
                throw CLIError.usage("Unknown command '\(command)'.")
            }
        } catch {
            FileHandle.standardError.write(Data("error: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }
}

private func configureDevSecureStore() throws {
    let root = try FileManager.default.url(
        for: .applicationSupportDirectory,
        in: .userDomainMask,
        appropriateFor: nil,
        create: true
    )
    .appendingPathComponent("RunAnywhere/DevTools/MLXCLI/SecureStore", isDirectory: true)
    try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    setenv("RUNANYWHERE_SWIFT_SECURE_STORE", "file", 1)
    setenv("RUNANYWHERE_SWIFT_SECURE_STORE_DIR", root.path, 1)
    setenv("RUNANYWHERE_SWIFT_LOCAL_ONLY", "1", 1)
}

private extension String {
    func withModel(_ body: (CatalogEntry) async throws -> Void) async throws {
        guard let entry = MLXCatalog.resolve(self) else { throw CLIError.modelNotFound(self) }
        try await body(entry)
    }
}

private func prepareMLXMetalLibrary() throws {
    let fileManager = FileManager.default
    let executableURL = URL(fileURLWithPath: CommandLine.arguments[0])
    let executableDirectory = executableURL.deletingLastPathComponent()
    let colocatedURL = executableDirectory.appendingPathComponent("mlx.metallib")

    if fileManager.fileExists(atPath: colocatedURL.path) {
        return
    }

    if let override = ProcessInfo.processInfo.environment["RUNANYWHERE_MLX_METALLIB"], !override.isEmpty {
        try fileManager.copyItem(at: URL(fileURLWithPath: override), to: colocatedURL)
        return
    }

    guard let sourceURL = newestXcodeMLXMetalLibrary() else {
        throw CLIError.missingMetalLibrary(
            "MLX Metal library is missing. Build the Swift macOS/iOS app once with xcodebuild, or set RUNANYWHERE_MLX_METALLIB to a default.metallib path."
        )
    }

    try fileManager.copyItem(at: sourceURL, to: colocatedURL)
}

private func newestXcodeMLXMetalLibrary() -> URL? {
    let fileManager = FileManager.default
    let derivedData = fileManager.homeDirectoryForCurrentUser
        .appendingPathComponent("Library/Developer/Xcode/DerivedData")
    guard let enumerator = fileManager.enumerator(
        at: derivedData,
        includingPropertiesForKeys: [.contentModificationDateKey, .isRegularFileKey],
        options: [.skipsHiddenFiles]
    ) else {
        return nil
    }

    var best: (url: URL, modified: Date, priority: Int)?
    for case let url as URL in enumerator {
        guard url.lastPathComponent == "default.metallib",
              url.path.contains("mlx-swift_Cmlx.bundle")
        else {
            continue
        }

        let values = try? url.resourceValues(forKeys: [.contentModificationDateKey, .isRegularFileKey])
        guard values?.isRegularFile == true else {
            continue
        }

        let priority = url.path.contains("/Build/Products/Debug/mlx-swift_Cmlx.bundle/")
            ? 1
            : 0
        let modified = values?.contentModificationDate ?? .distantPast
        if best == nil || priority > best!.priority || (priority == best!.priority && modified > best!.modified) {
            best = (url, modified, priority)
        }
    }
    return best?.url
}

private func printUsage() {
    print(
        """
        RunAnywhereMLXCLI

        Commands:
          list
          modalities
          pull <model>
          load <model>
          run <model> <prompt>
          embed <model> <text>
          vlm <model> <image-path> [prompt]
          stt <model> <pcm16-or-wav-path>
          tts <model> <text> [output.wav]

        Smallest real MLX smoke test:
          RunAnywhereMLXCLI tts mlx-soprano "hello from mlx" /tmp/mlx-soprano.wav
        """
    )
}

private func printModalities() {
    let rows: [(String, String, String)] = [
        ("language", "mlx-qwen3", "LLM generate"),
        ("multimodal", "mlx-fastvlm", "VLM image + prompt"),
        ("embedding", "mlx-qwen3-embed", "text embeddings"),
        ("speechRecognition", "mlx-qwen3-asr", "16-bit mono PCM STT"),
        ("speechSynthesis", "mlx-soprano", "TTS float PCM"),
        ("voiceActivityDetection", "-", "unsupported by current MLX runtime"),
    ]
    for row in rows {
        print("\(row.0)\t\(row.1)\t\(row.2)")
    }
}

private func requireArgument(_ args: [String], command: String, usage: String) throws -> String {
    guard let first = args.first, !first.isEmpty else {
        throw CLIError.usage("Usage: RunAnywhereMLXCLI \(command) \(usage)")
    }
    return first
}

private func seedCatalog() async {
    for entry in MLXCatalog.entries {
        do {
            _ = try await RunAnywhere.registerModel(
                multiFile: descriptors(for: entry),
                id: entry.id,
                name: entry.name,
                framework: entry.framework,
                modality: entry.category,
                memoryRequirement: entry.memoryRequirement,
                contextLength: entry.contextLength,
                supportsThinking: entry.supportsThinking
            )
        } catch {
            print("warning: failed to register \(entry.id): \(error.localizedDescription)")
        }
    }
}

private func descriptors(for entry: CatalogEntry) -> [RAModelFileDescriptor] {
    entry.files.compactMap { file in
        guard let url = URL(string: file.url) else { return nil }
        var descriptor = RAModelFileDescriptor(url: url, filename: file.filename, isRequired: file.isRequired)
        descriptor.role = RunAnywhere.inferModelFileRole(filename: file.filename, modality: entry.category)
        return descriptor
    }
}

private func listModels() async throws {
    let result = await RunAnywhere.listModels()
    guard result.success else {
        throw CLIError.modelUnavailable(result.errorMessage.isEmpty ? "Model listing failed" : result.errorMessage)
    }

    let modelsByID = Dictionary(uniqueKeysWithValues: result.models.models.map { ($0.id, $0) })
    for entry in MLXCatalog.entries {
        let model = modelsByID[entry.id]
        let status = (model?.isDownloaded ?? false) ? "downloaded" : "remote"
        print("\(entry.id)\t\(entry.alias)\t\(entry.category.wireString)\t\(status)\t\(entry.name)")
    }
}

private func modelInfo(for entry: CatalogEntry) async throws -> RAModelInfo {
    var request = RAModelGetRequest()
    request.modelID = entry.id
    let result = await RunAnywhere.getModel(request)
    guard result.found else { throw CLIError.modelUnavailable("Model \(entry.id) is not registered") }
    return result.model
}

@discardableResult
private func ensureDownloaded(_ entry: CatalogEntry) async throws -> RAModelInfo {
    let model = try await modelInfo(for: entry)
    if model.isDownloaded {
        print("downloaded\t\(entry.id)\t\(model.localPath)")
        return model
    }

    print("downloading\t\(entry.id)\t\(entry.name)")
    let progress = try await RunAnywhere.downloadModel(model) { progress in
        let percent = Int(progress.overallProgress * 100)
        let file = progress.currentFileName.isEmpty ? "-" : progress.currentFileName
        print("progress\t\(percent)%\t\(progress.bytesDownloaded)/\(progress.totalBytes)\t\(file)")
    }
    print("downloaded\t\(entry.id)\t\(progress.localPath)")
    return try await modelInfo(for: entry)
}

private func load(_ entry: CatalogEntry) async -> RAModelLoadResult {
    var request = RAModelLoadRequest()
    request.modelID = entry.id
    request.category = entry.category
    request.framework = entry.framework
    request.forceReload = false
    request.validateAvailability = true
    return await RunAnywhere.loadModel(request)
}

private func printLoad(_ result: RAModelLoadResult) {
    if result.success {
        print("loaded\t\(result.modelID)\t\(result.category.wireString)\t\(result.framework.wireString)\t\(result.resolvedPath)")
    } else {
        print("load-failed\t\(result.modelID)\t\(result.errorMessage)")
    }
}

private func ensureReady(_ entry: CatalogEntry) async throws {
    _ = try await ensureDownloaded(entry)
    let result = await load(entry)
    printLoad(result)
    if !result.success {
        let message = result.errorMessage.isEmpty ? "Unable to load \(entry.id)" : result.errorMessage
        throw CLIError.modelUnavailable(message)
    }
}

private func unload(_ entry: CatalogEntry) async {
    var request = RAModelUnloadRequest()
    request.modelID = entry.id
    request.category = entry.category
    request.framework = entry.framework
    let result = await RunAnywhere.unloadModel(request)
    if result.success {
        print("unloaded\t\(entry.id)")
    } else if !result.errorMessage.isEmpty {
        print("unload-failed\t\(entry.id)\t\(result.errorMessage)")
    }
}

private func withReadyModel<T>(
    _ entry: CatalogEntry,
    operation: () async throws -> T
) async throws -> T {
    try await ensureReady(entry)
    do {
        let result = try await operation()
        await unload(entry)
        return result
    } catch {
        await unload(entry)
        throw error
    }
}

private func runText(_ args: [String]) async throws {
    guard args.count >= 2 else { throw CLIError.usage("Usage: RunAnywhereMLXCLI run <model> <prompt>") }
    guard let entry = MLXCatalog.resolve(args[0]) else { throw CLIError.modelNotFound(args[0]) }
    try await withReadyModel(entry) {
        var options = RALLMGenerationOptions.defaults()
        options.maxTokens = 64
        options.temperature = 0.2
        options.preferredFramework = .mlx
        options.disableThinking = true
        let result = try await RunAnywhere.generate(prompt: args.dropFirst().joined(separator: " "), options: options)
        print("text\t\(result.text)")
        print("tokens\t\(result.tokensGenerated)\ttps\t\(String(format: "%.2f", result.tokensPerSecond))")
    }
}

private func runEmbedding(_ args: [String]) async throws {
    guard args.count >= 2 else { throw CLIError.usage("Usage: RunAnywhereMLXCLI embed <model> <text>") }
    guard let entry = MLXCatalog.resolve(args[0]) else { throw CLIError.modelNotFound(args[0]) }
    try await withReadyModel(entry) {
        let result = try await RunAnywhere.embeddings.embed(
            args.dropFirst().joined(separator: " "),
            modelID: entry.id,
            options: .defaults()
        )
        let firstVector = result.vectors.first?.values ?? []
        let preview = firstVector.prefix(8).map { String(format: "%.5f", $0) }.joined(separator: ",")
        print("embedding-dim\t\(firstVector.count)")
        print("embedding-preview\t\(preview)")
    }
}

private func runVLM(_ args: [String]) async throws {
    guard args.count >= 2 else { throw CLIError.usage("Usage: RunAnywhereMLXCLI vlm <model> <image-path> [prompt]") }
    guard let entry = MLXCatalog.resolve(args[0]) else { throw CLIError.modelNotFound(args[0]) }

    let imageURL = URL(fileURLWithPath: args[1])
    guard FileManager.default.fileExists(atPath: imageURL.path) else {
        throw CLIError.usage("Image not found: \(imageURL.path)")
    }

    try await withReadyModel(entry) {
        let prompt = args.count > 2 ? args.dropFirst(2).joined(separator: " ") : "Describe the image briefly."
        var options = RAVLMGenerationOptions.defaults(prompt: prompt)
        options.maxTokens = 96
        options.temperature = 0.1
        let result = try await RunAnywhere.processImage(.fromFilePath(imageURL.path), options: options)
        print("vlm\t\(result.text)")
    }
}

private func runSTT(_ args: [String]) async throws {
    guard args.count >= 2 else { throw CLIError.usage("Usage: RunAnywhereMLXCLI stt <model> <pcm16-or-wav-path>") }
    guard let entry = MLXCatalog.resolve(args[0]) else { throw CLIError.modelNotFound(args[0]) }

    let audioURL = URL(fileURLWithPath: args[1])
    let audio = try readPCM16Mono(from: audioURL)
    try await withReadyModel(entry) {
        var options = RASTTOptions.defaults()
        options.audioFormat = .pcm
        options.sampleRate = Int32(audio.sampleRate)
        options.language = .auto
        options.detectLanguage = true
        let result = try await RunAnywhere.transcribe(audio: audio.data, options: options)
        print("stt\t\(result.text)")
        print("language\t\(result.languageCode.isEmpty ? result.language.wireString : result.languageCode)")
    }
}

private func runTTS(_ args: [String]) async throws {
    guard args.count >= 2 else { throw CLIError.usage("Usage: RunAnywhereMLXCLI tts <model> <text> [output.wav]") }
    guard let entry = MLXCatalog.resolve(args[0]) else { throw CLIError.modelNotFound(args[0]) }
    let outputPath = args.count >= 3 ? args.last! : "/tmp/\(entry.id).wav"
    let textParts = args.dropFirst().dropLast(args.count >= 3 ? 1 : 0)
    try await withReadyModel(entry) {
        var options = RATTSOptions.defaults()
        options.audioFormat = .pcm
        let result = try await RunAnywhere.synthesize(textParts.joined(separator: " "), options: options)
        let sampleRate = Int(result.sampleRate > 0 ? result.sampleRate : options.sampleRate)
        let wav = try pcmFloat32ToPCM16Wav(result.audioData, sampleRate: sampleRate)
        try wav.write(to: URL(fileURLWithPath: outputPath), options: .atomic)
        print("tts\t\(outputPath)\t\(wav.count) bytes\t\(sampleRate) hz")
    }
}

private struct PCM16Audio {
    let data: Data
    let sampleRate: Int
}

private func readPCM16Mono(from url: URL) throws -> PCM16Audio {
    let data = try Data(contentsOf: url)
    guard data.count >= 12 else { throw CLIError.invalidAudio("Audio file is empty or too small: \(url.path)") }
    if data.prefix(4) != Data("RIFF".utf8) {
        return PCM16Audio(data: data, sampleRate: 16_000)
    }

    var offset = 12
    var sampleRate = 16_000
    var channels = 1
    var bitsPerSample = 16
    var audioFormat = 1
    var pcmData: Data?

    while offset + 8 <= data.count {
        let chunkID = String(decoding: data[offset..<offset + 4], as: UTF8.self)
        let chunkSize = Int(readUInt32LE(data, offset + 4))
        let chunkStart = offset + 8
        let chunkEnd = min(chunkStart + chunkSize, data.count)
        if chunkID == "fmt ", chunkEnd - chunkStart >= 16 {
            audioFormat = Int(readUInt16LE(data, chunkStart))
            channels = Int(readUInt16LE(data, chunkStart + 2))
            sampleRate = Int(readUInt32LE(data, chunkStart + 4))
            bitsPerSample = Int(readUInt16LE(data, chunkStart + 14))
        } else if chunkID == "data" {
            pcmData = data[chunkStart..<chunkEnd]
        }
        offset = chunkEnd + (chunkSize % 2)
    }

    guard audioFormat == 1, bitsPerSample == 16 else {
        throw CLIError.invalidAudio("Only PCM16 WAV input is supported for MLX STT.")
    }
    guard let pcmData, !pcmData.isEmpty else {
        throw CLIError.invalidAudio("WAV file has no data chunk: \(url.path)")
    }
    if channels == 1 {
        return PCM16Audio(data: pcmData, sampleRate: sampleRate)
    }
    guard channels == 2 else {
        throw CLIError.invalidAudio("Only mono or stereo PCM16 WAV input is supported.")
    }
    return PCM16Audio(data: downmixStereoPCM16ToMono(pcmData), sampleRate: sampleRate)
}

private func downmixStereoPCM16ToMono(_ stereo: Data) -> Data {
    var mono = Data(capacity: stereo.count / 2)
    stereo.withUnsafeBytes { rawBuffer in
        let samples = rawBuffer.bindMemory(to: Int16.self)
        for index in stride(from: 0, to: samples.count - 1, by: 2) {
            let mixed = (Int32(samples[index]) + Int32(samples[index + 1])) / 2
            var sample = Int16(clamping: mixed).littleEndian
            withUnsafeBytes(of: &sample) { mono.append(contentsOf: $0) }
        }
    }
    return mono
}

private func pcmFloat32ToPCM16Wav(_ floatData: Data, sampleRate: Int) throws -> Data {
    guard !floatData.isEmpty, floatData.count.isMultiple(of: MemoryLayout<Float>.stride) else {
        throw CLIError.invalidAudio("TTS returned no Float32 PCM audio.")
    }
    var pcm16 = Data(capacity: floatData.count / 2)
    floatData.withUnsafeBytes { rawBuffer in
        let samples = rawBuffer.bindMemory(to: Float.self)
        for sample in samples {
            let clipped = max(-1.0, min(1.0, sample))
            var intSample = Int16(clamping: Int32(clipped * Float(Int16.max))).littleEndian
            withUnsafeBytes(of: &intSample) { pcm16.append(contentsOf: $0) }
        }
    }
    return wavHeader(pcmByteCount: pcm16.count, sampleRate: sampleRate) + pcm16
}

private func wavHeader(pcmByteCount: Int, sampleRate: Int) -> Data {
    let channels = 1
    let bitsPerSample = 16
    let blockAlign = channels * bitsPerSample / 8
    let byteRate = sampleRate * blockAlign

    var wav = Data(capacity: 44)
    wav.append(Data("RIFF".utf8))
    appendUInt32LE(36 + pcmByteCount, to: &wav)
    wav.append(Data("WAVEfmt ".utf8))
    appendUInt32LE(16, to: &wav)
    appendUInt16LE(1, to: &wav)
    appendUInt16LE(channels, to: &wav)
    appendUInt32LE(sampleRate, to: &wav)
    appendUInt32LE(byteRate, to: &wav)
    appendUInt16LE(blockAlign, to: &wav)
    appendUInt16LE(bitsPerSample, to: &wav)
    wav.append(Data("data".utf8))
    appendUInt32LE(pcmByteCount, to: &wav)
    return wav
}

private func readUInt16LE(_ data: Data, _ offset: Int) -> UInt16 {
    UInt16(data[offset]) | (UInt16(data[offset + 1]) << 8)
}

private func readUInt32LE(_ data: Data, _ offset: Int) -> UInt32 {
    UInt32(data[offset])
        | (UInt32(data[offset + 1]) << 8)
        | (UInt32(data[offset + 2]) << 16)
        | (UInt32(data[offset + 3]) << 24)
}

private func appendUInt16LE(_ value: Int, to data: inout Data) {
    var little = UInt16(value).littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}

private func appendUInt32LE(_ value: Int, to data: inout Data) {
    var little = UInt32(value).littleEndian
    withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
}
