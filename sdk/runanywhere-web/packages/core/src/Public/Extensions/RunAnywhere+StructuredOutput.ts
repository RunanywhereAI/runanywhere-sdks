/**
 * RunAnywhere+StructuredOutput.ts
 *
 * Structured output namespace — mirrors Swift's `RunAnywhere+StructuredOutput.swift`.
 * Provides schema-driven JSON generation via `RunAnywhere.structuredOutput.*`.
 */

import type { LLMGenerationOptions } from '@runanywhere/proto-ts/llm_options';
import {
  StructuredOutputMode,
  StructuredOutputOptions as StructuredOutputOptionsMessage,
  StructuredOutputPromptResult as StructuredOutputPromptResultMessage,
  StructuredOutputRequest as StructuredOutputRequestMessage,
  StructuredOutputStreamEventKind,
  StructuredOutputValidation as StructuredOutputValidationMessage,
  StructuredOutputValidationRequest as StructuredOutputValidationRequestMessage,
  type StructuredOutputOptions,
  type StructuredOutputPromptResult,
  type StructuredOutputRequest,
  type StructuredOutputResult,
  type StructuredOutputValidation,
  type StructuredOutputValidationRequest,
} from '@runanywhere/proto-ts/structured_output';
import { SDKException } from '../../Foundation/SDKException';
import { SDKLogger } from '../../Foundation/SDKLogger';
import { ProtoWasmBridge } from '../../runtime/ProtoWasm';
import {
  getModuleForCapability,
  type EmscriptenRunanywhereModule,
} from '../../runtime/EmscriptenModule';
import { generateStructuredStream, type JSONSchemaDescriptor } from './RunAnywhere+TextGeneration';

export type {
  StructuredOutputOptions,
  StructuredOutputPromptResult,
  StructuredOutputRequest,
  StructuredOutputResult,
  StructuredOutputValidation,
  StructuredOutputValidationRequest,
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
  | 'strictMode'
  | 'typeName'
  | 'name'
  | 'mode'
  | 'regexPattern'
  | 'grammar'
  | 'repairJson'
  | 'maxRetries'
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
  const { parse: _parse, ...serializableOptions } = (
    options as StructuredOutputSchema & Partial<StructuredOutputOptions>
  );
  return StructuredOutputOptionsMessage.fromPartial({
    ...serializableOptions,
    includeSchemaInPrompt: options.includeSchemaInPrompt ?? true,
    mode: options.mode ?? StructuredOutputMode.STRUCTURED_OUTPUT_MODE_JSON_SCHEMA,
    repairJson: options.repairJson ?? false,
    maxRetries: options.maxRetries ?? 0,
  });
}

function normalizePreparePromptRequest(
  requestOrPrompt: StructuredOutputRequest | string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputRequest {
  if (typeof requestOrPrompt !== 'string') {
    return StructuredOutputRequestMessage.fromPartial(requestOrPrompt);
  }
  return StructuredOutputRequestMessage.fromPartial({
    requestId: '',
    prompt: requestOrPrompt,
    options: options ? buildStructuredOutputOptions(options) : undefined,
    metadata: {},
  });
}

function normalizeValidationRequest(
  requestOrText: StructuredOutputValidationRequest | string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputValidationRequest {
  if (typeof requestOrText !== 'string') {
    return StructuredOutputValidationRequestMessage.fromPartial(requestOrText);
  }
  return StructuredOutputValidationRequestMessage.fromPartial({
    text: requestOrText,
    options: options ? buildStructuredOutputOptions(options) : undefined,
  });
}

function readStructuredOutputPrompt(
  request: StructuredOutputRequest,
): StructuredOutputPromptResult {
  const module = requireStructuredOutputModule('structuredOutput.preparePrompt', [
    '_rac_structured_output_prepare_prompt_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    StructuredOutputRequestMessage.fromPartial(request),
    StructuredOutputRequestMessage,
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
  request: StructuredOutputValidationRequest,
): StructuredOutputValidation {
  const module = requireStructuredOutputModule('structuredOutput.validate', [
    '_rac_structured_output_validate_proto',
  ]);
  const result = new ProtoWasmBridge(module, logger).withEncodedRequest(
    StructuredOutputValidationRequestMessage.fromPartial(request),
    StructuredOutputValidationRequestMessage,
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

function preparePrompt(
  request: StructuredOutputRequest,
): StructuredOutputPromptResult;
function preparePrompt(
  prompt: string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputPromptResult;
function preparePrompt(
  requestOrPrompt: StructuredOutputRequest | string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputPromptResult {
  return readStructuredOutputPrompt(
    normalizePreparePromptRequest(requestOrPrompt, options),
  );
}

function validate(
  request: StructuredOutputValidationRequest,
): StructuredOutputValidation;
function validate(
  text: string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputValidation;
function validate(
  requestOrText: StructuredOutputValidationRequest | string,
  options?: Partial<StructuredOutputOptions> | StructuredOutputSchema,
): StructuredOutputValidation {
  return readStructuredOutputValidation(
    normalizeValidationRequest(requestOrText, options),
  );
}

/**
 * Generate structured output from a prompt using a JSON schema. This is the
 * implementation behind the Swift-named flat facade verb
 * `RunAnywhere.generateStructured(...)` (mirrors
 * `RunAnywhere+StructuredOutput.swift` `generateStructured(prompt:schema:options:)`).
 *
 * Drives the token stream to completion and returns the validated result
 * carried by the terminal `.completed` event (token events are ignored here —
 * this is the non-streaming convenience wrapper).
 */
export async function generateStructured<T = unknown>(
  prompt: string,
  schema: StructuredOutputSchema<T>,
  options?: Partial<LLMGenerationOptions>,
): Promise<T> {
  let result: StructuredOutputResult | undefined;
  for await (const event of generateStructuredStream(prompt, schema, options)) {
    if (
      event.kind === StructuredOutputStreamEventKind.STRUCTURED_OUTPUT_STREAM_EVENT_KIND_COMPLETED
      && event.result
    ) {
      result = event.result;
    }
  }
  // Swift parity: RunAnywhere+StructuredOutput.swift:149 throws `.processingFailed`.
  if (!result) {
    throw SDKException.processingFailed('Structured output did not return a result');
  }
  if (result.validation && !result.validation.isValid) {
    throw SDKException.processingFailed(
      result.validation.errorMessage ?? 'Structured output validation failed',
    );
  }
  const jsonText = new TextDecoder().decode(result.parsedJson);
  if (typeof schema.parse === 'function') {
    return schema.parse(jsonText);
  }
  try {
    return JSON.parse(jsonText) as T;
  } catch (error) {
    throw SDKException.processingFailed(
      `Structured output deserialization failed: ${(error as Error).message}`,
    );
  }
}

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
