//
//  HuggingFaceHubClient.swift
//  RunAnywhereAI
//
//  Minimal REST client for the public Hugging Face Hub API, plus the curated
//  sub-1B catalog the "Add from Hugging Face" sheet opens on. Used to search
//  repos and list downloadable GGUF files. The RunAnywhere SDK owns all
//  resolution/download once a URL is registered — this client is purely
//  example-app discovery UI plumbing.
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
    /// Live download count, or `nil` when the Hub did not report one.
    /// Optional rather than zero-defaulted so a curated suggestion — which has
    /// no live counts to offer — cannot be mistaken for a repo nobody uses.
    let downloads: Int?
    /// Live like count, same nil-means-unknown contract as `downloads`.
    let likes: Int?
    /// Total parameter count from `gguf.total`, when the search asked for it.
    /// MLX searches never carry one: MLX repos have no `gguf` block.
    let params: Int?

    /// Friendly repo name (last path component) for list display.
    var displayName: String {
        id.split(separator: "/").last.map(String.init) ?? id
    }

    /// Owning org/user for the repo, if the id is namespaced.
    var owner: String? {
        let parts = id.split(separator: "/")
        return parts.count > 1 ? String(parts[0]) : nil
    }

    /// Badge text for the parameter count, or `nil` when there is nothing
    /// trustworthy to show. A missing or nonsensical `gguf.total` must cost the
    /// badge — rendering "0" or "unknown" states a fact the API never gave us.
    var parameterBadge: String? {
        guard let params, params > 0 else { return nil }
        return Self.formattedParameterCount(params)
    }

    /// The parameter-count format shared by all four RunAnywhere example apps,
    /// so the same repo shows the same badge on iOS, Android, and the web.
    ///
    /// The 999M floor-cap is load-bearing, not cosmetic: `999_885_952` rounds to
    /// 1000, and a chip reading "1000M" directly under a header that says "All
    /// under 1B parameters" is a contradiction on screen. Every other catalog
    /// entry rounds to the vendor's own number (135M, 268M, 362M, 596M, 630M,
    /// 742M), so capping costs nothing anywhere else.
    static func formattedParameterCount(_ params: Int) -> String {
        if params >= 1_000_000_000 {
            return String(format: "%.1fB", Double(params) / 1e9)
        }
        return "\(min(999, Int((Double(params) / 1e6).rounded())))M"
    }
}

// MARK: - Curated Suggestions

/// One entry in the curated "suggested small models" catalog.
struct HFSuggestedModel: Identifiable, Hashable {
    /// Fully-qualified repo id — shown on the tile so the parameter claim above
    /// it stays checkable against the Hub rather than taken on trust.
    let repoId: String
    /// Consumer-facing name, e.g. `"SmolLM2 135M"`.
    let title: String
    /// Measured parameter count for the base model.
    let params: Int
    /// One line of consumer language. Identical copy across all four apps.
    let blurb: String

    var id: String { repoId }

    /// Always present, unlike `HFModelSummary.parameterBadge`: a catalog entry
    /// only earns a place here once its count has been measured.
    var parameterBadge: String {
        HFModelSummary.formattedParameterCount(params)
    }

    /// Bridge into the same repo-detail flow a search result opens, so tapping a
    /// suggestion and tapping a search hit are literally the same code path.
    ///
    /// Download and like counts are deliberately absent. They are live figures;
    /// authoring them beside authored data would let them rot on screen with
    /// nothing to notice it.
    var summary: HFModelSummary {
        HFModelSummary(id: repoId, downloads: nil, likes: nil, params: params)
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
            // `gguf.total` is the parameter count, and `expand[]=gguf` is the
            // only way to read it — the Hub rejects `expand[]=gguf.total`, so
            // there is no cheaper sub-field ask and the whole block (chat
            // template included) comes down with it.
            //
            // Requesting any `expand[]` also switches the response to an
            // allow-list, which silently drops `likes` and `modelId` from every
            // row. `downloads` and `likes` are re-requested here so the result
            // rows keep the metadata they have always shown; the two extra
            // expands measured ~25 bytes on a 16 KB page.
            items.append(URLQueryItem(name: "expand[]", value: "gguf"))
            items.append(URLQueryItem(name: "expand[]", value: "downloads"))
            items.append(URLQueryItem(name: "expand[]", value: "likes"))
        case .mlx:
            // No `expand[]=gguf` on this branch: MLX repos carry no `gguf`
            // block at all, so it would be pure payload cost for a field that
            // can never be present.
            items.append(URLQueryItem(name: "library", value: "mlx"))
        }
        components?.queryItems = items

        guard let url = components?.url else { throw HuggingFaceHubError.invalidURL }

