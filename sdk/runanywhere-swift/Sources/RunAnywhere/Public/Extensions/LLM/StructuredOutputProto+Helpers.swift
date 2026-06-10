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
    public static func defaults(
        schema: RAJSONSchema,
        includeSchemaInPrompt: Bool = true,
        strict: Bool = false
    ) -> RAStructuredOutputOptions {
        var options = RAStructuredOutputOptions()
        options.schema = schema
        options.includeSchemaInPrompt = includeSchemaInPrompt
        options.strictMode = strict
        options.jsonSchema = schema.jsonSchemaString
        options.mode = .jsonSchema
        return options
    }
}

// MARK: - RAJSONSchema

extension RAJSONSchema {
    /// JSON Schema text consumed by the commons structured-output C ABI.
    ///
    /// Delegates to `rac_structured_output_schema_to_json_proto` so
    /// every SDK shares the same byte-exact, key-sorted, compact serializer.
    /// Returns `"{}"` on any serialization or ABI failure to preserve the
    /// previous fallback contract.
    public var jsonSchemaString: String {
        guard let serialized = try? self.serializedData() else { return "{}" }
        var outBuffer = rac_proto_buffer_t()
        defer { rac_proto_buffer_free(&outBuffer) }

        let status = serialized.withUnsafeBytes { rawBuffer -> rac_result_t in
            let bytes = rawBuffer.bindMemory(to: UInt8.self).baseAddress
            return rac_structured_output_schema_to_json_proto(bytes, rawBuffer.count, &outBuffer)
        }
        guard status == RAC_SUCCESS, outBuffer.status == RAC_SUCCESS,
              let data = outBuffer.data, outBuffer.size > 0,
              let text = String(data: Data(bytes: data, count: outBuffer.size), encoding: .utf8) else {
            return "{}"
        }
        return text
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
