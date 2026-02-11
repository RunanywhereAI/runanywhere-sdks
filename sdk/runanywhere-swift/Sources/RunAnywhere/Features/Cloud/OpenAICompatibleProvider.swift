//
//  OpenAICompatibleProvider.swift
//  RunAnywhere SDK
//
//  Built-in cloud provider for OpenAI-compatible APIs.
//  Works with OpenAI, Groq, Together, Ollama, vLLM, etc.
//

import Foundation

// MARK: - OpenAI Compatible Provider

/// Cloud provider for any OpenAI-compatible chat completions API.
///
/// Supports both streaming (SSE) and non-streaming responses.
///
/// ```swift
/// // OpenAI
/// let openai = OpenAICompatibleProvider(apiKey: "sk-...", model: "gpt-4o-mini")
///
/// // Groq
/// let groq = OpenAICompatibleProvider(
///     apiKey: "gsk_...",
///     model: "llama-3.1-8b-instant",
///     baseURL: URL(string: "https://api.groq.com/openai/v1")!
/// )
///
/// // Local Ollama
/// let ollama = OpenAICompatibleProvider(
///     model: "llama3.2",
///     baseURL: URL(string: "http://localhost:11434/v1")!
/// )
/// ```
public final class OpenAICompatibleProvider: CloudProvider, @unchecked Sendable {

    // MARK: - CloudProvider

    public let providerId: String
    public let displayName: String

    // MARK: - Configuration

    private let apiKey: String?
    private let model: String
    private let baseURL: URL
    private let additionalHeaders: [String: String]
    private let session: URLSession

    // MARK: - Init

    /// Create an OpenAI-compatible provider.
    ///
    /// - Parameters:
    ///   - providerId: Unique ID (default: auto-generated from base URL)
    ///   - displayName: Human-readable name
    ///   - apiKey: API key (nil for local providers like Ollama)
    ///   - model: Default model to use
    ///   - baseURL: API base URL (default: OpenAI)
    ///   - additionalHeaders: Extra headers to send with every request
    public init(
        providerId: String? = nil,
        displayName: String? = nil,
        apiKey: String? = nil,
        model: String,
        baseURL: URL = URL(string: "https://api.openai.com/v1")!,
        additionalHeaders: [String: String] = [:]
    ) {
        self.apiKey = apiKey
        self.model = model
        self.baseURL = baseURL
        self.additionalHeaders = additionalHeaders
        self.providerId = providerId ?? "openai-compat-\(baseURL.host ?? "local")"
        self.displayName = displayName ?? "OpenAI Compatible (\(baseURL.host ?? "local"))"
        self.session = URLSession(configuration: .default)
    }

    // MARK: - CloudProvider Implementation

    public func generate(
        prompt: String,
        options: CloudGenerationOptions
    ) async throws -> CloudGenerationResult {
        let startTime = Date()

        let messages = buildMessages(prompt: prompt, options: options)
        let requestBody = buildRequestBody(messages: messages, options: options, stream: false)

        let data = try await performRequest(body: requestBody)

        let response = try JSONDecoder().decode(ChatCompletionResponse.self, from: data)

        let latencyMs = Date().timeIntervalSince(startTime) * 1000
        let text = response.choices.first?.message.content ?? ""

        return CloudGenerationResult(
            text: text,
            inputTokens: response.usage?.promptTokens ?? 0,
            outputTokens: response.usage?.completionTokens ?? 0,
            latencyMs: latencyMs,
            providerId: providerId,
            model: options.model,
            estimatedCostUSD: nil
        )
    }

