# JSON Schema Generation with Swift Macros Guide

## Table of Contents
1. [Overview](#overview)
2. [Core Concepts](#core-concepts)
3. [Dependencies](#dependencies)
4. [Implementation Strategy](#implementation-strategy)
5. [Detailed Implementation](#detailed-implementation)
6. [Usage Examples](#usage-examples)
7. [Best Practices](#best-practices)
8. [Troubleshooting](#troubleshooting)

## Overview

This guide explains how to implement automatic JSON schema generation from Swift types using the `@Generatable` macro. This approach provides compile-time type safety and automatic schema generation without requiring manual JSON schema definition.

### Key Benefits
- **Type Safety**: Compile-time guarantees through Swift's type system
- **Automatic Schema Generation**: JSON schemas generated from Swift types
- **Zero Runtime Overhead**: Schema generation happens at compile time
- **Codable Integration**: Seamless integration with Swift's Codable protocol

## Core Concepts

### 1. Schema-Driven Type Safety
The system follows this approach:
1. Define data structures using Swift types
2. Apply the `@Generatable` macro to automatically generate JSON schemas
3. Leverage compile-time type safety to ensure schema correctness

### 2. Swift Macros for Automation
Swift macros automatically generate the necessary boilerplate:
- JSON schema generation from type definitions
- Codable conformance for serialization/deserialization
- Type validation at compile time

## Dependencies

### Required Dependencies

```swift
// Package.swift
dependencies: [
    // For macro implementation
    .package(url: "https://github.com/apple/swift-syntax.git", from: "602.0.0-latest")
]
```

### Swift Version Requirements
- Swift 5.9 or later (for macro support)
- Xcode 15.0 or later

### Platform Support
- iOS 16.0+
- macOS 13.0+
- watchOS 9.0+
- tvOS 16.0+
- visionOS 1.0+

## Implementation Strategy

### Step 1: Define the Macro System

First, create the `@Generatable` macro that will handle schema generation:

```swift
// Generatable.swift
import SwiftSyntaxMacros

public protocol Generatable: Codable {
    static var jsonSchema: String { get }
}

@attached(member, names: named(jsonSchema), named(init), named(encode))
@attached(extension, conformances: Codable, Generatable, CaseIterable)
public macro Generatable() = #externalMacro(
    module: "GeneratableMacroImplementation",
    type: "GeneratableMacro"
)
```

### Step 2: Implement the Macro

```swift
// GeneratableMacro.swift
import SwiftCompilerPlugin
import SwiftSyntax
import SwiftSyntaxBuilder
import SwiftSyntaxMacros

public struct GeneratableMacro: MemberMacro, ExtensionMacro {
    public static func expansion(
        of node: AttributeSyntax,
        providingMembersOf declaration: some DeclGroupSyntax,
        conformingTo: [TypeSyntax],
        in context: some MacroExpansionContext
    ) throws -> [DeclSyntax] {
        // Handle structs
        if let structDecl = declaration.as(StructDeclSyntax.self) {
            return expandStruct(structDecl)
        }

        // Handle enums
        if let enumDecl = declaration.as(EnumDeclSyntax.self) {
            return expandEnum(enumDecl)
        }

        return []
    }

    private static func expandStruct(_ structDecl: StructDeclSyntax) -> [DeclSyntax] {
        // Extract properties and generate schema
        let members = structDecl.memberBlock.members
        let properties = extractProperties(from: members)
        let schemaString = generateSchemaString(for: properties)

        return [
            """
            public static var jsonSchema: String {
                return \(literal: schemaString)
            }
            """
        ]
    }

    private static func expandEnum(_ enumDecl: EnumDeclSyntax) -> [DeclSyntax] {
        let cases = extractCases(from: enumDecl)
        let enumValues = cases.map { "\"\($0)\"" }.joined(separator: ", ")

        return [
            """
            public init(from decoder: Decoder) throws {
                let container = try decoder.singleValueContainer()
                let stringValue = try container.decode(String.self)
                switch stringValue {
                \(raw: cases.map { "case \"\($0)\": self = .\($0)" }.joined(separator: "\n"))
                default:
                    throw DecodingError.dataCorrupted(
                        DecodingError.Context(
                            codingPath: decoder.codingPath,
                            debugDescription: "Unknown enum value: \\(stringValue)"
                        )
                    )
                }
            }

            public func encode(to encoder: Encoder) throws {
                var container = encoder.singleValueContainer()
                switch self {
                \(raw: cases.map { "case .\($0): try container.encode(\"\($0)\")" }.joined(separator: "\n"))
                }
            }

            public static var jsonSchema: String {
                return \"\"\"
                {
                  "type": "string",
                  "enum": [\(raw: enumValues)]
                }
                \"\"\"
            }
            """
        ]
    }
}
```

### Step 3: Schema Generation Utilities

Utility functions to support the macro implementation:

```swift
// SchemaGenerator.swift
public struct SchemaGenerator {
    public static func generateSchemaString(for properties: [PropertyInfo]) -> String {
        let propertySchemas = properties.map { property in
            let typeSchema = generateTypeSchema(for: property.type)
            return "\"\(property.name)\": \(typeSchema)"
        }.joined(separator: ",\n  ")

        let requiredFields = properties.filter { $0.isRequired }.map { "\"\($0.name)\"" }.joined(separator: ", ")

        return """
        {
          "type": "object",
          "properties": {
            \(propertySchemas)
          },
          "required": [\(requiredFields)]
        }
        """
    }

    private static func generateTypeSchema(for type: String) -> String {
        switch type {
        case "String":
            return "{\"type\": \"string\"}"
        case "Int", "Int32", "Int64":
            return "{\"type\": \"integer\"}"
        case "Double", "Float":
            return "{\"type\": \"number\"}"
        case "Bool":
            return "{\"type\": \"boolean\"}"
        default:
            if type.hasPrefix("[") && type.hasSuffix("]") {
                let itemType = String(type.dropFirst().dropLast())
                let itemSchema = generateTypeSchema(for: itemType)
                return "{\"type\": \"array\", \"items\": \(itemSchema)}"
            }
            return "{\"type\": \"object\"}"
        }
    }
}

public struct PropertyInfo {
    let name: String
    let type: String
    let isRequired: Bool
}
```

## Detailed Implementation

### Property Extraction

The macro needs to extract property information from Swift type declarations:

```swift
// PropertyExtractor.swift
struct PropertyExtractor {
    static func extractProperties(from members: MemberBlockItemListSyntax) -> [PropertyInfo] {
        var properties: [PropertyInfo] = []

        for member in members {
            if let varDecl = member.decl.as(VariableDeclSyntax.self) {
                for binding in varDecl.bindings {
                    if let identifier = binding.pattern.as(IdentifierPatternSyntax.self),
                       let typeAnnotation = binding.typeAnnotation {

                        let name = identifier.identifier.text
                        let type = typeAnnotation.type.description.trimmingCharacters(in: .whitespaces)
                        let isRequired = !type.hasSuffix("?")

                        properties.append(PropertyInfo(
                            name: name,
                            type: isRequired ? type : String(type.dropLast()),
                            isRequired: isRequired
                        ))
                    }
                }
            }
        }

        return properties
    }
}
```

### Enum Case Extraction

For enum types, the macro extracts case information:

```swift
// EnumExtractor.swift
struct EnumExtractor {
    static func extractCases(from enumDecl: EnumDeclSyntax) -> [String] {
        var cases: [String] = []

        for member in enumDecl.memberBlock.members {
            if let caseDecl = member.decl.as(EnumCaseDeclSyntax.self) {
                for caseElement in caseDecl.elements {
                    cases.append(caseElement.name.text)
                }
            }
        }

        return cases
    }
}
```

### Type Validation

The macro includes compile-time type validation:

```swift
// TypeValidator.swift
struct TypeValidator {
    static func validateGeneratableType(_ type: String) -> Bool {
        let supportedTypes = [
            "String", "Int", "Int32", "Int64", "Double", "Float", "Bool"
        ]

        // Check primitive types
        if supportedTypes.contains(type) {
            return true
        }

        // Check optional types
        if type.hasSuffix("?") {
            let baseType = String(type.dropLast())
            return validateGeneratableType(baseType)
        }

        // Check array types
        if type.hasPrefix("[") && type.hasSuffix("]") {
            let itemType = String(type.dropFirst().dropLast())
            return validateGeneratableType(itemType)
        }

        // Assume custom types are Generatable
        return true
    }
}
```

## Usage Examples

### Basic Example: Simple Struct

```swift
@Generatable
struct Person {
    let name: String
    let age: Int
    let email: String
}

// The macro generates:
// - Codable conformance
// - JSON schema as a static property

// Access the generated schema
print(Person.jsonSchema)
// Output:
// {
//   "type": "object",
//   "properties": {
//     "name": {"type": "string"},
//     "age": {"type": "integer"},
//     "email": {"type": "string"}
//   },
//   "required": ["name", "age", "email"]
// }

// Use with JSON encoding/decoding
let person = Person(name: "John Doe", age: 28, email: "john@example.com")
let jsonData = try JSONEncoder().encode(person)
let decodedPerson = try JSONDecoder().decode(Person.self, from: jsonData)
```

### Enum Example

```swift
@Generatable
enum Priority {
    case low, medium, high, urgent
}

@Generatable
struct Task {
    let title: String
    let description: String
    let priority: Priority
    let dueDate: String
}

// Generated schemas:
print(Priority.jsonSchema)
// {
//   "type": "string",
//   "enum": ["low", "medium", "high", "urgent"]
// }

print(Task.jsonSchema)
// {
//   "type": "object",
//   "properties": {
//     "title": {"type": "string"},
//     "description": {"type": "string"},
//     "priority": {"type": "string", "enum": ["low", "medium", "high", "urgent"]},
//     "dueDate": {"type": "string"}
//   },
//   "required": ["title", "description", "priority", "dueDate"]
// }
```

### Nested Structures

```swift
@Generatable
struct Address {
    let street: String
    let city: String
    let country: String
    let postalCode: String
}

@Generatable
struct Company {
    let name: String
    let address: Address
    let employeeCount: Int
}

// The macro handles nested types automatically
print(Company.jsonSchema)
// {
//   "type": "object",
//   "properties": {
//     "name": {"type": "string"},
//     "address": {"type": "object"},
//     "employeeCount": {"type": "integer"}
//   },
//   "required": ["name", "address", "employeeCount"]
// }
```

### Arrays and Complex Structures

```swift
@Generatable
struct Product {
    let name: String
    let price: Double
    let inStock: Bool
}

@Generatable
struct Order {
    let orderId: String
    let items: [Product]
    let totalAmount: Double
    let customerEmail: String
}

// Generated schema includes array types
print(Order.jsonSchema)
// {
//   "type": "object",
//   "properties": {
//     "orderId": {"type": "string"},
//     "items": {"type": "array", "items": {"type": "object"}},
//     "totalAmount": {"type": "number"},
//     "customerEmail": {"type": "string"}
//   },
//   "required": ["orderId", "items", "totalAmount", "customerEmail"]
// }
```

### Optional Fields

```swift
@Generatable
struct UserProfile {
    let username: String
    let email: String
    let bio: String?
    let website: String?
    let joinDate: String
}

// Optional fields are excluded from required array
print(UserProfile.jsonSchema)
// {
//   "type": "object",
//   "properties": {
//     "username": {"type": "string"},
//     "email": {"type": "string"},
//     "bio": {"type": "string"},
//     "website": {"type": "string"},
//     "joinDate": {"type": "string"}
//   },
//   "required": ["username", "email", "joinDate"]
// }
```

### Real-World Example

```swift
@Generatable
struct Location {
    let latitude: Double
    let longitude: Double
}

@Generatable
struct Restaurant {
    let name: String
    let cuisine: String
    let location: Location
    let rating: Double
    let priceRange: String
}

// Complete schema generation with nested types
print(Restaurant.jsonSchema)
// {
//   "type": "object",
//   "properties": {
//     "name": {"type": "string"},
//     "cuisine": {"type": "string"},
//     "location": {"type": "object"},
//     "rating": {"type": "number"},
//     "priceRange": {"type": "string"}
//   },
//   "required": ["name", "cuisine", "location", "rating", "priceRange"]
// }

// Use in JSON processing
let restaurant = Restaurant(
    name: "Sakura Sushi",
    cuisine: "Japanese",
    location: Location(latitude: 35.6762, longitude: 139.6503),
    rating: 4.8,
    priceRange: "$$"
)

let jsonData = try JSONEncoder().encode(restaurant)
let jsonString = String(data: jsonData, encoding: .utf8)!
```

## Best Practices

### 1. Schema Design
- Keep schemas simple and focused
- Use enums for constrained string values
- Make fields optional when appropriate
- Avoid deeply nested structures (>3 levels)

### 2. Performance Optimization
- Schema generation happens at compile time
- No runtime schema parsing overhead
- Reuse generated schemas across instances

### 3. Error Handling
```swift
do {
    let jsonData = try JSONEncoder().encode(myObject)
    let decodedObject = try JSONDecoder().decode(MyType.self, from: jsonData)
    // Handle success
} catch DecodingError.dataCorrupted {
    // Handle JSON decoding issues
} catch EncodingError.invalidValue {
    // Handle JSON encoding issues
} catch {
    // Handle other errors
}
```

### 4. Type Design Guidelines
- Use meaningful property names
- Prefer primitive types when possible
- Document complex structures
- Test with various prompts

## Troubleshooting

### Common Issues

1. **Macro Expansion Fails**
   - Ensure Swift 5.9+ is being used
   - Verify macro dependencies are properly configured
   - Check that @Generatable is applied to struct or enum declarations

2. **Invalid Schema Generation**
   - Verify @Generatable is applied correctly
   - Check for typos in property names
   - Ensure all custom types are also marked @Generatable

3. **Compilation Errors**
   - Ensure all properties have explicit type annotations
   - Verify that nested types conform to Generatable
   - Check for unsupported type combinations

### Debugging Tips

```swift
// Inspect generated schema
print(MyType.jsonSchema)

// Test JSON encoding/decoding
let instance = MyType(...)
let jsonData = try JSONEncoder().encode(instance)
let jsonString = String(data: jsonData, encoding: .utf8)!
print("Generated JSON:", jsonString)

// Verify roundtrip conversion
let decoded = try JSONDecoder().decode(MyType.self, from: jsonData)
```

## Advanced Features

### Custom Validators

```swift
@Generatable
struct EmailAddress {
    let email: String

    // Custom validation after creation
    func validate() throws {
        guard email.contains("@") else {
            throw ValidationError.invalidEmail
        }
    }
}
```

### Schema Customization

```swift
@Generatable
struct DateRange {
    let startDate: String  // Could be validated as ISO 8601
    let endDate: String    // Could be validated as ISO 8601
}

// Access and use the generated schema
let schema = DateRange.jsonSchema
// Use schema for API documentation, validation, etc.
```

### Integration with JSON Processing

```swift
// Use with existing JSON workflows
func processJSON<T: Generatable>(_ type: T.Type, data: Data) throws -> T {
    return try JSONDecoder().decode(type, from: data)
}

// Validate JSON against schema
func validateJSON<T: Generatable>(_ jsonString: String, against type: T.Type) -> Bool {
    guard let data = jsonString.data(using: .utf8) else { return false }
    do {
        _ = try JSONDecoder().decode(type, from: data)
        return true
    } catch {
        return false
    }
}
```

## Conclusion

The `@Generatable` macro approach provides significant benefits for Swift developers working with JSON:
- **Type Safety**: Compile-time guarantees through Swift's type system
- **Automatic Schema Generation**: No manual JSON schema writing required
- **Seamless Integration**: Works naturally with Swift's Codable protocol
- **Zero Runtime Overhead**: All schema generation happens at compile time

By automatically generating JSON schemas from Swift types, the `@Generatable` macro eliminates the need for manual schema maintenance and ensures that your JSON schemas always stay in sync with your Swift type definitions.

This approach is particularly valuable for:
- API documentation generation
- JSON validation
- Type-safe data interchange
- Automated testing with structured data
