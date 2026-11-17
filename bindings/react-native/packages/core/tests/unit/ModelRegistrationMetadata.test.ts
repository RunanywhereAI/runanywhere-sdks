/** Registration metadata must survive encoding at the native bridge boundary. */
import {
  ArchiveStructure,
  InferenceFramework,
  ModelCategory,
  ModelFileRole,
  ModelInfo,
  ModelSource,
  RegisterMultiFileModelRequest,
} from '@runanywhere/proto-ts/model_types';
import { requireNativeModule } from '../../src/native';
import { bytesToArrayBuffer } from '../../src/services/ProtoBytes';
import {
  registerArchiveModel,
  registerMultiFileModel,
} from '../../src/Public/Extensions/Models/RunAnywhere+ModelRegistry';

jest.mock('../../src/native', () => {
  const native = {
    registerMultiFileModelProto: jest.fn(),
    registerModelProto: jest.fn(),
    inferModelFileRole: jest.fn(),
  };
  return {
    requireNativeModule: () => native,
    isNativeModuleAvailable: () => true,
  };
});
jest.mock('../../src/Foundation/Initialization/InitializedGuard', () => ({
  requireInitialized: jest.fn(),
  isSDKInitialized: () => true,
}));
jest.mock('../../src/Foundation/Initialization/ServicesReadyGuard', () => ({
  ensureServicesReady: jest.fn(),
  ensureServicesReadyOrIgnore: jest.fn(),
}));

const native = jest.mocked(requireNativeModule());
const identity = {
  id: 'metadata-regression',
  name: 'Metadata regression',
  framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
  modality: ModelCategory.MODEL_CATEGORY_LANGUAGE,
};
const metadata = {
  memoryRequirement: 2_000_000,
  downloadSize: 1_000_000,
  contextLength: 4096,
  source: ModelSource.MODEL_SOURCE_LOCAL,
  description: 'Caller supplied model metadata',
  supportsThinking: true,
  supportsLora: true,
};
const files = [
  {
    url: 'https://example.com/model.gguf',
    filename: 'model.gguf',
    isRequired: true,
    role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
  },
];

beforeEach(() => {
  jest.clearAllMocks();
  native.registerModelProto.mockResolvedValue(true);
  native.registerMultiFileModelProto.mockResolvedValue(
    bytesToArrayBuffer(
      ModelInfo.encode(
        ModelInfo.fromPartial({
          id: identity.id,
          name: identity.name,
          framework: identity.framework,
          category: identity.modality,
        })
      ).finish()
    )
  );
});

describe('registration metadata', () => {
  it('encodes all multi-file metadata into the actual proto request', async () => {
    await registerMultiFileModel({ ...identity, ...metadata, files });
    const [buffer] = native.registerMultiFileModelProto.mock.calls[0]!;
    const request = RegisterMultiFileModelRequest.decode(
      new Uint8Array(buffer)
    );
    expect(request).toMatchObject({
      memoryRequiredBytes: metadata.memoryRequirement,
      downloadSizeBytes: metadata.downloadSize,
      contextLength: metadata.contextLength,
      source: metadata.source,
      description: metadata.description,
      supportsThinking: true,
      supportsLora: true,
      files: [{ role: files[0]!.role, isOptional: false }],
    });
  });

  it('preserves explicitly false multi-file capability flags', async () => {
    await registerMultiFileModel({
      ...identity,
      files,
      supportsThinking: false,
      supportsLora: false,
    });
    const [buffer] = native.registerMultiFileModelProto.mock.calls[0]!;
    const request = RegisterMultiFileModelRequest.decode(
      new Uint8Array(buffer)
    );
    expect(request.supportsThinking).toBe(false);
    expect(request.supportsLora).toBe(false);
  });

  it('leaves omitted multi-file metadata unset', async () => {
    await registerMultiFileModel({ ...identity, files });
    const [buffer] = native.registerMultiFileModelProto.mock.calls[0]!;
    const request = RegisterMultiFileModelRequest.decode(
      new Uint8Array(buffer)
    );
    expect(request.contextLength).toBeUndefined();
    expect(request.source).toBeUndefined();
    expect(request.description).toBeUndefined();
    expect(request.supportsThinking).toBeUndefined();
    expect(request.supportsLora).toBeUndefined();
  });

  it('encodes metadata on an explicitly laid out archive', async () => {
    const registered = await registerArchiveModel({
      ...identity,
      ...metadata,
      url: 'https://example.com/model.zip',
      structure: ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
    });
    const [buffer] = native.registerModelProto.mock.calls[0]!;
    const model = ModelInfo.decode(new Uint8Array(buffer));
    expect(model).toMatchObject({
      memoryRequiredBytes: metadata.memoryRequirement,
      downloadSizeBytes: metadata.downloadSize,
      contextLength: metadata.contextLength,
      source: metadata.source,
      metadata: { description: metadata.description },
      supportsThinking: true,
      supportsLora: true,
    });
    expect(registered).toEqual(model);
  });

  it('keeps remote as the archive source when none is supplied', async () => {
    const model = await registerArchiveModel({
      ...identity,
      url: 'https://example.com/model.zip',
      structure: ArchiveStructure.ARCHIVE_STRUCTURE_DIRECTORY_BASED,
    });
    expect(model.source).toBe(ModelSource.MODEL_SOURCE_REMOTE);
  });
});
