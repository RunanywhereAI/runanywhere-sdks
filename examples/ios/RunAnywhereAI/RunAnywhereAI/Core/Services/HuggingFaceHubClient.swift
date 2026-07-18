//
//  HuggingFaceHubClient.swift
//  RunAnywhereAI
//
//  Minimal REST client for the public Hugging Face Hub API. Used by the
//  "Add from Hugging Face" flow to search repos and list downloadable GGUF
//  files. The RunAnywhere SDK owns all resolution/download once a URL is
//  registered — this client is purely example-app discovery UI plumbing.
//

import Foundation

// MARK: - Search Kind

/// Which kind of on-device model artifact to search the Hub for.
enum HFSearchKind: String, CaseIterable, Identifiable {
    /// GGUF (llama.cpp) quantized weights — runs everywhere.
    case gguf
    /// MLX repo bundles — Apple Silicon only (iOS device / native macOS).
    case mlx

    var id: String { rawValue }

    var displayName: String {
        switch self {
        case .gguf: return "GGUF"
        case .mlx: return "MLX"
        }
    }
}

// MARK: - Structured Response Types

/// One repo from a Hub model search.
struct HFModelSummary: Identifiable, Hashable {
    /// Fully-qualified repo id, e.g. `"unsloth/Qwen3-0.6B-GGUF"`.
    let id: String
    let downloads: Int
    let likes: Int

    /// Friendly repo name (last path component) for list display.
    var displayName: String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    /// Owning org/user for the repo, if the id is namespaced.
    var owner: String? {
        let parts = id.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }
}

/// One downloadable GGUF file inside a repo.
struct HFRepoFile: Identifiable, Hashable {
    /// Path within the repo, e.g. `"Qwen3-0.6B-Q4_K_M.gguf"`.
    let path: String
    /// Resolved size in bytes (`lfs.size` preferred over plain `size`).
    let sizeBytes: Int64
    /// Quantization label parsed from the filename, e.g. `"Q4_K_M"`.
    let quantLabel: String

    var id: String { path }

    /// Human-readable size for row display.
    var formattedSize: String {
        sizeBytes > 0 ? sizeBytes.formattedFileSize : "Unknown size"
    }
}

// MARK: - Errors

enum HuggingFaceHubError: LocalizedError {
    case invalidURL
    case invalidResponse
    case httpStatus(Int)

    var errorDescription: String? {
        switch self {
        case .invalidURL:
            return "Could not build a valid Hugging Face request URL."
        case .invalidResponse:
            return "Received an unexpected response from Hugging Face."
        case .httpStatus(let code):
            return "Hugging Face request failed (HTTP \(code))."
        }
    }
}

// MARK: - Client

/// URLSession-based client for the public Hugging Face Hub REST API.
struct HuggingFaceHubClient {
    private let session: URLSession
    private let decoder: JSONDecoder

    init(session: URLSession = .shared) {
        self.session = session
        self.decoder = JSONDecoder()
    }

    // MARK: Search

    /// Search the Hub for repos exposing the requested artifact kind, ordered
    /// by descending download count.
    func searchModels(
        query: String,
        kind: HFSearchKind,
        token: String? = nil
    ) async throws -> [HFModelSummary] {
        var components = URLComponents(string: "https://huggingface.co/api/models")
        var items: [URLQueryItem] = [
            URLQueryItem(name: "search", value: query),
            URLQueryItem(name: "sort", value: "downloads"),
            URLQueryItem(name: "direction", value: "-1"),
            URLQueryItem(name: "limit", value: "25")
        ]
        switch kind {
        case .gguf:
            items.append(URLQueryItem(name: "filter", value: "gguf"))
        case .mlx:
            items.append(URLQueryItem(name: "library", value: "mlx"))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw HuggingFaceHubError.invalidURL }

        let raw: [HFModelDTO] = try await fetch(url: url, token: token)
        return raw.map { dto in
            HFModelSummary(id: dto.id, downloads: dto.downloads ?? 0, likes: dto.likes ?? 0)
        }
    }

    // MARK: File Listing

    /// List downloadable `.gguf` files (with resolved sizes) inside a repo.
    func listGgufFiles(repoId: String, token: String? = nil) async throws -> [HFRepoFile] {
        let escapedRepo = repoId
            .addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? repoId
        let urlString = "https://huggingface.co/api/models/\(escapedRepo)/tree/main?recursive=true"
        guard let url = URL(string: urlString) else { throw HuggingFaceHubError.invalidURL }

        let entries: [HFTreeEntryDTO] = try await fetch(url: url, token: token)
        return entries
            .filter { $0.type == "file" && $0.path.lowercased().hasSuffix(".gguf") }
            .map { entry in
                let size = entry.lfs?.size ?? entry.size ?? 0
                return HFRepoFile(
                    path: entry.path,
                    sizeBytes: size,
                    quantLabel: Self.quantLabel(from: entry.path)
                )
            }
            .sorted { $0.sizeBytes < $1.sizeBytes }
    }

    // MARK: - Private

    private func fetch<T: Decodable>(url: URL, token: String?) async throws -> T {
        var request = URLRequest(url: url)
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        if let token, !token.isEmpty {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        let (data, response) = try await session.data(for: request)
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HuggingFaceHubError.invalidResponse
        }
        guard (200..<300).contains(httpResponse.statusCode) else {
            throw HuggingFaceHubError.httpStatus(httpResponse.statusCode)
        }
        return try decoder.decode(T.self, from: data)
    }

    /// Derive a quantization label (e.g. `Q4_K_M`, `IQ3_XXS`, `F16`) from a
    /// GGUF filename. Falls back to the bare filename stem when no known
    /// quant token is present.
    static func quantLabel(from path: String) -> String {
        let fileName = (path as NSString).lastPathComponent
        let stem = (fileName as NSString).deletingPathExtension
        let tokens = stem.split { $0 == "." || $0 == "-" || $0 == "_" }

        var collected: [String] = []
        for token in tokens {
            let upper = token.uppercased()
            if upper.hasPrefix("Q") || upper.hasPrefix("IQ") || upper.hasPrefix("F16")
                || upper.hasPrefix("F32") || upper.hasPrefix("BF16") {
                collected.append(upper)
            } else if !collected.isEmpty {
                // Quant tokens are contiguous (e.g. Q4_K_M); stop at the first gap.
                let suffixes: Set<String> = ["K", "M", "S", "L", "XL", "XS", "XXS", "0", "1"]
                if suffixes.contains(upper) {
                    collected.append(upper)
                } else {
                    break
                }
            }
        }

        if collected.isEmpty {
            return stem
        }
        return collected.joined(separator: "_")
    }
}

// MARK: - Wire DTOs (decode-only)

private struct HFModelDTO: Decodable {
    let id: String
    let downloads: Int?
    let likes: Int?

    private enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case downloads
        case likes
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // The Hub returns the repo ref under either "id" or "modelId".
        if let value = try container.decodeIfPresent(String.self, forKey: .id) {
            id = value
        } else {
            id = try container.decode(String.self, forKey: .modelId)
        }
        downloads = try container.decodeIfPresent(Int.self, forKey: .downloads)
        likes = try container.decodeIfPresent(Int.self, forKey: .likes)
    }
}

private struct HFTreeEntryDTO: Decodable {
    let type: String
    let path: String
    let size: Int64?
    let lfs: HFLfsDTO?
}

private struct HFLfsDTO: Decodable {
    let size: Int64?
}
