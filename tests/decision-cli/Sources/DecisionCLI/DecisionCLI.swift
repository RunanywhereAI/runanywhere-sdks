//
//  DecisionCLI.swift
//  DecisionCLI
//
//  Local model smoke + parity tool. Two ways to exercise the SDK end to end
//  against on-device checkpoints:
//
//    run   — the canonical ticket (team/refund/urgency) through the decision
//            component. Works on both backends; the JSON output feeds `compare`
//            so llamacpp and MLX can be diffed for probability parity.
//    chat  — a plain text generation through `RunAnywhere.llm`, the same path
//            an app uses, to prove the base stack (load → prefill → decode)
//            independent of the decision head.
//
//  `--model` takes a filesystem path or a catalog id (see `models`); catalog
//  ids download once into Application Support unless DECISION_CLI_MODELS_DIR
//  points elsewhere.
//

import CRACommons
import Foundation
import LlamaCPPRuntime
import MLXRuntime
import RunAnywhere

// MARK: - Canonical case

/// The ticket every decision engine is checked against. Mirrors the fixture in
/// `tests/decision-cli/fixtures/ticket.json`, captured from the checkpoint
/// reference implementation.
private let canonicalState = #"{"ticket":"I was charged twice. Please refund the extra payment."}"#

private let canonicalQuestions: [RunAnywhere.DecisionQuestion] = [
    .init(
        id: "team", type: .choice, instructions: "Which team?",
        options: [
            .init(key: "billing", description: "Payments and refunds"),
            .init(key: "technical", description: "Bugs"),
            .init(key: "other", description: "None of the above"),
        ]),
    .init(
        id: "refund", type: .noul,
        instructions: "Does the customer ask for a refund?",
        options: [
            .init(key: "true", description: "The customer asks for a refund"),
            .init(key: "false", description: "No refund is requested"),
        ]),
    .init(
        id: "urgency", type: .score, instructions: "How urgent?",
        options: [
            .init(key: "0", description: "Routine"),
            .init(key: "1", description: "Soon"),
            .init(key: "2", description: "Urgent"),
        ]),
]

// MARK: - Output shapes

/// One answered field, in a stable machine-readable shape for `compare`.
private struct AnswerRecord: Codable, Equatable {
    let id: String
    let type: String
    let choice: String?
    let noul: Float?
    let score: Float?
    let confidence: Float
    let probabilities: [String: Float]
}

private struct RunRecord: Codable {
    let framework: String
    let model: String
    let answers: [AnswerRecord]
    /// Prompt-wording version the model served; optional so JSON written before
    /// the field existed still decodes.
    var promptFormatVersion: UInt32?
}

enum CLIError: Error, LocalizedError {
    case usage(String)
    case unsupportedFramework(String)
    case missingArgument(String)
    case runFailed(String)
    case comparisonFailed(String)

    var errorDescription: String? {
        switch self {
        case .usage(let text): text
        case .unsupportedFramework(let name):
            "Unknown framework '\(name)'. Use 'mlx' or 'llamacpp'."
        case .missingArgument(let name): "Missing required argument: \(name)"
        case .runFailed(let detail): "Decision run failed: \(detail)"
        case .comparisonFailed(let detail): detail
        }
    }
}

// MARK: - Entry point

@main
@MainActor
private struct DecisionCLI {
    static func main() async {
        do {
            var args = Array(CommandLine.arguments.dropFirst())
            guard let command = args.first else {
                printUsage()
                exit(64)
            }
            args.removeFirst()

            switch command {
            case "run":
                try await run(args)
            case "chat":
                try await chat(args)
            case "compare":
                try compare(args)
            case "models":
                printCatalog()
            case "help", "--help", "-h":
                printUsage()
            default:
                throw CLIError.usage("unknown command '\(command)'")
            }
        } catch {
            FileHandle.standardError.write(Data("decision-cli: \(error.localizedDescription)\n".utf8))
            exit(1)
        }
    }

    // MARK: run

