/**
 * Type-level tests for @runanywhere/web public API.
 * Run with: npx tsd
 *
 * Rewritten against the v3 Swift-shaped public surface
 * (`Public/API/RunAnywhere.ts`): the v2 proto-shaped verbs this file used
 * to exercise (`DownloadStage`, `LoRAApplyRequest`, `ToolParameterType`,
 * `RunAnywhere.lora.catalog.markDownloadCompleted`, ...) were either
 * deleted outright by the API realignment or never were part of the public
 * `@runanywhere/web` root export in the first place -- they lived only on
 * internal proto-ts modules or Web-only extension namespaces, not on
 * `RunAnywhere` itself.
 */
import { expectNotAssignable, expectType } from 'tsd';
import {
  RunAnywhere,
  SDKException,
  ProtoErrorCode,
  isSDKException,
  InferenceFramework,
  ModelCategory,
  ModelFormat,
  formatFramework,
  type Environment,
  type InitializeOptions,
  type ChatMessage,
  type ChatRole,
  type LlmOptions,
  type LoraState,
  type AppliedAdapter,
  type ToolDefinition,
} from '@runanywhere/web';

// initialize options must accept the v3 string-union environment, not the
// proto SDKEnvironment enum directly (Environment = 'production' | 'development').
type InitOptions = Parameters<(typeof RunAnywhere)['initialize']>[0];
expectType<InitOptions>({} as InitializeOptions | undefined);
const opts: InitOptions = {
  environment: 'development',
};
expectType<Promise<void>>(RunAnywhere.initialize(opts));
expectNotAssignable<Environment>('staging');
expectNotAssignable<InitOptions>({
  webgpuWasmUrl: 'https://example.com/racommons-llamacpp-webgpu.js',
});

// LLM generation options can be supplied partially by public convenience calls.
const genOpts: LlmOptions = { temperature: 0.8 };
expectType<number | undefined>(genOpts.temperature);

// isSDKException must be a type guard.
const e: unknown = new SDKException(-ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED, 'test');
if (isSDKException(e)) {
  // `.code` is the positive proto ErrorCode (Swift parity); `.cAbiCode` is the
  // signed rac_result_t integer.
  expectType<ProtoErrorCode>(e.code);
  const cAbiCode: number = e.cAbiCode;
  expectType<number>(cAbiCode);
}

// ChatMessage is the Web-local, string-role convenience shape (Public/API/Inputs.ts),
// not the generated proto ChatMessage — role is a string union, not MessageRole.
const role: ChatRole = 'user';
const msg: ChatMessage = {
  role,
  content: 'Hello',
};
expectType<ChatRole>(msg.role);
expectNotAssignable<ChatRole>('narrator');

// Generated enums referenced by public option/result fields are re-exported directly.
expectType<InferenceFramework>(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP);
expectType<ModelCategory>(ModelCategory.MODEL_CATEGORY_LANGUAGE);
expectType<ModelFormat>(ModelFormat.MODEL_FORMAT_GGUF);
expectType<string>(formatFramework(InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP));

// RunAnywhere.lora is the flat Swift-shaped surface: apply(adapterId, scale?),
// remove(adapterId | null), removeAll(), list(). It has no `catalog`
// sub-namespace and no request/result proto types — those live on the
// Web-only `RunAnywhere+LoRA.ts` extension, not the cross-SDK v3 root.
expectType<(adapterId: string, scale?: number) => Promise<void>>(RunAnywhere.lora.apply);
expectType<(adapterId: string | null) => Promise<void>>(RunAnywhere.lora.remove);
expectType<() => Promise<void>>(RunAnywhere.lora.removeAll);
expectType<Promise<LoraState>>(RunAnywhere.lora.list());

const applied: AppliedAdapter = { id: 'style', scale: 0.75 };
expectType<string>(applied.id);
expectType<number>(applied.scale);

// `ToolDefinition` is re-exported straight from the generated proto module;
// `parameters` is a single JSON-Schema string now, not a structured list
// (idl/tool_calling.proto — ToolParameterType was deleted outright).
const toolDefinition: ToolDefinition = {
  name: 'get_weather',
  description: 'Get weather',
  parameters: JSON.stringify({
    type: 'object',
    properties: { location: { type: 'string', description: 'City' } },
    required: ['location'],
  }),
};
expectType<string>(toolDefinition.parameters);
