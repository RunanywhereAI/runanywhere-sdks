import Foundation

/// Preserve model-defined textual terminators while passing generated text,
/// including tool-call framing, unchanged to the commons ABI consumer.
struct MLXTextStopFilter {
    let stops: [String]
    private var pending = ""
    private(set) var stopped = false

    init(stopStrings: Set<String>) {
        stops = stopStrings.filter { !$0.isEmpty }
    }

    mutating func process(_ chunk: String) -> String {
        guard !stopped else { return "" }
        pending += chunk
        let ranges = stops.compactMap { pending.range(of: $0) }
        if let first = ranges.min(by: { $0.lowerBound < $1.lowerBound }) {
            let text = String(pending[..<first.lowerBound])
            pending = ""
            stopped = true
            return text
        }
        var held = 0
        for stop in stops {
            let pendingScalars = pending.unicodeScalars
            let stopScalars = stop.unicodeScalars
            let limit = min(pendingScalars.count, stopScalars.count - 1)
            if limit > held {
                for size in stride(from: limit, through: held + 1, by: -1)
                    where pendingScalars.suffix(size).elementsEqual(stopScalars.prefix(size)) {
                    held = size
                    break
                }
            }
        }
        let end = pending.unicodeScalars.index(pending.unicodeScalars.endIndex, offsetBy: -held)
        let text = String(pending[..<end])
        pending = String(pending[end...])
        return text
    }

    mutating func finish() -> String {
        defer { pending = "" }
        return stopped ? "" : pending
    }
}
