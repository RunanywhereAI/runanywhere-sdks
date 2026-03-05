import Foundation
import PDFKit
import React

/// Native document text extraction using PDFKit.
/// Mirrors the iOS example app's DocumentService.swift for RAG document ingestion.
@objc(DocumentService)
class DocumentService: NSObject {

  @objc static func requiresMainQueueSetup() -> Bool {
    return false
  }

  /// Extract plain text from a file at the given path.
  /// Supports PDF (via PDFKit) and JSON / plain text (via String).
  @objc func extractText(
    _ filePath: String,
    withResolver resolve: @escaping RCTPromiseResolveBlock,
    withRejecter reject: @escaping RCTPromiseRejectBlock
  ) {
    DispatchQueue.global(qos: .userInitiated).async {
      do {
        // Document picker may return a file:// URI or a bare path
        let url: URL
        if filePath.hasPrefix("file://") {
          url = URL(string: filePath) ?? URL(fileURLWithPath: filePath)
        } else {
          url = URL(fileURLWithPath: filePath)
        }
        let hasAccess = url.startAccessingSecurityScopedResource()
        defer {
          if hasAccess { url.stopAccessingSecurityScopedResource() }
        }

        let ext = url.pathExtension.lowercased()
        let text: String

        switch ext {
        case "pdf":
          text = try Self.extractPDFText(from: url)
        case "json":
          text = try Self.extractJSONText(from: url)
        default:
          text = try String(contentsOf: url, encoding: .utf8)
        }

        resolve(text)
      } catch {
        reject("EXTRACT_ERROR", error.localizedDescription, error)
      }
    }
  }

  // MARK: - PDF extraction (PDFKit)

  private static func extractPDFText(from url: URL) throws -> String {
    guard let document = PDFDocument(url: url) else {
      throw NSError(domain: "DocumentService", code: 1,
                    userInfo: [NSLocalizedDescriptionKey: "Failed to open PDF. File may be corrupted or image-only."])
    }
    guard document.pageCount > 0 else {
      throw NSError(domain: "DocumentService", code: 2,
                    userInfo: [NSLocalizedDescriptionKey: "PDF has no pages."])
    }

    var pages: [String] = []
    for i in 0..<document.pageCount {
      if let page = document.page(at: i), let text = page.string, !text.isEmpty {
        pages.append(text)
      }
    }

    let result = pages.joined(separator: "\n")
    guard !result.isEmpty else {
      throw NSError(domain: "DocumentService", code: 3,
                    userInfo: [NSLocalizedDescriptionKey: "PDF contains no extractable text (may be image-only)."])
    }
    return result
  }

  // MARK: - JSON extraction (recursive string values)

  private static func extractJSONText(from url: URL) throws -> String {
    let data = try Data(contentsOf: url)
    let parsed = try JSONSerialization.jsonObject(with: data)
    var strings: [String] = []
    extractStrings(from: parsed, into: &strings)
    return strings.joined(separator: "\n")
  }

  private static func extractStrings(from value: Any, into result: inout [String]) {
    if let string = value as? String {
      result.append(string)
    } else if let dict = value as? [String: Any] {
      for (_, v) in dict {
        extractStrings(from: v, into: &result)
      }
    } else if let array = value as? [Any] {
      for element in array {
        extractStrings(from: element, into: &result)
      }
    }
  }
}
