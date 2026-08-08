//
//  DocumentService.swift
//  RunAnywhereAI
//
//  Utility for extracting plain text from PDF, JSON, and text files.
//  Used to prepare document content for RAG ingestion.
//

import Foundation
import PDFKit

// MARK: - Document Type

enum DocumentType {
    case pdf
    case json
    /// Anything already readable as text: notes, transcripts, source, Markdown.
    ///
    /// Added because the composer now accepts dropped and pasted files, and a
    /// `.md` file is the single most common thing anyone drags onto a chat.
    /// Refusing it while accepting a PDF of the same notes was arbitrary, and it
    /// was the one place iOS accepted less than the web app.
    case plainText
    case unsupported

    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "json": self = .json
        case "txt", "md", "markdown": self = .plainText
        default: self = .unsupported
        }
    }
}

// MARK: - Document Service Error

enum DocumentServiceError: LocalizedError {
    case unsupportedFormat(String)
    case pdfExtractionFailed
    case jsonExtractionFailed(String)
    case fileReadFailed(String)

    var errorDescription: String? {
        switch self {
        case .unsupportedFormat(let ext):
            return "Unsupported document format: .\(ext). Attach a PDF, .txt, .md, or .json file."
        case .pdfExtractionFailed:
            return "Failed to extract text from the PDF. The file may be corrupted or image-only."
        case .jsonExtractionFailed(let message):
            return "Failed to parse JSON file: \(message)"
        case .fileReadFailed(let message):
            return "Failed to read file: \(message)"
        }
    }
}

// MARK: - Document Service

struct DocumentService {
    /// Extract plain text from a file at the given URL.
    ///
    /// Supports PDF (via PDFKit), JSON (via JSONSerialization), and plain text.
    /// Calls `startAccessingSecurityScopedResource` for files from UIDocumentPickerViewController.
    ///
    /// - Parameter url: The file URL to extract text from.
    /// - Returns: Plain text content of the document.
    /// - Throws: `DocumentServiceError` for unsupported formats, extraction failures, or file read errors.
    static func extractText(from url: URL) throws -> String {
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
            if hasAccess {
                url.stopAccessingSecurityScopedResource()
            }
        }

        switch DocumentType(url: url) {
        case .pdf:
            return try extractPDFText(from: url)
        case .json:
            return try extractJSONText(from: url)
        case .plainText:
            return try extractPlainText(from: url)
        case .unsupported:
            throw DocumentServiceError.unsupportedFormat(url.pathExtension)
        }
    }

    // MARK: - Private Helpers

    private static func extractPDFText(from url: URL) throws -> String {
        guard let document = PDFDocument(url: url) else {
            throw DocumentServiceError.pdfExtractionFailed
        }

        let pageCount = document.pageCount
        guard pageCount > 0 else {
            throw DocumentServiceError.pdfExtractionFailed
        }

        var pages: [String] = []
        for index in 0..<pageCount {
            guard let page = document.page(at: index) else { continue }
            if let text = page.string, !text.isEmpty {
                pages.append(text)
            }
        }

        let result = pages.joined(separator: "\n")
        guard !result.isEmpty else {
            throw DocumentServiceError.pdfExtractionFailed
        }

        return result
    }

    /// Read a text file, tolerating an encoding that is not UTF-8.
    ///
    /// `String(contentsOf:encoding:.utf8)` throws outright on a file saved as
    /// Latin-1 or UTF-16, which is a common enough export that failing the whole
    /// attachment over it is the wrong trade. `encoding:` (the sniffing
    /// overload) is the fallback, and only a file that is genuinely not text
    /// reaches the error.
    private static func extractPlainText(from url: URL) throws -> String {
        let text: String
        do {
            text = try String(contentsOf: url, encoding: .utf8)
        } catch {
            var detected = String.Encoding.utf8
            guard let sniffed = try? String(contentsOf: url, usedEncoding: &detected) else {
                throw DocumentServiceError.fileReadFailed(error.localizedDescription)
            }
            text = sniffed
        }

        guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
            throw DocumentServiceError.fileReadFailed("The file has no readable text.")
        }
        return text
    }

    private static func extractJSONText(from url: URL) throws -> String {
        let data: Data
        do {
            data = try Data(contentsOf: url)
        } catch {
            throw DocumentServiceError.fileReadFailed(error.localizedDescription)
        }

        let parsed: Any
        do {
            parsed = try JSONSerialization.jsonObject(with: data)
        } catch {
            throw DocumentServiceError.jsonExtractionFailed(error.localizedDescription)
        }

        var strings: [String] = []
        extractStrings(from: parsed, into: &strings)
        return strings.joined(separator: "\n")
    }

    /// Recursively extract all string values from a parsed JSON object.
    private static func extractStrings(from value: Any, into result: inout [String]) {
        if let string = value as? String {
            result.append(string)
        } else if let dict = value as? [String: Any] {
            for (_, dictValue) in dict {
                extractStrings(from: dictValue, into: &result)
            }
        } else if let array = value as? [Any] {
            for element in array {
                extractStrings(from: element, into: &result)
            }
        }
    }
}
