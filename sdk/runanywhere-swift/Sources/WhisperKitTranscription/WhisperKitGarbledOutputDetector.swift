import Foundation
import RunAnywhere

/// Utility for detecting garbled or nonsensical WhisperKit transcription output
struct WhisperKitGarbledOutputDetector {
    private let logger = SDKLogger(category: "WhisperKitService")

    /// Detect garbled or nonsensical WhisperKit output
    func isGarbled(_ text: String) -> Bool {
        let trimmedText = text.trimmingCharacters(in: .whitespacesAndNewlines)

        // Empty text is not garbled, just empty
        guard !trimmedText.isEmpty else { return false }

        // Check for repetitive word patterns
        if hasExcessiveWordRepetition(in: trimmedText) {
            return true
        }

        // Check for non-Latin scripts (Hebrew, Arabic, Chinese, etc.)
        if hasNonLatinScript(in: trimmedText) {
            return true
        }

        // Check for common garbled patterns
        if matchesGarbledPattern(trimmedText) {
            return true
        }

        // Check character composition
        if hasTooMuchPunctuation(in: trimmedText) {
            return true
        }

        // Check for excessive character repetition
        if hasExcessiveCharRepetition(in: trimmedText) {
            return true
        }

        return false
    }

    // MARK: - Private Helpers

    private func hasExcessiveWordRepetition(in text: String) -> Bool {
        let words = text.lowercased().components(separatedBy: .whitespacesAndNewlines).filter { !$0.isEmpty }

        guard words.count > 3 else { return false }

        // Check for excessive word repetition
        let wordCounts = Dictionary(words.map { ($0, 1) }, uniquingKeysWith: +)
        for (word, count) in wordCounts where Double(count) / Double(words.count) > 0.4 {
            logger.warning("⚠️ Detected excessive word repetition: '\(word)' appears \(count)/\(words.count) times")
            return true
        }

        // Check for repeating short phrases (2-3 word patterns)
        if words.count >= 6 {
            if hasRepeatingPhrases(in: words) {
                return true
            }
        }

        return false
    }

    private func hasRepeatingPhrases(in words: [String]) -> Bool {
        var twoWordPatterns: [String: Int] = [:]
        for i in 0..<(words.count - 1) {
            let pattern = "\(words[i]) \(words[i + 1])"
            twoWordPatterns[pattern, default: 0] += 1
        }
        for (pattern, count) in twoWordPatterns where count > 3 && Double(count * 2) / Double(words.count) > 0.5 {
            logger.warning("⚠️ Detected repeating phrase pattern: '\(pattern)' repeats \(count) times")
            return true
        }
        return false
    }

    private func hasNonLatinScript(in text: String) -> Bool {
        let nonLatinRanges: [ClosedRange<UInt32>] = [
            0x0590...0x05FF,  // Hebrew
            0x0600...0x06FF,  // Arabic
            0x0700...0x074F,  // Syriac
            0x0750...0x077F,  // Arabic Supplement
            0x0E00...0x0E7F,  // Thai
            0x1000...0x109F,  // Myanmar
            0x1100...0x11FF,  // Hangul Jamo
            0x3040...0x309F,  // Hiragana
            0x30A0...0x30FF,  // Katakana
            0x4E00...0x9FFF,  // CJK Unified Ideographs
            0xAC00...0xD7AF   // Hangul Syllables
        ]

        let nonLatinCount = text.unicodeScalars.filter { scalar in
            nonLatinRanges.contains { range in
                range.contains(scalar.value)
            }
        }.count

        // If more than 30% of characters are non-Latin, it's likely wrong language
        if Double(nonLatinCount) / Double(text.count) > 0.3 {
            logger.warning("⚠️ Detected non-Latin script in output (\(nonLatinCount)/\(text.count) characters)")
            return true
        }

        return false
    }

    private func matchesGarbledPattern(_ text: String) -> Bool {
        let garbledPatterns = [
            // Repetitive characters
            "^[\\(\\)\\-\\.\\s]+$",  // Only parentheses, dashes, dots, spaces
            "^[\\-\\s]{10,}",        // Many consecutive dashes or spaces
            "^[\\(]{5,}",           // Many consecutive opening parentheses
            "^[\\)]{5,}",           // Many consecutive closing parentheses
            "^[\\.,]{5,}",          // Many consecutive dots/commas
            // Special token patterns
            "^\\s*\\[.*\\]\\s*$",   // Text wrapped in brackets
            "^\\s*<.*>\\s*$"        // Text wrapped in angle brackets
        ]

        for pattern in garbledPatterns where text.range(of: pattern, options: .regularExpression) != nil {
            return true
        }

        return false
    }

    private func hasTooMuchPunctuation(in text: String) -> Bool {
        let punctuationCount = text.filter { $0.isPunctuation || $0 == "-" }.count
        let totalCount = text.count
        return totalCount > 5 && Double(punctuationCount) / Double(totalCount) > 0.7
    }

    private func hasExcessiveCharRepetition(in text: String) -> Bool {
        let charCounts = Dictionary(text.map { ($0, 1) }, uniquingKeysWith: +)
        for (char, count) in charCounts where char != " " && char != "-" && count > max(10, text.count / 2) {
            return true
        }
        return false
    }
}
