/**
 * Type-level tests for @runanywhere/web public API.
 * Run with: npx tsd
 */
import { expectType } from 'tsd';
import {
  RunAnywhere,
  SDKEnvironment,
  SDKException,
  ProtoErrorCode,
  isSDKException,
  DownloadStage,
  DownloadState,
  ChatMessageStatus,
  MessageRole,
  ToolParameterType,
  type LLMGenerationOptions,
  type ChatMessage,
  type DownloadProgress,
  type LoRAAdapterConfig,
  type LoRAApplyRequest,
  type LoRAApplyResult,
  type LoRARemoveRequest,
  type LoRAState,
  type LoraAdapterCatalogEntry,
  type LoraAdapterCatalogGetRequest,
  type LoraAdapterCatalogGetResult,
  type LoraAdapterCatalogListRequest,
  type LoraAdapterCatalogListResult,
  type LoraAdapterCatalogQuery,
  type LoraAdapterDownloadCompletedRequest,
  type LoraAdapterDownloadCompletedResult,
  type LoraCompatibilityResult,
  type ToolDefinition,
  type ToolValue,
} from '@runanywhere/web';

// initialize options must accept the proto-canonical environment enum.
type InitOptions = Parameters<(typeof RunAnywhere)['initialize']>[0];
const opts: InitOptions = {
  environment: SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT,
};
expectType<Promise<void>>(RunAnywhere.initialize(opts));

// LLM generation options can be supplied partially by public convenience calls.
const genOpts: Partial<LLMGenerationOptions> = { temperature: 0.8 };
expectType<number | undefined>(genOpts.temperature);

// isSDKException must be a type guard
const e: unknown = new SDKException(-ProtoErrorCode.ERROR_CODE_NOT_INITIALIZED, 'test');
if (isSDKException(e)) {
  const code: number = e.code;
  expectType<number>(code);
}

const msg: ChatMessage = {
  id: 'm1',
  role: MessageRole.MESSAGE_ROLE_USER,
  content: 'Hello',
  timestampUs: 0,
  toolCalls: [],
  status: ChatMessageStatus.CHAT_MESSAGE_STATUS_COMPLETE,
  metadata: {},
  attachments: [],
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
  taskId: 'task-1',
  currentFileIndex: 0,
  totalFiles: 1,
  storageKey: 'models/m1',
  localPath: '',
  overallProgress: 0.5,
  startedAtUnixMs: 0,
  updatedAtUnixMs: 0,
  currentFileName: 'model.gguf',
  resumeToken: '',
};
expectType<number>(prog.stageProgress);

const loraHandle = 1;
const loraConfig: LoRAAdapterConfig = {
  adapterPath: '/models/adapters/style.gguf',
  scale: 0.75,
  adapterId: 'style',
  metadata: {},
  targetModules: [],
};
const loraApplyRequest: LoRAApplyRequest = {
  requestId: 'apply-1',
  adapters: [loraConfig],
  replaceExisting: true,
};
const loraRemoveRequest: LoRARemoveRequest = {
  requestId: 'remove-1',
  adapterIds: ['style'],
  adapterPaths: [],
  clearAll: false,
};
const loraStateRequest: LoRAState = {
  loadedAdapters: [],
  hasActiveAdapters: false,
  errorCode: 0,
};
const loraCatalogEntry: LoraAdapterCatalogEntry = {
  id: 'style',
  name: 'Style',
  description: '',
  url: 'https://example.com/style.gguf',
  filename: 'style.gguf',
  compatibleModels: ['base'],
  sizeBytes: 0,
  defaultScale: 0.75,
  tags: [],
  metadata: {},
};
const loraCatalogListRequest: LoraAdapterCatalogListRequest = {
  query: { modelId: 'base', tags: [] },
  includeCounts: true,
};
const loraCatalogQuery: LoraAdapterCatalogQuery = {
  modelId: 'base',
  downloadedOnly: true,
  tags: ['style'],
};
const loraCatalogGetRequest: LoraAdapterCatalogGetRequest = {
  adapterId: 'style',
};
const loraDownloadCompletedRequest: LoraAdapterDownloadCompletedRequest = {
  adapterId: 'style',
  localPath: 'opfs://runanywhere/lora/style.gguf',
  imported: false,
  statusMessage: 'download completed',
};
expectType<boolean>(RunAnywhere.lora.supportsNative());
expectType<string[]>(RunAnywhere.lora.missingExports());
expectType<boolean>(RunAnywhere.lora.catalog.supportsNative());
expectType<string[]>(RunAnywhere.lora.catalog.missingExports());
expectType<Promise<LoRAApplyResult>>(RunAnywhere.lora.apply(loraHandle, loraApplyRequest));
expectType<Promise<LoRAState>>(RunAnywhere.lora.remove(loraHandle, loraRemoveRequest));
expectType<Promise<LoRAState>>(RunAnywhere.lora.list(loraHandle, loraStateRequest));
expectType<Promise<LoRAState>>(RunAnywhere.lora.state(loraHandle, loraStateRequest));
expectType<Promise<LoraCompatibilityResult>>(
  RunAnywhere.lora.checkCompatibility(loraHandle, loraConfig),
);
expectType<Promise<LoraAdapterCatalogEntry>>(
  RunAnywhere.lora.catalog.register(loraCatalogEntry),
);
expectType<Promise<LoraAdapterCatalogListResult>>(
  RunAnywhere.lora.catalog.list(loraCatalogListRequest),
);
expectType<Promise<LoraAdapterCatalogListResult>>(
  RunAnywhere.lora.catalog.query(loraCatalogQuery),
);
expectType<Promise<LoraAdapterCatalogGetResult>>(
  RunAnywhere.lora.catalog.get(loraCatalogGetRequest),
);
expectType<Promise<LoraAdapterDownloadCompletedResult>>(
  RunAnywhere.lora.catalog.markDownloadCompleted(loraDownloadCompletedRequest),
);

const toolValue: ToolValue = { stringValue: 'San Francisco' };
expectType<string | undefined>(toolValue.stringValue);

const toolDefinition: ToolDefinition = {
  name: 'get_weather',
  description: 'Get weather',
  parameters: [{
    name: 'location',
    type: ToolParameterType.TOOL_PARAMETER_TYPE_STRING,
    description: 'City',
    required: true,
    enumValues: [],
  }],
  metadata: {},
};
expectType<ToolParameterType>(toolDefinition.parameters[0].type);