        let raw: [HFModelDTO] = try await fetch(url: url, token: token)
        return raw.map { dto in
            HFModelSummary(
                id: dto.id,
                downloads: dto.downloads,
                likes: dto.likes,
                params: dto.gguf?.total
            )
        }
    }

    // MARK: Suggestions

    /// The curated sub-1B catalog for an artifact kind, ascending by parameter
    /// count. Instant and offline: the sheet can open on it without a request,
    /// and it can never render an empty panel.
    static func suggestedModels(for kind: HFSearchKind) -> [HFSuggestedModel] {
        switch kind {
        case .gguf: return suggestedGGUF
        case .mlx: return suggestedMLX
        }
    }

    /// Sub-1B GGUF repos, verified against the Hub's own `gguf.total`.
    ///
    /// Why this list is authored rather than queried. Reading a parameter count
    /// at all costs `expand[]=gguf`, which is 4–14× the payload of a plain
    /// search. And filtering *after* the fact does not work: only three of the
    /// top hundred GGUF text-generation repos by downloads are under 1B — the
    /// head of that list is 27B–284B — so "fetch the top N and filter" would
    /// return a nearly empty panel. Size-token searches (`135M`, `0.6B`) do
    /// surface small repos but leak other modalities; `0.6B` returns parakeet
    /// and nemotron ASR repos beside chat models.
    ///
    /// So: an authored list with measured counts. The badge shows the measured
    /// number, which means what is on screen is exactly what the "under 1B"
    /// claim was checked against. `unsloth/Llama-3.2-1B-Instruct-GGUF` is
    /// 1,235,814,432 params and is excluded for being over the line.
    private static let suggestedGGUF: [HFSuggestedModel] = [
        HFSuggestedModel(
            repoId: "unsloth/SmolLM2-135M-Instruct-GGUF",
            title: "SmolLM2 135M",
            params: 134_515_008,
            blurb: "The smallest useful chat model. Downloads in seconds."
        ),
        HFSuggestedModel(
            repoId: "unsloth/gemma-3-270m-it-GGUF",
            title: "Gemma 3 270M",
            params: 268_098_176,
            blurb: "Google's smallest instruction model, with a 32K context."
        ),
        HFSuggestedModel(
            repoId: "LiquidAI/LFM2-350M-GGUF",
            title: "LFM2 350M",
            params: 354_483_968,
            blurb: "A 128K context in a tiny model — good for long documents."
        ),
        HFSuggestedModel(
            repoId: "HuggingFaceTB/SmolLM2-360M-Instruct-GGUF",
            title: "SmolLM2 360M",
            params: 361_821_120,
            blurb: "More capable than 135M, still quick on any device."
        ),
        HFSuggestedModel(
            repoId: "unsloth/Qwen3-0.6B-GGUF",
            title: "Qwen3 0.6B",
            params: 596_049_920,
            blurb: "A strong all-rounder for its size, with a 40K context."
        ),
        HFSuggestedModel(
            repoId: "Qwen/Qwen2.5-0.5B-Instruct-GGUF",
            title: "Qwen2.5 0.5B",
            params: 630_167_424,
            blurb: "Widely used, dependable general chat."
        ),
        HFSuggestedModel(
            repoId: "LiquidAI/LFM2-700M-GGUF",
            title: "LFM2 700M",
            params: 742_489_344,
            blurb: "The long-context option, with more room to reason."
        ),
        HFSuggestedModel(
            repoId: "ggml-org/gemma-3-1b-it-GGUF",
            title: "Gemma 3 1B",
            params: 999_885_952,
            blurb: "The most capable model still under 1B."
        )
    ]

    /// Sub-1B MLX bundles — Apple Silicon only, so this list is only ever shown
    /// where MLX actually registered.
    ///
    /// Counts are the base model's, verified against the GGUF probe of the same
    /// base: quantization changes bytes, not parameters. They cannot be read off
    /// the API here at all — an MLX repo has no `gguf` block, and
    /// `safetensors.total` counts *packed* tensors rather than parameters
    /// (`mlx-community/Qwen3-0.6B-4bit` reports 93,188,096, not 596M). A curated
    /// list is the only option that exists for MLX.
    ///
    /// LFM2 is absent because there is no sub-1B LFM2 MLX repo — the smallest is
    /// 1.2B. Do not invent one to make the two lists match.
    private static let suggestedMLX: [HFSuggestedModel] = [
        HFSuggestedModel(
            repoId: "mlx-community/SmolLM2-135M-Instruct",
            title: "SmolLM2 135M",
            params: 134_515_008,
            blurb: "The smallest useful chat model. Downloads in seconds."
        ),
        HFSuggestedModel(
            repoId: "mlx-community/gemma-3-270m-it-8bit",
            title: "Gemma 3 270M",
            params: 268_098_176,
            blurb: "Google's smallest instruction model, kept at 8-bit for quality."
        ),
        HFSuggestedModel(
            repoId: "mlx-community/SmolLM2-360M-Instruct",
            title: "SmolLM2 360M",
            params: 361_821_120,
            blurb: "More capable than 135M, still quick on any device."
        ),
        HFSuggestedModel(
            repoId: "mlx-community/Qwen3-0.6B-4bit",
            title: "Qwen3 0.6B",
            params: 596_049_920,
            blurb: "A strong all-rounder for its size, with a 40K context."
        ),
        HFSuggestedModel(
            repoId: "mlx-community/Qwen2.5-0.5B-Instruct-4bit",
            title: "Qwen2.5 0.5B",
            params: 630_167_424,
            blurb: "Widely used, dependable general chat."
        ),
        HFSuggestedModel(
            repoId: "mlx-community/gemma-3-1b-it-qat-4bit",
            title: "Gemma 3 1B",
            params: 999_885_952,
            blurb: "The most capable model still under 1B, quantization-aware trained."
        )
    ]

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
    /// Present only when the request asked for `expand[]=gguf`.
    let gguf: HFGgufDTO?

    private enum CodingKeys: String, CodingKey {
        case id
        case modelId
        case downloads
        case likes
        case gguf
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
        // `try?` rather than `decodeIfPresent`: one repo with a malformed `gguf`
        // block should cost that row its parameter badge, not fail the entire
        // search. Absent and garbage both collapse to nil, which the badge
        // already treats as "show nothing".
        gguf = try? container.decode(HFGgufDTO.self, forKey: .gguf)
    }
}

private struct HFGgufDTO: Decodable {
    /// Total parameter count across the repo's tensors.
    let total: Int?
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
