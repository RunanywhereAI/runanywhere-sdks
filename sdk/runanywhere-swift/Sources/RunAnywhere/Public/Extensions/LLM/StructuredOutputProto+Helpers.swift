//
//  StructuredOutputProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Structured Output proto types.
//

import Foundation

// MARK: - RAStructuredOutputOptions

extension RAStructuredOutputOptions {
    public static func defaults(
        schema: RAJSONSchema,
        includeSchemaInPrompt: Bool = true,
        strict: Bool = false
    ) -> RAStructuredOutputOptions {
        var o = RAStructuredOutputOptions()
        o.schema = schema
        o.includeSchemaInPrompt = includeSchemaInPrompt
        o.strictMode = strict
        return o
    }
}

// MARK: - RAStructuredOutputValidation

extension RAStructuredOutputValidation {
    public init(
        isValid: Bool,
        containsJson: Bool = false,
        errorMessage: String? = nil,
        rawOutput: String? = nil
    ) {
        self.init()
        self.isValid = isValid
        self.containsJson = containsJson
        if let err = errorMessage { self.errorMessage = err }
        if let raw = rawOutput { self.rawOutput = raw }
    }
}

// MARK: - RAStructuredOutputResult

extension RAStructuredOutputResult {
    public var success: Bool { validation.isValid }
}

// MARK: - RANamedEntity

extension RANamedEntity {
    public init(
        text: String,
        entityType: String,
        startOffset: Int32,
        endOffset: Int32,
        confidence: Float
    ) {
        self.init()
        self.text = text
        self.entityType = entityType
        self.startOffset = startOffset
        self.endOffset = endOffset
        self.confidence = confidence
    }

    public var length: Int32 { max(0, endOffset - startOffset) }
}