    public func generateStream(
        prompt: String,
        options: CloudGenerationOptions
    ) -> AsyncThrowingStream<String, Error> {
        AsyncThrowingStream { continuation in
            Task {
                do {
                    let messages = buildMessages(prompt: prompt, options: options)
                    let requestBody = buildRequestBody(messages: messages, options: options, stream: true)
                    let request = try buildURLRequest(body: requestBody)

                    let (bytes, response) = try await session.bytes(for: request)

                    guard let httpResponse = response as? HTTPURLResponse,
                          (200...299).contains(httpResponse.statusCode) else {
                        let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
                        throw CloudProviderError.httpError(statusCode: statusCode)
                    }

                    // Parse SSE stream
                    for try await line in bytes.lines {
                        if line.hasPrefix("data: ") {
                            let data = String(line.dropFirst(6))
                            if data == "[DONE]" { break }

                            if let jsonData = data.data(using: .utf8),
                               let chunk = try? JSONDecoder().decode(ChatCompletionChunk.self, from: jsonData),
                               let content = chunk.choices.first?.delta.content {
                                continuation.yield(content)
                            }
                        }
                    }

                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
    }

    public func isAvailable() async -> Bool {
        // Simple health check: try to list models or just check connectivity
        guard let url = URL(string: "\(baseURL)/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 5
        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }
        do {
            let (_, response) = try await session.data(for: request)
            return (response as? HTTPURLResponse)?.statusCode == 200
        } catch {
            return false
        }
    }

    // MARK: - Internal Helpers

    private func buildMessages(prompt: String, options: CloudGenerationOptions) -> [[String: String]] {
        if let messages = options.messages {
            return messages.map { ["role": $0.role, "content": $0.content] }
        }

        var msgs: [[String: String]] = []
        if let systemPrompt = options.systemPrompt {
            msgs.append(["role": "system", "content": systemPrompt])
        }
        msgs.append(["role": "user", "content": prompt])
        return msgs
    }

    private func buildRequestBody(
        messages: [[String: String]],
        options: CloudGenerationOptions,
        stream: Bool
    ) -> [String: Any] {
        var body: [String: Any] = [
            "model": options.model,
            "messages": messages,
            "max_tokens": options.maxTokens,
            "temperature": options.temperature,
            "stream": stream,
        ]
        return body
    }

    private func buildURLRequest(body: [String: Any]) throws -> URLRequest {
        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw CloudProviderError.invalidURL
        }

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")

        if let apiKey = apiKey {
            request.setValue("Bearer \(apiKey)", forHTTPHeaderField: "Authorization")
        }

        for (key, value) in additionalHeaders {
            request.setValue(value, forHTTPHeaderField: key)
        }

        request.httpBody = try JSONSerialization.data(withJSONObject: body)
        return request
    }

    private func performRequest(body: [String: Any]) async throws -> Data {
        let request = try buildURLRequest(body: body)
        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? -1
            throw CloudProviderError.httpError(statusCode: statusCode)
        }

        return data
    }
}

// MARK: - Cloud Provider Errors

/// Errors from cloud provider operations
public enum CloudProviderError: Error, LocalizedError, Sendable {
    case invalidURL
    case httpError(statusCode: Int)
    case noProviderRegistered
    case providerNotFound(id: String)
    case providerUnavailable(id: String)
    case decodingError(String)
    case budgetExceeded(currentUSD: Double, capUSD: Double)
    case latencyTimeout(maxMs: UInt32, actualMs: Double)

    public var errorDescription: String? {
        switch self {
        case .invalidURL: return "Invalid cloud provider URL"
        case .httpError(let code): return "Cloud API returned HTTP \(code)"
        case .noProviderRegistered: return "No cloud provider registered"
        case .providerNotFound(let id): return "Cloud provider not found: \(id)"
        case .providerUnavailable(let id): return "Cloud provider unavailable: \(id)"
        case .decodingError(let msg): return "Failed to decode cloud response: \(msg)"
        case .budgetExceeded(let current, let cap):
            return "Cloud budget exceeded: $\(String(format: "%.4f", current)) / $\(String(format: "%.4f", cap)) cap"
        case .latencyTimeout(let maxMs, let actualMs):
            return "On-device latency timeout: \(String(format: "%.0f", actualMs))ms exceeded \(maxMs)ms limit"
        }
    }
}

// MARK: - OpenAI API Response Types

private struct ChatCompletionResponse: Decodable {
    let choices: [Choice]
    let usage: Usage?

    struct Choice: Decodable {
        let message: Message
    }

    struct Message: Decodable {
        let content: String?
    }

    struct Usage: Decodable {
        let promptTokens: Int
        let completionTokens: Int

        enum CodingKeys: String, CodingKey {
            case promptTokens = "prompt_tokens"
            case completionTokens = "completion_tokens"
        }
    }
}

private struct ChatCompletionChunk: Decodable {
    let choices: [Choice]

    struct Choice: Decodable {
        let delta: Delta
    }

    struct Delta: Decodable {
        let content: String?
    }
}
