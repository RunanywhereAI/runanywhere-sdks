//
//  DocumentService.swift
//  RunAnywhereAI
//
//  Utility for extracting plain text from PDF and JSON files.
//  Used to prepare document content for RAG ingestion.
//

import Foundation
import PDFKit

// MARK: - Document Type

enum DocumentType {
    case pdf
    case json
    case unsupported

    init(url: URL) {
        switch url.pathExtension.lowercased() {
        case "pdf": self = .pdf
        case "json": self = .json
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
            return "Unsupported document format: .\(ext). Only PDF and JSON files are supported."
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
    /// Supports PDF (via PDFKit) and JSON (via JSONSerialization).
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
