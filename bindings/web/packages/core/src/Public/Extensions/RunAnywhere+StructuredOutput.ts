/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output namespace — mirrors Swift's `RunAnywhere+StructuredOutput.swift`.
 * Provides schema-driven JSON generation via `RunAnywhere.structuredOutput.*`.
 *
 * idl/structured_output.proto (API-realignment so-p2) deleted the dedicated
 * `StructuredOutputRequest` / `StructuredOutputValidationRequest` messages
 * outright. `StructuredOutputParseRequest` (requestId, text, options,
 * metadata) is now the sole request envelope shared by parse/validate/
 * prepare-prompt — `text` plays the role the old `prompt` field did (mirrors
 * commons' `rac_structured_output_prepare_prompt_proto` /
 * `..._validate_proto`, `structured_output.cpp`). There is likewise no more
 * `JSONSchema`/`NamedEntity` message or `StructuredOutputStreamEvent`/
 * `StructuredOutputStreamEventKind` type — `StructuredOutputOptions.schema`
 * is a plain JSON-Schema string.
 */

import type {
  LLMGenerationOptions,
  LLMGenerationResult,
} from '@runanywhere/proto-ts/llm_options';
import {
  StructuredOutputOptions as StructuredOutputOptionsMessage,
  StructuredOutputParseRequest as StructuredOutputParseRequestMessage,
  StructuredOutputPromptResult as StructuredOutputPromptResultMessage,
  StructuredOutputValidation as StructuredOutputValidationMessage,
  type StructuredOutputOptions,
  type StructuredOutputParseRequest,
  type StructuredOutputPromptResult,
  type StructuredOutputResult,
  type StructuredOutputValidation,
} from '@runanywhere/proto-ts/structured_output';
import { SDKException } from '../../Foundation/SDKException.js';
import { SDKLogger } from '../../Foundation/SDKLogger.js';
import { ProtoWasmBridge } from '../../runtime/ProtoWasm.js';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule.js';
import {
  TextGeneration,
  generateStructuredStream,
  type JSONSchemaDescriptor,
  type StructuredOutputStreamEvent,
} from './RunAnywhere+TextGeneration.js';

export type {
  StructuredOutputOptions,
  StructuredOutputParseRequest,
  StructuredOutputPromptResult,
  StructuredOutputResult,
  StructuredOutputValidation,
};

const logger = new SDKLogger('StructuredOutput');

type StructuredOutputExport =
  | '_rac_structured_output_prepare_prompt_proto'
  | '_rac_structured_output_validate_proto';

// Schema accepted by the structured-output verbs. Composed from the canonical
// `JSONSchemaDescriptor` (jsonSchema + parse) so there is a single source of
// truth for the descriptor shape; the typed `parse` override narrows the
// return type to `T` and the structured-output knobs are pulled from the
// generated `StructuredOutputOptions` message.
type StructuredOutputSchema<T = unknown> = Omit<JSONSchemaDescriptor, 'parse'> & {
  parse?: (text: string) => T;
} & Partial<Pick<
  StructuredOutputOptions,
  | 'includeSchemaInPrompt'
  | 'schema'
  | 'grammar'
  | 'regex'
>>;

function missingStructuredOutputExports(
  module: EmscriptenRunanywhereModule,
  names: StructuredOutputExport[],
): string[] {
  return names.filter((name) => typeof module[name] !== 'function');
}

function requireStructuredOutputModule(
  feature: string,
  names: StructuredOutputExport[],
): EmscriptenRunanywhereModule {
  const module = getModuleForCapability('structured-output');
  if (!module) {
    throw SDKException.backendNotAvailable(
      feature,
      'No backend that exports rac_structured_output_*_proto is registered. ' +
      'Call LlamaCPP.register() (or another structured-output-providing backend) first.',
    );
  }

  const missing = [
    ...missingStructuredOutputExports(module, names),
    ...new ProtoWasmBridge(module, logger).missingProtoBufferExports(),
  ];
  if (missing.length > 0) {
    throw SDKException.backendNotAvailable(
      feature,
      `This Web WASM build does not export ${missing.join(', ')}.`,
    );
  }
  return module;
}

