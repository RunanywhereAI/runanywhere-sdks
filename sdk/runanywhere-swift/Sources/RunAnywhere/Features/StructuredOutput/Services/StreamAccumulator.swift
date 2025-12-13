import Foundation

// MARK: - Stream Accumulator

/// Accumulates tokens during streaming for later parsing
public actor StreamAccumulator {
    private var text = ""
    private var isComplete = false
    private var completionContinuation: CheckedContinuation<Void, Never>?

    public init() {}

    public func append(_ token: String) {
        text += token
    }

    public var fullText: String {
        return text
    }

    public func markComplete() {
        guard !isComplete else { return }
        isComplete = true
        completionContinuation?.resume()
        completionContinuation = nil
    }

    public func waitForCompletion() async {
        guard !isComplete else { return }

        await withCheckedContinuation { continuation in
            if isComplete {
                continuation.resume()
            } else {
                completionContinuation = continuation
            }
        }
    }
}