    private static func run(_ args: [String]) async throws {
        let framework = try value(of: "--framework", in: args)
            ?? { throw CLIError.missingArgument("--framework") }()
        let modelPath = try resolveModel(args)
        let outputPath = value(of: "--out", in: args)
        let timeoutSeconds = Double(value(of: "--timeout", in: args) ?? "300") ?? 300

        let frameworkKind: InferenceFramework
        let modelID: String
        switch framework.lowercased() {
        case "mlx":
            frameworkKind = .mlx
            modelID = "decision-mlx"
        case "llamacpp", "llama.cpp", "gguf":
            frameworkKind = .llamaCpp
            modelID = "decision-llamacpp"
        default:
            throw CLIError.unsupportedFramework(framework)
        }

        try configureDevSecureStore()
        LlamaCPP.register()
        MLX.register()
        try RunAnywhere.initialize(environment: .development)

        try await registerAndLoad(
            modelPath: modelPath, framework: frameworkKind, modelID: modelID,
            category: .decision)

        let pin = value(of: "--prompt-format-version", in: args).flatMap(UInt32.init)
        let started = Date()
        let run = try await withTimeout(seconds: timeoutSeconds) {
            try await RunAnywhere.decision.decideResult(
                state: canonicalState, questions: canonicalQuestions,
                promptFormatVersion: pin)
        }
        let elapsed = Date().timeIntervalSince(started)

        let record = RunRecord(
            framework: framework.lowercased(),
            model: modelPath,
            answers: run.answers.map(answerRecord),
            promptFormatVersion: run.promptFormatVersion)
        try emit(record, to: outputPath)
        printReport(record, elapsed: elapsed)
    }

    // MARK: chat