function buildStructuredOutputOptions(
  options: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputOptions {
  const { parse: _parse, jsonSchema, ...serializableOptions } = (
    options as StructuredOutputSchema & Partial<StructuredOutputOptions>
  );
  return StructuredOutputOptionsMessage.fromPartial({
    ...serializableOptions,
    schema: serializableOptions.schema ?? jsonSchema,
    includeSchemaInPrompt: options.includeSchemaInPrompt ?? true,
  });
}

function normalizeParseRequest(
  requestOrText: StructuredOutputParseRequest | string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputParseRequest {
  if (typeof requestOrText !== 'string') {
    return StructuredOutputParseRequestMessage.fromPartial(requestOrText);
  }
  return StructuredOutputParseRequestMessage.fromPartial({
    requestId: '',
    text: requestOrText,
    options: options ? buildStructuredOutputOptions(options) : undefined,
    metadata: {},
  });
}

function readStructuredOutputPrompt(
  request: StructuredOutputParseRequest,
): StructuredOutputPromptResult {
  const module = requireStructuredOutputModule('structuredOutput.preparePrompt', [
    '_rac_structured_output_prepare_prompt_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    request,
    StructuredOutputParseRequestMessage,
    StructuredOutputPromptResultMessage,
    (requestPtr, requestSize, outResult) => (
      module._rac_structured_output_prepare_prompt_proto!(
        requestPtr,
        requestSize,
        outResult,
      )
    ),
    'rac_structured_output_prepare_prompt_proto',
  );
  if (!result) {
    throw SDKException.backendNotAvailable(
      'structuredOutput.preparePrompt',
      'rac_structured_output_prepare_prompt_proto returned no StructuredOutputPromptResult bytes.',
    );
  }
  return result;
}

function readStructuredOutputValidation(
  request: StructuredOutputParseRequest,
): StructuredOutputValidation {
  const module = requireStructuredOutputModule('structuredOutput.validate', [
    '_rac_structured_output_validate_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    request,
    StructuredOutputParseRequestMessage,
    StructuredOutputValidationMessage,
    (requestPtr, requestSize, outResult) => (
      module._rac_structured_output_validate_proto!(requestPtr, requestSize, outResult)
    ),
    'rac_structured_output_validate_proto',
  );
  if (!result) {
    throw SDKException.backendNotAvailable(
      'structuredOutput.validate',
      'rac_structured_output_validate_proto returned no StructuredOutputValidation bytes.',
    );
  }
  return result;
}

// ---------------------------------------------------------------------------
// Structured output proto helpers — Swift parity: StructuredOutputProto+Helpers.swift
// ---------------------------------------------------------------------------

/**
 * Whether the structured-output result validated successfully.
 * Swift parity: `RAStructuredOutputResult.success` (StructuredOutputProto+Helpers.swift:76).
 */
export function structuredOutputResultSuccess(result: StructuredOutputResult): boolean {
  return result.validation?.isValid ?? false;
}

function preparePrompt(
  request: StructuredOutputParseRequest,
): StructuredOutputPromptResult;
function preparePrompt(
  text: string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputPromptResult;
function preparePrompt(
  requestOrText: StructuredOutputParseRequest | string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputPromptResult {
  return readStructuredOutputPrompt(
    normalizeParseRequest(requestOrText, options),
  );
}

function validate(
  request: StructuredOutputParseRequest,
): StructuredOutputValidation;
function validate(
  text: string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputValidation;
function validate(
  requestOrText: StructuredOutputParseRequest | string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputValidation {
  return readStructuredOutputValidation(
    normalizeParseRequest(requestOrText, options),
  );
}

/**
 * Generate structured output from a prompt using a JSON schema. This is the
 * implementation behind the Swift-named flat facade verb
 * `RunAnywhere.generateStructured(...)` (mirrors
 * `RunAnywhere+StructuredOutput.swift` `generateStructured(prompt:schema:options:)`).
 *
 * Drives the token stream to completion and returns the
 * `StructuredOutputResult` carried by the terminal `.completed` event —
 * Swift parity: the caller inspects `result.validation` rather than the SDK
 * throwing on validation failure.
 */
export async function generateStructured(
  prompt: string,
  schema: StructuredOutputSchema,
  options?: Partial<LLMGenerationOptions>,
): Promise<StructuredOutputResult> {
  let result: StructuredOutputResult | undefined;
  for await (const event of generateStructuredStream(prompt, schema, options)) {
    if (event.kind === 'completed' && event.result) {
      result = event.result;
    }
  }
  // Swift parity: RunAnywhere+StructuredOutput.swift:149 throws `.processingFailed`.
  if (!result) {
    throw SDKException.processingFailed('Structured output did not return a result');
  }
  return result;
}

/**
 * Generate raw text via the LLM with a structured-output configuration
 * applied to the request. Returns the raw `LLMGenerationResult`; callers can
 * pass `result.text` to `extractStructuredOutput(text, schema)` for parsing.
 *
 * Mirrors Swift `generateWithStructuredOutput(prompt:structuredOutput:options:)`
 * (RunAnywhere+StructuredOutput.swift:139-156): when
 * `includeSchemaInPrompt` is set, the prompt is prepared through the commons
 * structured-output primitive and any system prompt it produces overrides the
 * caller's; the structured-output options ride the generate request
 * (`LLMGenerationOptions.structuredOutput`).
 */
export async function generateWithStructuredOutput(
  prompt: string,
  structuredOutput: Partial<StructuredOutputOptions>,
  options?: Partial<LLMGenerationOptions>,
): Promise<LLMGenerationResult> {
  const normalizedStructured = buildStructuredOutputOptions(structuredOutput);
  let systemPrompt = options?.systemPrompt;
  if (normalizedStructured.includeSchemaInPrompt) {
    const prep = preparePrompt(prompt, normalizedStructured);
    if (prep.error) {
      // Swift parity: RunAnywhere+StructuredOutput.swift:149.
      throw new SDKException(prep.error);
    }
    if (prep.systemPrompt !== undefined) {
      systemPrompt = prep.systemPrompt;
    }
  }
  return TextGeneration.generate({
    ...options,
    ...(systemPrompt !== undefined ? { systemPrompt } : {}),
    structuredOutput: normalizedStructured,
    prompt,
  });
}

export type { StructuredOutputStreamEvent };

/**
 * Public `RunAnywhere.structuredOutput.*` namespace — Web-only extensions
 * ONLY.
 *
 * The Swift source of truth (`RunAnywhere+StructuredOutput.swift`) has no
 * `structuredOutput` namespace; its flat verbs (`generateStructured`,
 * `generateStructuredStream`, plus `extractStructuredOutput` from
 * `RunAnywhere+TextGeneration.swift`) live directly on the `RunAnywhere`
 * facade (see RunAnywhere+FlatFacade.ts). The members below are Web-platform
 * extensions: the export probe exists because Web WASM backends register
 * asynchronously, and the proto primitives (`preparePrompt` / `validate`)
 * are exposed where Swift keeps them internal on `CppBridge.StructuredOutput`.
 */
export const StructuredOutput = {
  /** @webOnly Probe whether the active WASM build exports the structured-output proto ABI. */
  supportsProtoStructuredOutput(): boolean {
    const module = getModuleForCapability('structured-output');
    if (!module) return false;
    return missingStructuredOutputExports(module, [
      '_rac_structured_output_prepare_prompt_proto',
      '_rac_structured_output_validate_proto',
    ]).length === 0 && new ProtoWasmBridge(module, logger).hasProtoBufferExports();
  },

  /** @webOnly Raw `rac_structured_output_prepare_prompt_proto` primitive (internal CppBridge helper in Swift). */
  preparePrompt,

  /** @webOnly Raw `rac_structured_output_validate_proto` primitive (internal CppBridge helper in Swift). */
  validate,
};
