# Structured Output Implementation Plan for RunAnywhere Swift SDK

## Executive Summary

This plan outlines the implementation of a structured output capability for the RunAnywhere Swift SDK that enables LLMs to generate type-safe, structured objects using Swift's `@Generatable` macro system. The implementation will integrate seamlessly with the SDK's existing capabilities-driven architecture while providing compile-time type safety and automatic JSON schema generation.

## Table of Contents

1. [Overview](#overview)
2. [Architecture Design](#architecture-design)
3. [Implementation Phases](#implementation-phases)
4. [Technical Components](#technical-components)
5. [Integration Points](#integration-points)
6. [API Design](#api-design)
7. [Testing Strategy](#testing-strategy)
8. [Timeline & Milestones](#timeline--milestones)

## Overview

### Goals
- Enable structured output generation with compile-time type safety
- Integrate `@Generatable` macro system for automatic JSON schema generation
- Support constrained generation to ensure LLM outputs match schema
- Provide seamless integration with existing SDK capabilities
- Maintain zero runtime overhead through compile-time schema generation

### Key Features
- **Type-Safe Output**: Guarantee LLM outputs conform to Swift types
- **Automatic Schema Generation**: Generate JSON schemas from Swift types using macros
- **Constrained Generation**: Force LLMs to produce valid structured objects
- **Framework Support**: Work across all supported ML frameworks
- **Error Recovery**: Handle schema validation failures gracefully

## Architecture Design

### New Capability Module: StructuredOutput

Following the SDK's capabilities-driven architecture, we'll create a new capability module:

```
Capabilities/StructuredOutput/
├── Protocols/
│   ├── StructuredOutputGenerator.swift
│   ├── SchemaValidator.swift
│   └── ConstraintEngine.swift
├── Services/
│   ├── StructuredOutputService.swift
│   ├── SchemaGenerationService.swift
│   └── ValidationService.swift
├── Models/
│   ├── StructuredOutputRequest.swift
│   ├── StructuredOutputResult.swift
│   └── SchemaConstraints.swift
├── Strategies/
│   ├── JSONSchemaStrategy.swift
│   ├── GrammarBasedStrategy.swift
│   └── TokenMaskingStrategy.swift
├── Implementations/
│   ├── CoreMLStructuredOutput.swift
│   ├── GGUFStructuredOutput.swift
│   └── TensorFlowLiteStructuredOutput.swift
└── Validation/
    ├── OutputValidator.swift
    └── SchemaEnforcer.swift
```

### Integration with Existing Architecture

The structured output capability will integrate with:

1. **TextGeneration Capability**: Extend generation to support structured outputs
2. **Routing Service**: Route based on framework support for constrained generation
3. **Framework Adapters**: Add structured output support to each adapter
4. **Error Recovery**: Handle schema validation failures
5. **Monitoring**: Track structured output success rates

## Implementation Phases

### Phase 1: Core Infrastructure (Week 1-2)

1. **Macro System Setup**
   - Implement `@Generatable` macro using Swift Syntax
   - Create schema generation utilities
   - Set up macro compilation pipeline

2. **Core Protocols & Models**
   - Define `StructuredOutputGenerator` protocol
   - Create request/result models
   - Implement schema constraint types

3. **Basic Service Implementation**
   - Create `StructuredOutputService` skeleton
   - Implement schema validation logic
   - Set up dependency injection

### Phase 2: Generation Strategies (Week 3-4)

1. **JSON Schema Strategy**
   - Convert Swift schemas to JSON Schema format
   - Implement schema-guided generation
   - Add response parsing and validation

2. **Grammar-Based Strategy**
   - Implement GBNF (Grammar-Based Natural Format) support
   - Create grammar generation from schemas
   - Add grammar-constrained decoding

3. **Token Masking Strategy**
   - Implement token-level constraints
   - Create invalid token masking logic
   - Add beam search with constraints

### Phase 3: Framework Integration (Week 5-6)

1. **Framework Adapter Updates**
   - Add structured output support to each adapter
   - Implement framework-specific optimizations
   - Handle capability detection

2. **Specific Implementations**
   - CoreML: Use model configuration for constraints
   - GGUF/llama.cpp: Integrate grammar-based generation
   - TensorFlow Lite: Implement custom decoding

### Phase 4: API & Developer Experience (Week 7)

1. **Public API Design**
   - Extend `RunAnywhereSDK` with structured output methods
   - Create convenient type-safe APIs
   - Add async/streaming support

2. **Documentation & Examples**
   - Create comprehensive usage guide
   - Add code examples for common patterns
   - Document best practices

### Phase 5: Testing & Optimization (Week 8)

1. **Testing Suite**
   - Unit tests for all components
   - Integration tests with real models
   - Performance benchmarks

2. **Optimization**
   - Profile generation performance
   - Optimize constraint checking
   - Improve error messages

## Technical Components

### 1. Macro Implementation

```swift
// Sources/RunAnywhere/Macros/Generatable.swift
@attached(member, names: named(jsonSchema))
@attached(extension, conformances: Codable, Generatable)
public macro Generatable() = #externalMacro(
    module: "RunAnywhereMacros",
    type: "GeneratableMacro"
)

public protocol Generatable: Codable {
    static var jsonSchema: String { get }
}
```

### 2. Structured Output Service

```swift
// Sources/RunAnywhere/Capabilities/StructuredOutput/Services/StructuredOutputService.swift
public actor StructuredOutputService: StructuredOutputGenerator {
    private let generationService: TextGenerator
    private let validationService: SchemaValidator
    private let routingService: RoutingEngine
    private let strategies: [StructuredOutputStrategy]

    public func generate<T: Generatable>(
        prompt: String,
        outputType: T.Type,
        options: GenerationOptions? = nil
    ) async throws -> T {
        // 1. Get schema from type
        let schema = T.jsonSchema

        // 2. Determine best strategy based on routing
        let routing = try await routingService.determineRouting(prompt, context, options)
        let strategy = selectStrategy(for: routing)

        // 3. Generate with constraints
        let constrainedOptions = options?.withSchema(schema) ?? GenerationOptions(schema: schema)
        let result = try await strategy.generateStructured(prompt, schema: schema, options: constrainedOptions)

        // 4. Validate and parse
        let validated = try await validationService.validate(result.text, against: schema)
        return try JSONDecoder().decode(T.self, from: validated.data(using: .utf8)!)
    }

    public func generateStream<T: Generatable>(
        prompt: String,
        outputType: T.Type,
        options: GenerationOptions? = nil
    ) -> AsyncThrowingStream<StructuredStreamingUpdate<T>, Error> {
        // Streaming implementation with progressive validation
    }
}
```

### 3. Framework-Specific Implementations

```swift
// Sources/RunAnywhere/Capabilities/StructuredOutput/Implementations/GGUFStructuredOutput.swift
class GGUFStructuredOutputAdapter: StructuredOutputStrategy {
    func generateStructured(
        prompt: String,
        schema: String,
        options: GenerationOptions
    ) async throws -> StructuredOutputResult {
        // Convert schema to GBNF grammar
        let grammar = try GrammarConverter.schemaToGBNF(schema)

        // Use llama.cpp's grammar-based generation
        let grammarOptions = LlamaCppOptions(
            grammar: grammar,
            temperature: options.temperature ?? 0.1,
            maxTokens: options.maxTokens ?? 1000
        )

        // Generate with constraints
        let result = try await llamaCppService.generateWithGrammar(prompt, options: grammarOptions)

        return StructuredOutputResult(
            text: result.text,
            validationStatus: .valid,
            metrics: result.metrics
        )
    }
}
```

### 4. Public API Extensions

```swift
// Sources/RunAnywhere/Public/RunAnywhereSDK+StructuredOutput.swift
public extension RunAnywhereSDK {
    /// Generate structured output that conforms to a Generatable type
    func generateStructured<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: GenerationOptions? = nil
    ) async throws -> T {
        guard isInitialized else { throw SDKError.notInitialized }

        return try await container.structuredOutputService.generate(
            prompt: prompt,
            outputType: type,
            options: options
        )
    }

    /// Generate structured output with streaming updates
    func generateStructuredStream<T: Generatable>(
        _ type: T.Type,
        prompt: String,
        options: GenerationOptions? = nil
    ) -> AsyncThrowingStream<StructuredStreamingUpdate<T>, Error> {
        guard isInitialized else {
            return AsyncThrowingStream { continuation in
                continuation.finish(throwing: SDKError.notInitialized)
            }
        }

        return container.structuredOutputService.generateStream(
            prompt: prompt,
            outputType: type,
            options: options
        )
    }
}
```

## Integration Points

### 1. Service Container Integration

```swift
// Update ServiceContainer.swift
public class ServiceContainer {
    // Add structured output service
    private(set) lazy var structuredOutputService: StructuredOutputService = {
        StructuredOutputService(
            generationService: generationService,
            validationService: schemaValidationService,
            routingService: routingService,
            logger: logger
        )
    }()

    private(set) lazy var schemaValidationService: SchemaValidationService = {
        SchemaValidationService(logger: logger)
    }()
}
```

### 2. Framework Adapter Protocol Extension

```swift
// Update FrameworkAdapter protocol
protocol FrameworkAdapter {
    // Existing methods...

    // Add structured output support
    func supportsStructuredOutput() -> Bool
    func createStructuredOutputStrategy() -> StructuredOutputStrategy?
}
```

### 3. Generation Options Extension

```swift
// Extend GenerationOptions
public extension GenerationOptions {
    var schema: String?
    var schemaValidation: SchemaValidationMode
    var constraintStrategy: ConstraintStrategy

    enum SchemaValidationMode {
        case strict      // Fail on any deviation
        case lenient     // Allow minor deviations
        case bestEffort  // Extract what's possible
    }

    enum ConstraintStrategy {
        case jsonSchema     // Use JSON schema constraints
        case grammar        // Use grammar-based generation
        case tokenMasking   // Use token-level constraints
        case automatic      // Let SDK choose
    }
}
```

## API Design

### Basic Usage

```swift
// Define a structured output type
@Generatable
struct WeatherReport {
    let location: String
    let temperature: Double
    let conditions: String
    let humidity: Int
}

// Generate structured output
let weather = try await sdk.generateStructured(
    WeatherReport.self,
    prompt: "What's the weather in San Francisco?"
)
print("Temperature: \(weather.temperature)°F")
```

### Advanced Usage

```swift
// Complex nested structure
@Generatable
struct AnalysisReport {
    let summary: String
    let sentimentScores: SentimentScores
    let keyTopics: [Topic]
    let recommendations: [String]
}

@Generatable
struct SentimentScores {
    let positive: Double
    let negative: Double
    let neutral: Double
}

@Generatable
struct Topic {
    let name: String
    let relevance: Double
}

// Generate with options
let options = GenerationOptions(
    temperature: 0.1,
    schemaValidation: .strict,
    constraintStrategy: .grammar
)

let analysis = try await sdk.generateStructured(
    AnalysisReport.self,
    prompt: "Analyze this customer feedback: ...",
    options: options
)
```

### Streaming Usage

```swift
// Stream structured updates
for try await update in sdk.generateStructuredStream(WeatherReport.self, prompt: prompt) {
    switch update {
    case .partial(let json):
        print("Partial: \(json)")
    case .complete(let weather):
        print("Complete: \(weather)")
    case .validationError(let error):
        print("Validation error: \(error)")
    }
}
```

## Testing Strategy

### 1. Unit Tests

```swift
// Test schema generation
func testSchemaGeneration() {
    @Generatable
    struct TestStruct {
        let name: String
        let age: Int
    }

    let expectedSchema = """
    {
      "type": "object",
      "properties": {
        "name": {"type": "string"},
        "age": {"type": "integer"}
      },
      "required": ["name", "age"]
    }
    """

    XCTAssertEqual(TestStruct.jsonSchema, expectedSchema)
}

// Test structured generation
func testStructuredGeneration() async throws {
    let result = try await service.generate(
        prompt: "Create a person",
        outputType: Person.self
    )

    XCTAssertNotNil(result.name)
    XCTAssertGreaterThan(result.age, 0)
}
```

### 2. Integration Tests

- Test with each supported framework
- Verify constraint enforcement
- Test error recovery scenarios
- Validate streaming behavior

### 3. Performance Tests

- Benchmark schema generation time
- Measure constraint checking overhead
- Compare strategies performance
- Test with various model sizes

## Timeline & Milestones

### Week 1-2: Core Infrastructure
- [ ] Implement @Generatable macro
- [ ] Create core protocols and models
- [ ] Set up basic service structure

### Week 3-4: Generation Strategies
- [ ] Implement JSON schema strategy
- [ ] Add grammar-based generation
- [ ] Create token masking strategy

### Week 5-6: Framework Integration
- [ ] Update framework adapters
- [ ] Implement framework-specific logic
- [ ] Add capability detection

### Week 7: API & Documentation
- [ ] Design public API
- [ ] Create usage examples
- [ ] Write documentation

### Week 8: Testing & Polish
- [ ] Complete test suite
- [ ] Performance optimization
- [ ] Bug fixes and refinements

## Success Criteria

1. **Functionality**
   - Successfully generate structured outputs for all supported types
   - Work with at least 3 major frameworks (CoreML, GGUF, TFLite)
   - Handle nested structures and arrays

2. **Performance**
   - Schema generation < 1ms at compile time
   - Constraint checking adds < 10% overhead
   - Streaming maintains real-time feel

3. **Developer Experience**
   - Simple, intuitive API
   - Clear error messages
   - Comprehensive documentation

4. **Reliability**
   - 95%+ success rate for valid schemas
   - Graceful error recovery
   - No crashes or hangs

## Risk Mitigation

1. **Framework Limitations**
   - Some frameworks may not support constrained generation
   - Mitigation: Implement post-generation validation fallback

2. **Performance Impact**
   - Constraint checking could slow generation
   - Mitigation: Optimize hot paths, cache compiled schemas

3. **Schema Complexity**
   - Very complex schemas might be challenging
   - Mitigation: Set reasonable complexity limits, provide guidelines

## Next Steps

1. Review and approve this plan
2. Set up macro development environment
3. Begin Phase 1 implementation
4. Create tracking issues for each component
5. Schedule regular progress reviews

## Appendix: Technical Details

### Grammar Conversion Example

```swift
// JSON Schema to GBNF Grammar conversion
let jsonSchema = """
{
  "type": "object",
  "properties": {
    "name": {"type": "string"},
    "age": {"type": "integer"}
  },
  "required": ["name", "age"]
}
"""

// Converts to GBNF:
let gbnfGrammar = """
root ::= "{" ws "\"name\"" ws ":" ws string "," ws "\"age\"" ws ":" ws number ws "}"
string ::= "\"" ([^"\\] | "\\" .)* "\""
number ::= [0-9]+
ws ::= [ \t\n]*
"""
```

### Token Masking Algorithm

```swift
// Pseudocode for token masking
func maskInvalidTokens(schema: Schema, partialOutput: String, nextTokenLogits: [Float]) -> [Float] {
    let validNextTokens = schema.getValidNextTokens(after: partialOutput)
    var maskedLogits = nextTokenLogits

    for (index, token) in vocabulary.enumerated() {
        if !validNextTokens.contains(token) {
            maskedLogits[index] = -Float.infinity
        }
    }

    return maskedLogits
}
```

This implementation plan provides a comprehensive roadmap for adding structured output capabilities to the RunAnywhere Swift SDK while maintaining its clean architecture and high performance standards.
