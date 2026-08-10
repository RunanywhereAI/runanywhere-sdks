//
//  StructuredOutputProto+Helpers.swift
//  RunAnywhere SDK
//
//  Ergonomic helpers for canonical Structured Output proto types.
//

import CRACommons
import Foundation

// MARK: - RAStructuredOutputOptions

extension RAStructuredOutputOptions {
    /// `RAJSONSchema`/`strictMode`/`jsonSchema`/`mode` were all deleted
    /// outright (idl/structured_output.proto): the message shrunk to just
    /// `includeSchemaInPrompt` plus a `schema`/`grammar`/`regex` oneof of
    /// raw strings, so `schema` here is JSON Schema text directly rather
    /// than a typed tree to serialize.
    public static func defaults(
        schema: String,
        includeSchemaInPrompt: Bool = true
    ) -> RAStructuredOutputOptions {
        var options = RAStructuredOutputOptions()
        options.schema = schema
        options.includeSchemaInPrompt = includeSchemaInPrompt
        return options
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
        if let err = errorMessage {
            self.error = RASDKError.make(
                code: .validationFailed,
                message: err,
                category: .validation
            )
        }
        if let raw = rawOutput { self.rawOutput = raw }
    }
}

// MARK: - RAStructuredOutputResult

extension RAStructuredOutputResult {
    public var success: Bool { validation.isValid }
}

// RANamedEntity was deleted outright (idl/structured_output.proto) with no
// replacement — named-entity extraction has no proto home anymore.
