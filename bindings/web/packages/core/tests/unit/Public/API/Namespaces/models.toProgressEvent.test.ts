import { describe, expect, it } from 'vitest';
import { DownloadState, type DownloadProgress } from '@runanywhere/proto-ts/download_service';
import { __testing__ } from '../../../../../src/Public/API/Namespaces/models';

function progress(partial: Partial<DownloadProgress> = {}): DownloadProgress {
  return {
    modelId: 'm',
    bytesDownloaded: 0,
    totalBytes: 0,
    stageProgress: 0,
    bytesPerSecond: 0,
    state: DownloadState.DOWNLOAD_STATE_DOWNLOADING,
    retryAttempt: 0,
    taskId: 't',
    currentFileIndex: 0,
    totalFiles: 1,
    storageKey: '',
    localPath: '',
    overallProgress: 0,
    startedAtUnixMs: 0,
    updatedAtUnixMs: 0,
    currentFileName: '',
    ...partial,
  };
}

describe('toProgressEvent', () => {
  it('maps commons throughput, ETA, and overall progress onto the public event', () => {
    const event = __testing__.toProgressEvent(
      progress({
        bytesDownloaded: 4_200_000,
        totalBytes: 10_000_000,
        bytesPerSecond: 3_600_000,
        etaSeconds: 2,
        overallProgress: 0.42,
        currentFileName: 'weights.bin',
        retryAttempt: 1,
        currentFileIndex: 0,
        totalFiles: 2,
      }),
      'op-1',
      7,
    );

    expect(event).toEqual({
      type: 'progress',
      operationId: 'op-1',
      sequence: 7,
      bytesDone: 4_200_000,
      bytesTotal: 10_000_000,
      file: 'weights.bin',
      bytesPerSecond: 3_600_000,
      etaSeconds: 2,
      retryAttempt: 1,
      overallProgress: 0.42,
      currentFileIndex: 0,
      totalFiles: 2,
    });
  });

  it('leaves unknown rate, ETA, and overall progress undefined rather than zero', () => {
    const event = __testing__.toProgressEvent(
      progress({
        bytesDownloaded: 100,
        totalBytes: 0,
        bytesPerSecond: 0,
        overallProgress: 0,
      }),
      'op-2',
      1,
    );

    expect(event).toMatchObject({
      type: 'progress',
      bytesDone: 100,
      bytesTotal: 0,
      bytesPerSecond: undefined,
      etaSeconds: undefined,
      overallProgress: undefined,
    });
  });

  it('treats a negative ETA sentinel as unknown', () => {
    const event = __testing__.toProgressEvent(
      progress({ etaSeconds: -1, bytesPerSecond: 1, overallProgress: 0.1 }),
      'op-3',
      2,
    );

    expect(event).toMatchObject({
      type: 'progress',
      etaSeconds: undefined,
      bytesPerSecond: 1,
      overallProgress: 0.1,
    });
  });
});
