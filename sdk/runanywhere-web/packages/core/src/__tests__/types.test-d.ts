/**
 * Type-level tests for @runanywhere/web public API.
 * Run with: npx tsd
 */
import { expectType } from 'tsd';
import {
  RunAnywhere,
  SDKEnvironment,
  SDKException,
  SDKErrorCode,
  isSDKException,
  DownloadStage,
  DownloadState,
  MessageRole,
  type GenerateOptions,
  type ChatMessage,
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

// isSDKException must be a type guard
const e: unknown = new SDKException(SDKErrorCode.NotInitialized, 'test');
if (isSDKException(e)) {
  const code: SDKErrorCode = e.code;
  expectType<SDKErrorCode>(code);
}

const msg: ChatMessage = {
  id: 'm1',
  role: MessageRole.MESSAGE_ROLE_USER,
  content: 'Hello',
  timestampUs: 0,
};
expectType<MessageRole>(msg.role);

const prog: DownloadProgress = {
  modelId: 'm1',
  stage: DownloadStage.DOWNLOAD_STAGE_DOWNLOADING,
  bytesDownloaded: 100,
  totalBytes: 200,
  stageProgress: 0.5,
  overallSpeedBps: 1000,
  etaSeconds: 1,
  state: DownloadState.DOWNLOAD_STATE_DOWNLOADING,
  retryAttempt: 0,
  errorMessage: '',
};
expectType<number>(prog.stageProgress);

// IRunAnywhere must be satisfied by the RunAnywhere export
const sdk: IRunAnywhere = RunAnywhere;
expectType<IRunAnywhere>(sdk);
