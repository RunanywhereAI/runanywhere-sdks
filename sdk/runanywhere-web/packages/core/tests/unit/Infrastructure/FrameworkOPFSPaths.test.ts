import { describe, expect, it } from 'vitest';
import { ModelArtifactType } from '@runanywhere/proto-ts/model_types';
import { isExtractedDirectoryArtifact } from '../../../src/Infrastructure/FrameworkOPFSPaths.js';

describe('isExtractedDirectoryArtifact', () => {
  it('treats tar.gz archive artifact types as extracted directories', () => {
    expect(isExtractedDirectoryArtifact({
      id: 'sherpa-onnx-whisper-tiny.en',
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_TAR_GZ_ARCHIVE,
      downloadUrl: 'https://example.test/model.tar.gz',
    } as never)).toBe(true);
  });

  it('treats archive download URLs as extracted directories when artifactType is missing', () => {
    expect(isExtractedDirectoryArtifact({
      id: 'vits-piper',
      downloadUrl: 'https://example.test/vits-piper.tar.gz',
    } as never)).toBe(true);
  });

  it('does not treat single-file models as extracted directories', () => {
    expect(isExtractedDirectoryArtifact({
      id: 'silero-vad',
      artifactType: ModelArtifactType.MODEL_ARTIFACT_TYPE_SINGLE_FILE,
      downloadUrl: 'https://example.test/silero_vad.onnx',
    } as never)).toBe(false);
  });
});
