/**
 * JSONSchemaGenerator.ts
 *
 * Utilities for generating JSON schemas from TypeScript types
 *
 * Note: This is a simplified version. In a full implementation,
 * you would use a library like ts-json-schema-generator or
 * implement compile-time schema generation.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Features/LLM/StructuredOutput/Generatable.swift
 */

/**
 * Schema property definition
 */
export interface SchemaProperty {
  type: 'string' | 'number' | 'boolean' | 'object' | 'array' | 'null';
  description?: string;
  items?: SchemaProperty;
  properties?: Record<string, SchemaProperty>;
  required?: string[];
  enum?: string[];
  format?: string;
}

/**
 * JSON Schema definition
 */
export interface JSONSchema {
  $schema?: string;
  type: 'object' | 'array';
  title?: string;
  description?: string;
  properties?: Record<string, SchemaProperty>;
  required?: string[];
  items?: SchemaProperty;
  additionalProperties?: boolean;
}

/**
 * Creates a basic JSON schema for an object
 */
export function createObjectSchema(
  properties: Record<string, SchemaProperty>,
  required: string[] = [],
  options: {
    title?: string;
    description?: string;
    additionalProperties?: boolean;
  } = {}
): string {
  const schema: JSONSchema = {
    $schema: 'http://json-schema.org/draft-07/schema#',
    type: 'object',
    properties,
    required,
    additionalProperties: options.additionalProperties ?? false,
  };

  if (options.title) {
    schema.title = options.title;
  }

  if (options.description) {
    schema.description = options.description;
  }

  return JSON.stringify(schema, null, 2);
}

/**
 * Creates a string property
 */
export function stringProperty(description?: string, format?: string): SchemaProperty {
  const prop: SchemaProperty = { type: 'string' };
  if (description) prop.description = description;
  if (format) prop.format = format;
  return prop;
}

/**
 * Creates a number property
 */
export function numberProperty(description?: string): SchemaProperty {
  const prop: SchemaProperty = { type: 'number' };
  if (description) prop.description = description;
  return prop;
}

/**
 * Creates a boolean property
 */
export function booleanProperty(description?: string): SchemaProperty {
  const prop: SchemaProperty = { type: 'boolean' };
  if (description) prop.description = description;
  return prop;
}

/**
 * Creates an array property
 */
export function arrayProperty(
  items: SchemaProperty,
  description?: string
): SchemaProperty {
  const prop: SchemaProperty = { type: 'array', items };
  if (description) prop.description = description;
  return prop;
}

/**
 * Creates an object property
 */
export function objectProperty(
  properties: Record<string, SchemaProperty>,
  required: string[] = [],
  description?: string
): SchemaProperty {
  const prop: SchemaProperty = {
    type: 'object',
    properties,
    required: required.length > 0 ? required : undefined,
  };
  if (description) prop.description = description;
  return prop;
}

/**
 * Creates an enum property
 */
export function enumProperty(
  values: string[],
  description?: string
): SchemaProperty {
  const prop: SchemaProperty = { type: 'string', enum: values };
  if (description) prop.description = description;
  return prop;
}

/**
 * Example usage:
 *
 * ```typescript
 * const userSchema = createObjectSchema(
 *   {
 *     name: stringProperty('User name'),
 *     age: numberProperty('User age'),
 *     email: stringProperty('User email', 'email'),
 *     isActive: booleanProperty('Whether user is active'),
 *     tags: arrayProperty(stringProperty(), 'User tags'),
 *     role: enumProperty(['admin', 'user', 'guest'], 'User role'),
 *   },
 *   ['name', 'email'], // required fields
 *   {
 *     title: 'User',
 *     description: 'A user object',
 *   }
 * );
 * ```
 */
