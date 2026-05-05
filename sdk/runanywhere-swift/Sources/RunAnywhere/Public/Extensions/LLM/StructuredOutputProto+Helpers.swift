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
        o.jsonSchema = schema.jsonSchemaString
        o.mode = .jsonSchema
        return o
    }
}

// MARK: - RAJSONSchema

extension RAJSONSchema {
    /// JSON Schema text consumed by the commons structured-output C ABI.
    public var jsonSchemaString: String {
        if hasRawJson, !rawJson.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return rawJson
        }

        let object = JSONSchemaWriter.object(from: self)
        guard JSONSerialization.isValidJSONObject(object),
              let data = try? JSONSerialization.data(withJSONObject: object, options: [.sortedKeys]),
              let string = String(data: data, encoding: .utf8) else {
            return "{}"
        }
        return string
    }
}

private enum JSONSchemaWriter {
    static func object(from schema: RAJSONSchema) -> [String: Any] {
        if schema.hasRawJson, let raw = dictionary(from: schema.rawJson) {
            return raw
        }

        var schemaObject: [String: Any] = [:]
        if let type = schema.type.jsonSchemaName {
            schemaObject["type"] = type
        }
        if !schema.properties.isEmpty {
            schemaObject["properties"] = schema.properties.mapValues { object(from: $0) }
        }
        if !schema.required.isEmpty {
            schemaObject["required"] = schema.required
        }
        if schema.hasItems {
            schemaObject["items"] = object(from: schema.items)
        }
        if schema.hasAdditionalProperties {
            schemaObject["additionalProperties"] = schema.additionalProperties
        }
        if schema.hasSchemaUri {
            schemaObject["$schema"] = schema.schemaUri
        }
        if schema.hasIDUri {
            schemaObject["$id"] = schema.idUri
        }
        if schema.hasTitle {
            schemaObject["title"] = schema.title
        }
        if schema.hasDescription_p {
            schemaObject["description"] = schema.description_p
        }
        if !schema.definitions.isEmpty {
            schemaObject["definitions"] = schema.definitions.mapValues { object(from: $0) }
        }
        if schema.hasRef {
            schemaObject["$ref"] = schema.ref
        }
        if !schema.allOf.isEmpty {
            schemaObject["allOf"] = schema.allOf.map { object(from: $0) }
        }
        if !schema.anyOf.isEmpty {
            schemaObject["anyOf"] = schema.anyOf.map { object(from: $0) }
        }
        if !schema.oneOf.isEmpty {
            schemaObject["oneOf"] = schema.oneOf.map { object(from: $0) }
        }
        if schema.hasNotSchema {
            schemaObject["not"] = object(from: schema.notSchema)
        }
        return schemaObject
    }

    static func object(from property: RAJSONSchemaProperty) -> [String: Any] {
        var object = property.hasObjectSchema ? object(from: property.objectSchema) : [:]

        if let type = property.type.jsonSchemaName {
            object["type"] = type
        }
        if property.hasDescription_p {
            object["description"] = property.description_p
        }
        if !property.enumValues.isEmpty {
            object["enum"] = property.enumValues
        }
        if property.hasFormat {
            object["format"] = property.format
        }
        if property.hasItemsSchema {
            object["items"] = self.object(from: property.itemsSchema)
        }
        if property.hasMinimum {
            object["minimum"] = property.minimum
        }
        if property.hasMaximum {
            object["maximum"] = property.maximum
        }
        if property.hasMinLength {
            object["minLength"] = Int(property.minLength)
        }
        if property.hasMaxLength {
            object["maxLength"] = Int(property.maxLength)
        }
        if property.hasPattern {
            object["pattern"] = property.pattern
        }
        if property.hasMinItems {
            object["minItems"] = Int(property.minItems)
        }
        if property.hasMaxItems {
            object["maxItems"] = Int(property.maxItems)
        }
        if property.hasDefaultJson {
            object["default"] = jsonValue(from: property.defaultJson)
        }
        return object
    }

    private static func dictionary(from json: String) -> [String: Any]? {
        guard let data = json.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return object
    }

    private static func jsonValue(from json: String) -> Any {
        guard let data = json.data(using: .utf8),
              let value = try? JSONSerialization.jsonObject(with: data) else {
            return json
        }
        return value
    }
}

private extension RAJSONSchemaType {
    var jsonSchemaName: String? {
        switch self {
        case .object: return "object"
        case .array: return "array"
        case .string: return "string"
        case .number: return "number"
        case .integer: return "integer"
        case .boolean: return "boolean"
        case .null: return "null"
        default: return nil
        }
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
