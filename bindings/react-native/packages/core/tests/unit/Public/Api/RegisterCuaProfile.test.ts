/**
 * IDL round-trip + register-mapping coverage for `cuaProfile`
 * (PR #605 review issue 9): `ModelRegistration.cuaProfile` must forward into
 * `RegisterModelFromUrlRequest` / `RegisterMultiFileModelRequest`, and the
 * field must round-trip through proto encode/decode unchanged.
 */

import {
  RegisterModelFromUrlRequest,
  RegisterMultiFileModelRequest,
  InferenceFramework,
  ModelFileRole,
  ModelInfo,
  ModelInfoMetadata,
  ModelSource,
} from '@runanywhere/proto-ts/model_types';

describe('cua_profile IDL round-trip', () => {
  it('RegisterModelFromUrlRequest preserves cuaProfile through encode/decode', () => {
    const request = RegisterModelFromUrlRequest.fromPartial({
      url: 'https://example.com/fara.gguf',
      name: 'Fara1.5',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      cuaProfile: 'fara',
    });
    const decoded = RegisterModelFromUrlRequest.decode(
      RegisterModelFromUrlRequest.encode(request).finish()
    );
    expect(decoded.cuaProfile).toBe('fara');
  });

  it('RegisterModelFromUrlRequest omits cuaProfile when unset', () => {
    const request = RegisterModelFromUrlRequest.fromPartial({
      url: 'https://example.com/model.gguf',
      name: 'Some Model',
    });
    const decoded = RegisterModelFromUrlRequest.decode(
      RegisterModelFromUrlRequest.encode(request).finish()
    );
    expect(decoded.cuaProfile).toBeUndefined();
  });

  it('RegisterMultiFileModelRequest preserves cuaProfile through encode/decode', () => {
    const request = RegisterMultiFileModelRequest.fromPartial({
      id: 'fara1.5-4b-q4_k_m',
      name: 'Fara1.5 4B',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      // `ModelFileDescriptor.isRequired` was renamed `isOptional`, with
      // INVERTED polarity (required=true means optional=false) — both
      // files here are required, so isOptional is false.
      files: [
        {
          url: 'https://example.com/fara.gguf',
          filename: 'fara.gguf',
          isOptional: false,
          role: ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL,
        },
        {
          url: 'https://example.com/mmproj-fara.gguf',
          filename: 'mmproj-fara.gguf',
          isOptional: false,
          role: ModelFileRole.MODEL_FILE_ROLE_COMPANION,
        },
      ],
      cuaProfile: 'fara',
    });
    const decoded = RegisterMultiFileModelRequest.decode(
      RegisterMultiFileModelRequest.encode(request).finish()
    );
    expect(decoded.cuaProfile).toBe('fara');
    expect(decoded.files).toHaveLength(2);
  });

  it('preserves registration metadata for multi-file requests', () => {
    const request = RegisterMultiFileModelRequest.fromPartial({
      id: 'metadata-bundle',
      name: 'Metadata Bundle',
      framework: InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
      downloadSizeBytes: 1234,
      contextLength: 4096,
      source: ModelSource.MODEL_SOURCE_LOCAL,
      description: 'Multi-file metadata fixture',
    });
    const decoded = RegisterMultiFileModelRequest.decode(
      RegisterMultiFileModelRequest.encode(request).finish()
    );
    expect(decoded).toMatchObject({
      downloadSizeBytes: 1234,
      contextLength: 4096,
      source: ModelSource.MODEL_SOURCE_LOCAL,
      description: 'Multi-file metadata fixture',
    });
  });

  it('preserves registration metadata for archive ModelInfo', () => {
    const archive = ModelInfo.fromPartial({
      id: 'metadata-archive',
      name: 'Metadata Archive',
      downloadSizeBytes: 5678,
      contextLength: 8192,
      source: ModelSource.MODEL_SOURCE_BUILT_IN,
      metadata: ModelInfoMetadata.fromPartial({
        description: 'Archive metadata fixture',
      }),
    });
    const decoded = ModelInfo.decode(ModelInfo.encode(archive).finish());
    expect(decoded).toMatchObject({
      downloadSizeBytes: 5678,
      contextLength: 8192,
      source: ModelSource.MODEL_SOURCE_BUILT_IN,
      metadata: { description: 'Archive metadata fixture' },
    });
  });
});