    /// Text-generation smoke test: proves the whole local stack (load → prefill
    /// → decode) on a plain LLM, independent of the decision path. Uses the
    /// same SDK surface an app would.
    private static func chat(_ args: [String]) async throws {
        let framework = try value(of: "--framework", in: args)
            ?? { throw CLIError.missingArgument("--framework") }()
        let modelPath = try resolveModel(args)
        let prompt = value(of: "--prompt", in: args)
            ?? "Write one sentence about why running AI locally matters."
        let maxTokens = Int(value(of: "--max-tokens", in: args) ?? "64") ?? 64
        let timeoutSeconds = Double(value(of: "--timeout", in: args) ?? "300") ?? 300

        let frameworkKind: InferenceFramework
        let modelID: String
        switch framework.lowercased() {
        case "mlx":
            frameworkKind = .mlx
            modelID = "chat-mlx"
        case "llamacpp", "llama.cpp", "gguf":
            frameworkKind = .llamaCpp
            modelID = "chat-llamacpp"
        default:
            throw CLIError.unsupportedFramework(framework)
        }

        try configureDevSecureStore()
        LlamaCPP.register()
        MLX.register()
        try RunAnywhere.initialize(environment: .development)

        try await registerAndLoad(
            modelPath: modelPath, framework: frameworkKind, modelID: modelID,
            category: .language)

        var options = LlmOptions()
        options.maxOutputTokens = maxTokens
        options.temperature = 0.0
        let generateOptions = options

        print("prompt: \(prompt)")
        let started = Date()
        let result = try await withTimeout(seconds: timeoutSeconds) {
            try await RunAnywhere.llm.generate(prompt: prompt, options: generateOptions)
        }
        let elapsed = Date().timeIntervalSince(started)

        print("reply: \(result.text.trimmingCharacters(in: .whitespacesAndNewlines))")
        print(String(
            format: "tokens: in=%d out=%d | %.2fs | %.2f tok/s",
            result.inputTokens, result.outputTokens, elapsed, result.tokensPerSecond))
        if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw CLIError.runFailed("model produced no text")
        }
    }

    // MARK: compare

    private static func compare(_ args: [String]) throws {
        let leftPath = try value(of: "--a", in: args)
            ?? { throw CLIError.missingArgument("--a") }()
        let rightPath = try value(of: "--b", in: args)
            ?? { throw CLIError.missingArgument("--b") }()
        let tolerance = Float(value(of: "--tolerance", in: args) ?? "0.01") ?? 0.01

        let left = try decodeRun(at: leftPath)
        let right = try decodeRun(at: rightPath)
        guard left.answers.count == right.answers.count else {
            throw CLIError.comparisonFailed(
                "answer count differs: \(left.answers.count) vs \(right.answers.count)")
        }

        var maxDelta = Float(0)
        var failures: [String] = []
        for (lhs, rhs) in zip(left.answers, right.answers) {
            guard lhs.id == rhs.id else {
                throw CLIError.comparisonFailed(
                    "field order differs: '\(lhs.id)' vs '\(rhs.id)'")
            }
            for key in Set(lhs.probabilities.keys).union(rhs.probabilities.keys) {
                let delta = abs(lhs.probabilities[key, default: 0] - rhs.probabilities[key, default: 0])
                maxDelta = max(maxDelta, delta)
                if delta > tolerance {
                    failures.append(
                        String(format: "%@.%@ delta %.4f exceeds tolerance %.4f",
                               lhs.id, key, delta, tolerance))
                }
            }
            if lhs.choice != rhs.choice {
                failures.append("\(lhs.id): choice '\(lhs.choice ?? "-")' vs '\(rhs.choice ?? "-")'")
            }
        }

        print(String(format: "max probability delta: %.5f (tolerance %.4f)", maxDelta, tolerance))
        if failures.isEmpty {
            print("PARITY OK: \(left.framework) vs \(right.framework)")
        } else {
            for failure in failures { print("MISMATCH: \(failure)") }
            throw CLIError.comparisonFailed("\(failures.count) mismatched field(s)")
        }
    }

    // MARK: models

    private static func printCatalog() {
        print("available models (pass an id to --model, or a filesystem path):")
        for entry in Catalog.entries {
            let kind = entry.isDecision ? "decision" : "text"
            print(String(
                format: "  %-24s %-10s %-9s %6.0f MB  %@",
                (entry.id as NSString).utf8String!, (entry.framework as NSString).utf8String!,
                (kind as NSString).utf8String!,
                Double(entry.sizeBytes) / 1_000_000.0,
                entry.url ?? "\(entry.repo ?? "")@\(entry.revision ?? "main")"))
        }
    }

    // MARK: Model registration

    private static func registerAndLoad(
        modelPath: String,
        framework: InferenceFramework,
        modelID: String,
        category: ModelCategory
    ) async throws {
        let url = URL(fileURLWithPath: modelPath)
        var info = RAModelInfo()
        info.id = modelID
        info.name = modelID
        info.framework = framework
        info.category = category
        info.localPath = modelPath

        // MLX models are directories, GGUF models are single files; the
        // import path handles both when the source is local and stable.
        var request = RAModelImportRequest()
        request.model = info
        request.sourcePath = url.path
        request.copyIntoManagedStorage = false
        request.overwriteExisting = true
        _ = try await RunAnywhere.importModel(request)

        let loaded = try await RunAnywhere.models.load(id: modelID)
        guard loaded.category == category else {
            throw CLIError.runFailed(
                "model loaded as \(loaded.category) instead of \(category)")
        }
    }

    /// `--model` accepts a catalog id/alias (resolved + downloaded if absent) or
    /// a filesystem path to an existing checkpoint.
    private static func resolveModel(_ args: [String]) throws -> String {
        let raw = try value(of: "--model", in: args)
            ?? { throw CLIError.missingArgument("--model") }()
        if FileManager.default.fileExists(atPath: raw) {
            return raw
        }
        guard let entry = Catalog.resolve(raw) else {
            throw CLIError.runFailed(
                "no such file and no catalog entry '\(raw)' (run `decision-cli models`)")
        }
        let root = try catalogRoot()
        if let local = Catalog.localPath(for: entry, root: root) {
            print("using cached \(entry.id): \(local)")
            return local
        }
        print("downloading \(entry.id) into \(root) ...")
        let path = try Catalog.download(entry, root: root)
        print("downloaded: \(path)")
        return path
    }

    private static func catalogRoot() throws -> String {
        if let override = ProcessInfo.processInfo.environment["DECISION_CLI_MODELS_DIR"] {
            return override
        }
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask,
            appropriateFor: nil, create: true
        )
        .appendingPathComponent("RunAnywhere/DevTools/DecisionCLI/Models", isDirectory: true)
        .path
        try FileManager.default.createDirectory(
            atPath: root, withIntermediateDirectories: true)
        return root
    }

    // MARK: Helpers

    private static func answerRecord(_ answer: RunAnywhere.DecisionAnswer) -> AnswerRecord {
        let type: String
        switch answer.type {
        case .choice: type = "choice"
        case .noul: type = "noul"
        case .score: type = "score"
        }
        return AnswerRecord(
            id: answer.id, type: type, choice: answer.choice,
            noul: answer.noul, score: answer.score,
            confidence: answer.confidence,
            probabilities: answer.probabilities)
    }

    private static func emit(_ record: RunRecord, to path: String?) throws {
        guard let path else { return }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        try encoder.encode(record).write(to: URL(fileURLWithPath: path))
    }

    private static func decodeRun(at path: String) throws -> RunRecord {
        let data = try Data(contentsOf: URL(fileURLWithPath: path))
        return try JSONDecoder().decode(RunRecord.self, from: data)
    }

    private static func printReport(_ record: RunRecord, elapsed: TimeInterval) {
        print("framework: \(record.framework)")
        if let version = record.promptFormatVersion {
            print("prompt_format_version: \(version)")
        }
        for answer in record.answers {
            let probabilities = answer.probabilities
                .sorted { $0.key < $1.key }
                .map { "\($0.key)=\(String(format: "%.4f", $0.value))" }
                .joined(separator: " ")
            let verdict: String
            switch answer.type {
            case "choice": verdict = "choice=\(answer.choice ?? "-")"
            case "noul": verdict = String(format: "noul=%.4f", answer.noul ?? -1)
            default: verdict = String(format: "score=%.4f", answer.score ?? -1)
            }
            print("  \(answer.id): \(verdict) conf=\(String(format: "%.4f", answer.confidence)) [\(probabilities)]")
        }
        print(String(format: "time: %.2fs", elapsed))
    }

    /// Dev CLIs are unsigned, so Keychain is unavailable; mirror the MLXCLI
    /// convention and use the file-backed secure store in Application Support.
    private static func configureDevSecureStore() throws {
        let root = try FileManager.default.url(
            for: .applicationSupportDirectory,
            in: .userDomainMask,
            appropriateFor: nil,
            create: true
        )
        .appendingPathComponent("RunAnywhere/DevTools/DecisionCLI/SecureStore", isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        setenv("RUNANYWHERE_SWIFT_SECURE_STORE", "file", 1)
        setenv("RUNANYWHERE_SWIFT_SECURE_STORE_DIR", root.path, 1)
        setenv("RUNANYWHERE_SWIFT_LOCAL_ONLY", "1", 1)
    }

    private static func value(of flag: String, in args: [String]) -> String? {
        guard let index = args.firstIndex(of: flag), index + 1 < args.count else {
            return nil
        }
        return args[index + 1]
    }

    private static func withTimeout<T: Sendable>(
        seconds: Double,
        _ body: @escaping @Sendable () async throws -> T
    ) async throws -> T {
        try await withThrowingTaskGroup(of: T.self) { group in
            group.addTask { try await body() }
            group.addTask {
                try await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
                throw CLIError.runFailed("timed out after \(Int(seconds))s")
            }
            let result = try await group.next()!
            group.cancelAll()
            return result
        }
    }

    private static func printUsage() {
        print(
            """
            decision-cli — local model smoke + parity tool

            USAGE:
              decision-cli run    --framework <mlx|llamacpp> --model <id|path> [--out result.json] [--timeout 300] [--prompt-format-version N]
              decision-cli chat   --framework <mlx|llamacpp> --model <id|path> [--prompt "..."] [--max-tokens 64]
              decision-cli compare --a <result.json> --b <result.json> [--tolerance 0.01]
              decision-cli models
              decision-cli help

            MODEL:
              --model takes a filesystem path, or a catalog id resolved (and
              downloaded once) by the CLI; run `decision-cli models` for the list.
              Set DECISION_CLI_MODELS_DIR to override the download directory.

            The canonical ticket (team/refund/urgency) is built in; run it on both
            backends with the same checkpoint's quantizations and compare the JSON
            outputs. `chat` exercises the text stack on LFM2.5/Qwen. See
            tests/decision-cli/README.md for model paths and reference numbers.
            """)
    }
}