/**
 * Type-level tests for @runanywhere/web public API.
 * Run with: npx tsd
 */
import { expectType } from 'tsd';
import {
  RunAnywhere,
  SDKEnvironment,
  SDKError,
  SDKErrorCode,
  isSDKError,
  DownloadStage,
  type GenerateOptions,
  type ChatMessage,
  type ModelDescriptor,
  type DownloadProgress,
  type IRunAnywhere,
} from '../index';

// InitializeOptions (SDKInitOptions) must accept environment
type InitOptions = Parameters<(typeof RunAnywhere)['initialize']>[0];
const opts: InitOptions = {
  environment: SDKEnvironment.Development,
};
expectType<Promise<void>>(RunAnywhere.initialize(opts));

// GenerateOptions.onToken must be optional
const genOpts: GenerateOptions = { temperature: 0.8 };
expectType<number | undefined>(genOpts.temperature);

// isSDKError must be a type guard
const e: unknown = new SDKError(SDKErrorCode.NotInitialized, 'test');
if (isSDKError(e)) {
  const code: SDKErrorCode = e.code;
  expectType<SDKErrorCode>(code);
}

// ChatMessage role must be a union literal
const msg: ChatMessage = { role: 'user', content: 'Hello' };
expectType<'user' | 'assistant' | 'system'>(msg.role);

// role must not accept arbitrary strings
// @ts-expect-error role must not accept 'admin'
// eslint-disable-next-line @typescript-eslint/no-unused-vars -- intentional for type test
const bad: ChatMessage = { role: 'admin', content: 'x' };

// ModelDescriptor and DownloadProgress are exported
const desc: ModelDescriptor = {
  id: 'm1',
  name: 'Model',
  url: 'https://example.com/m.gguf',
  memoryRequirement: 1e9,
};
expectType<string>(desc.id);

const prog: DownloadProgress = {
  modelId: 'm1',
  stage: DownloadStage.Downloading,
  progress: 0.5,
  bytesDownloaded: 100,
  totalBytes: 200,
};
expectType<number>(prog.progress);

// IRunAnywhere must be satisfied by the RunAnywhere export
const sdk: IRunAnywhere = RunAnywhere;
expectType<IRunAnywhere>(sdk);
