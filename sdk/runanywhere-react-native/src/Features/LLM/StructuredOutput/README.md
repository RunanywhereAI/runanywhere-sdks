# Structured Output for React Native SDK

This module provides structured output generation capabilities for LLMs, matching the iOS implementation.

## Overview

The Structured Output system allows you to generate type-safe, validated JSON outputs from LLM responses. It includes:

- **Generatable Protocol**: Interface for types that can be generated
- **Generation Hints**: Fine-tune generation behavior
- **Stream Support**: Real-time streaming with token accumulation
- **Validation**: Automatic JSON extraction and validation
- **JSON Schema Generation**: Utilities to create schemas

## Core Concepts

### Generatable Interface

Types that can be generated as structured output must implement the `Generatable` interface:

```typescript
interface Generatable {
  readonly jsonSchema: string;
  readonly generationHints?: GenerationHints;
}
```

### Generation Hints

Optional hints to customize generation behavior:

```typescript
interface GenerationHints {
  temperature?: number;      // Controls randomness (0.0-1.0)
  maxTokens?: number;        // Maximum tokens to generate
  systemRole?: string;       // System prompt for guidance
}
```

## Basic Usage

### 1. Define Your Output Type

```typescript
import {
  createGeneratable,
  createObjectSchema,
  stringProperty,
  numberProperty,
  arrayProperty,
} from '@runanywhere/react-native';

// Define the schema for a Person
const personSchema = createObjectSchema(
  {
    name: stringProperty('Full name of the person'),
    age: numberProperty('Age in years'),
    occupation: stringProperty('Current occupation'),
    hobbies: arrayProperty(stringProperty(), 'List of hobbies'),
  },
  ['name', 'age'], // required fields
  {
    title: 'Person',
    description: 'A person with their details',
  }
);

// Create a Generatable type
const PersonType = createGeneratable(personSchema, {
  temperature: 0.7,
  maxTokens: 500,
});
```

### 2. Generate Structured Output (Non-Streaming)

```typescript
import { StructuredOutputGenerationService } from '@runanywhere/react-native';

// Create the service with a handler
const handler = new StructuredOutputHandler();
const service = new StructuredOutputGenerationService(handler);

// Generate
const person = await service.generateStructured<{
  name: string;
  age: number;
  occupation: string;
  hobbies: string[];
}>(
  PersonType,
  'Tell me about a software engineer in their 30s',
  null, // options
  llmCapability
);

console.log(person.name); // "Alice Johnson"
console.log(person.age); // 32
```

### 3. Generate with Streaming

```typescript
import { StructuredOutputGenerationService } from '@runanywhere/react-native';

const result = service.generateStructuredStream<Person>(
  PersonType,
  'Tell me about a software engineer',
  null,
  async (prompt, options) => {
    // Your stream generator function
    return await llmCapability.generateStream(prompt, options);
  }
);

// Consume the token stream
for await (const token of result.tokenStream) {
  console.log(`Token ${token.tokenIndex}: ${token.text}`);
  // Real-time UI updates
}

// Get the final parsed result
const person = await result.result;
console.log('Final person:', person);
```

## Advanced Examples

### Complex Nested Schema

```typescript
import {
  createObjectSchema,
  stringProperty,
  numberProperty,
  arrayProperty,
  objectProperty,
  enumProperty,
} from '@runanywhere/react-native';

const companySchema = createObjectSchema(
  {
    name: stringProperty('Company name'),
    founded: numberProperty('Year founded'),
    size: enumProperty(['startup', 'small', 'medium', 'large'], 'Company size'),
    employees: arrayProperty(
      objectProperty(
        {
          name: stringProperty('Employee name'),
          role: stringProperty('Job role'),
          department: stringProperty('Department'),
        },
        ['name', 'role']
      ),
      'List of employees'
    ),
  },
  ['name', 'founded'],
  {
    title: 'Company',
    description: 'A company with employees',
  }
);

const CompanyType = createGeneratable(companySchema);
```

### Custom Generation Hints

```typescript
import { createGeneratable, createGenerationHints } from '@runanywhere/react-native';

const hints = createGenerationHints(
  0.3, // Low temperature for more deterministic output
  1000, // Max tokens
  'You are a professional data formatter' // System role
);

const StrictPersonType = createGeneratable(personSchema, hints);
```

### Error Handling

```typescript
import { StructuredOutputError, StructuredOutputErrorType } from '@runanywhere/react-native';

try {
  const person = await service.generateStructured<Person>(
    PersonType,
    'Tell me about someone',
    null,
    llmCapability
  );
} catch (error) {
  if (error instanceof StructuredOutputError) {
    switch (error.type) {
      case StructuredOutputErrorType.InvalidJSON:
        console.error('LLM did not generate valid JSON');
        break;
      case StructuredOutputErrorType.ExtractionFailed:
        console.error('Could not extract JSON from response');
        break;
      case StructuredOutputErrorType.ValidationFailed:
        console.error('JSON does not match schema');
        break;
    }
  }
}
```

## Architecture

### Components

1. **Generatable.ts**: Core protocol and configuration
2. **GenerationHints.ts**: Hint system for customization
3. **StreamToken.ts**: Token types for streaming
4. **StreamAccumulator.ts**: Accumulates tokens during streaming
5. **StructuredOutputGenerationService.ts**: Main service for generation
6. **StructuredOutputValidation.ts**: Validation types and errors
7. **JSONSchemaGenerator.ts**: Schema generation utilities

### Flow

```
User Request
     ↓
Define Generatable Type (with schema)
     ↓
StructuredOutputGenerationService
     ↓
System Prompt Injection (with schema)
     ↓
LLM Generation (streaming or non-streaming)
     ↓
JSON Extraction & Validation
     ↓
Parsed & Typed Result
```

## Best Practices

1. **Define Clear Schemas**: Use descriptive property descriptions
2. **Mark Required Fields**: Specify which fields are mandatory
3. **Use Appropriate Hints**: Adjust temperature and max tokens for your use case
4. **Handle Errors**: Always wrap generation in try-catch
5. **Stream for UX**: Use streaming for real-time feedback
6. **Validate Types**: Use TypeScript types that match your schema

## Comparison with iOS

This implementation closely matches the iOS SDK:

| Feature | iOS | React Native |
|---------|-----|--------------|
| Generatable Protocol | ✅ `Generatable` | ✅ `Generatable` interface |
| Generation Hints | ✅ `GenerationHints` | ✅ `GenerationHints` |
| Streaming | ✅ `AsyncSequence` | ✅ `AsyncIterable` |
| Stream Accumulator | ✅ Actor | ✅ Class with Promises |
| Validation | ✅ `StructuredOutputValidation` | ✅ `StructuredOutputValidation` |
| Error Types | ✅ Enum | ✅ Class with type property |
| JSON Schema | ✅ Swift macros | ✅ Utility functions |

## TypeScript-Specific Features

### Type Safety

```typescript
// TypeScript infers the return type from the generic
const person = await service.generateStructured<Person>(...);
// person is typed as Person, not any
```

### Async Iteration

```typescript
// Native async iteration support
for await (const token of result.tokenStream) {
  // Process each token
}
```

### JSON Schema Builders

```typescript
// Type-safe schema builders
const schema = createObjectSchema({
  name: stringProperty('Name'),
  age: numberProperty('Age'),
});
```

## References

- iOS Implementation: `sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/`
- JSON Schema Spec: [json-schema.org](https://json-schema.org/)
