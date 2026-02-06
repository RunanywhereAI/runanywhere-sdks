//
//  TextChunker.swift
//  RunAnywhere SDK
//
//  Simple text chunking utility for RAG ingestion.
//

import Foundation

/// Utility for splitting text into overlapping chunks
///
/// Used by RAGAgent.ingest() to break large documents into
/// manageable pieces for embedding and storage.
public enum TextChunker {

    /// Split text into chunks with overlap
    ///
    /// Splits on sentence boundaries (`.`, `!`, `?`) when possible,
    /// falling back to character boundaries.
    ///
    /// - Parameters:
    ///   - text: Text to split
    ///   - maxCharacters: Maximum characters per chunk
    ///   - overlap: Character overlap between consecutive chunks
    /// - Returns: Array of text chunks
    public static func chunk(
        _ text: String,
        maxCharacters: Int,
        overlap: Int = 50
    ) -> [String] {
        guard !text.isEmpty else { return [] }
        guard text.count > maxCharacters else { return [text] }

        // Split into sentences first
        let sentences = splitIntoSentences(text)
        var chunks: [String] = []
        var currentChunk = ""

        for sentence in sentences {
            if currentChunk.isEmpty {
                currentChunk = sentence
            } else if currentChunk.count + sentence.count + 1 <= maxCharacters {
                currentChunk += " " + sentence
            } else {
                // Current chunk is full
                chunks.append(currentChunk)

                // Start new chunk with overlap from end of previous
                if overlap > 0 && currentChunk.count > overlap {
                    let overlapStart = currentChunk.index(currentChunk.endIndex,
                                                          offsetBy: -overlap)
                    currentChunk = String(currentChunk[overlapStart...]) + " " + sentence
                } else {
                    currentChunk = sentence
                }
            }
        }

        if !currentChunk.isEmpty {
            chunks.append(currentChunk)
        }

        return chunks
    }

    // MARK: - Private

    private static func splitIntoSentences(_ text: String) -> [String] {
        var sentences: [String] = []
        var current = ""

        for char in text {
            current.append(char)
            if char == "." || char == "!" || char == "?" {
                let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
                if !trimmed.isEmpty {
                    sentences.append(trimmed)
                }
                current = ""
            }
        }

        // Add remaining text
        let trimmed = current.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmed.isEmpty {
            sentences.append(trimmed)
        }

        return sentences
    }
}
