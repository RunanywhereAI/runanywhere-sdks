//
//  Catalog.swift
//  DecisionCLI
//
//  Local model catalog for the dev CLIs. Mirrors the entries in the Wally
//  catalog (src/catalog/catalog.rs) so a model can be named by its short id
//  instead of a path, and so the same checkpoints are exercised here and
//  there. Kept deliberately tiny: one text model per backend plus the decision
//  pair, all pinned to an HF revision so a rerun fetches the same bytes.
//

import Foundation

struct CatalogEntry {
    let id: String
    let aliases: [String]
    let framework: String  // "llamacpp" | "mlx"
    let category: String   // "language" | "decision"
    /// Direct GGUF URL, when the artifact is a single file.
    let url: String?
    /// HF repo + revision for multi-file (MLX) checkpoints.
    let repo: String?
    let revision: String?
    /// Expected file inside the repo for multi-file checkpoints.
    let file: String?
    let sizeBytes: Int64

    var isDecision: Bool { category == "decision" }
}

enum Catalog {
    static let entries: [CatalogEntry] = [
        // ---- decision models (llama.cpp) ----
        CatalogEntry(
            id: "clef-flash-gguf",
            aliases: ["clef-gguf", "clef"],
            framework: "llamacpp",
            category: "decision",
            url: "https://huggingface.co/ggml-org/Clef-Flash-GGUF/resolve/main/Clef-Flash-Q4_K_M.gguf",
            repo: nil, revision: nil, file: nil,
            sizeBytes: 6_486_448_192
        ),
        // ---- decision models (MLX) ----
        CatalogEntry(
            id: "clef-flash-mlx-4bit",
            aliases: ["clef-mlx"],
            framework: "mlx",
            category: "decision",
            url: nil,
            repo: "mlx-community/clef-flash-4bit",
            revision: nil,
            file: "model.safetensors",
            sizeBytes: 5_900_000_000
        ),
        // ---- text models (llama.cpp), from the Wally catalog ----
        CatalogEntry(
            id: "lfm2.5-1.2b",
            aliases: ["lfm2.5", "lfm"],
            framework: "llamacpp",
            category: "language",
            url: "https://huggingface.co/LiquidAI/LFM2.5-1.2B-Instruct-GGUF/resolve/6767265158422fb8a19c62ceb45f16f05363615b/LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            repo: "LiquidAI/LFM2.5-1.2B-Instruct-GGUF",
            revision: "6767265158422fb8a19c62ceb45f16f05363615b",
            file: "LFM2.5-1.2B-Instruct-Q4_K_M.gguf",
            sizeBytes: 697 * 1_000_000
        ),
        CatalogEntry(
            id: "qwen3-0.6b",
            aliases: ["qwen3"],
            framework: "llamacpp",
            category: "language",
            url: "https://huggingface.co/Qwen/Qwen3-0.6B-GGUF/resolve/main/Qwen3-0.6B-Q8_0.gguf",
            repo: "Qwen/Qwen3-0.6B-GGUF",
            revision: nil,
            file: "Qwen3-0.6B-Q8_0.gguf",
            sizeBytes: 639 * 1_000_000
        ),
        // ---- text models (MLX), from the Wally catalog ----
        CatalogEntry(
            id: "mlx-qwen3-0.6b-4bit",
            aliases: ["mlx-qwen3"],
            framework: "mlx",
            category: "language",
            url: nil,
            repo: "mlx-community/Qwen3-0.6B-4bit",
            revision: nil,
            file: "model.safetensors",
            sizeBytes: 351_383_618
        ),
    ]

    /// Resolve an id/alias to its catalog entry.
    static func resolve(_ name: String) -> CatalogEntry? {
        let key = name.lowercased()
        return entries.first { entry in
            entry.id == key || entry.aliases.contains(key)
        }
    }

    /// A stable on-disk path for a catalog model: an already-downloaded local
    /// file (GGUF) or directory (MLX), otherwise nil and the caller downloads.
    static func localPath(for entry: CatalogEntry, root: String) -> String? {
        let fm = FileManager.default
        if let file = entry.file {
            let direct = (root as NSString).appendingPathComponent(entry.id)
            let candidate = (direct as NSString).appendingPathComponent(file)
            if fm.fileExists(atPath: candidate) { return candidate }
            // GGUF entries often land flat in a per-model directory.
            if fm.fileExists(atPath: direct) {
                if let contents = try? fm.contentsOfDirectory(atPath: direct) {
                    if let gguf = contents.first(where: { $0.hasSuffix(".gguf") }) {
                        return (direct as NSString).appendingPathComponent(gguf)
                    }
                }
            }
        }
        let dir = (root as NSString).appendingPathComponent(entry.id)
        if fm.fileExists(atPath: dir) { return dir }
        return nil
    }

    /// Download an entry with `hf download` into `<root>/<id>`. Returns the
    /// resolved model path (a file for GGUF, a directory for MLX).
    @discardableResult
    static func download(_ entry: CatalogEntry, root: String) throws -> String {
        guard let repo = entry.repo else {
            throw CLIError.runFailed("catalog entry \(entry.id) has no repo")
        }
        let dest = (root as NSString).appendingPathComponent(entry.id)
        try FileManager.default.createDirectory(
            atPath: dest, withIntermediateDirectories: true)

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        var arguments = ["hf", "download", repo]
        // GGUF: fetch the single file. MLX: the whole repo (config, tokenizer,
        // shard index) — `file` is only the marker we look for afterwards.
        if entry.framework == "llamacpp", let file = entry.file {
            arguments.append(file)
        }
        if let revision = entry.revision {
            arguments.append("--revision")
            arguments.append(revision)
        }
        arguments.append(contentsOf: ["--local-dir", dest])
        process.arguments = arguments

        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw CLIError.runFailed("hf download failed for \(entry.id)")
        }
        if entry.framework == "llamacpp", let file = entry.file {
            let direct = (dest as NSString).appendingPathComponent(file)
            if FileManager.default.fileExists(atPath: direct) { return direct }
        }
        return dest
    }
}