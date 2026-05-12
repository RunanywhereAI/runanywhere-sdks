/**
 * Canonical model/component lifecycle extension.
 *
 * These helpers expose the stable runanywhere-commons lifecycle proto ABI
 * directly as generated proto-ts request/result types.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import {
  CurrentModelRequest,
  CurrentModelResult,
  ModelFileRole,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
import type {
  CurrentModelRequest as CurrentModelRequestMessage,
  CurrentModelResult as CurrentModelResultMessage,
  ModelFileDescriptor,
  ModelLoadRequest as ModelLoadRequestMessage,
  ModelLoadResult as ModelLoadResultMessage,
  ModelUnloadRequest as ModelUnloadRequestMessage,
  ModelUnloadResult as ModelUnloadResultMessage,
} from '@runanywhere/proto-ts/model_types';
import {
  ComponentLifecycleSnapshot,
  SDKComponent,
} from '@runanywhere/proto-ts/sdk_events';
import type {
  ComponentLifecycleSnapshot as ComponentLifecycleSnapshotMessage,
} from '@runanywhere/proto-ts/sdk_events';
import { arrayBufferToBytes, bytesToArrayBuffer } from '../../../services/ProtoBytes';

export type {
  CurrentModelRequest,
  CurrentModelResult,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
export type {
  ComponentLifecycleSnapshot,
} from '@runanywhere/proto-ts/sdk_events';

export interface LifecycleArtifactSource {
  modelId?: string;
  resolvedArtifacts: ModelFileDescriptor[];
}

export interface VLMResolvedLifecycleArtifacts {
  primaryModelPath: string;
  visionProjectorPath: string;
}

function encode<T>(
  message: T,
  codec: { encode(value: T): { finish(): Uint8Array } }
): ArrayBuffer {
  return bytesToArrayBuffer(codec.encode(message).finish());
}

function decode<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T },
  fallback: T
): T {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? fallback : codec.decode(bytes);
}

function nonEmptyPath(path?: string): string | undefined {
  const trimmed = path?.trim();
  return trimmed && trimmed.length > 0 ? trimmed : undefined;
}

export function getLifecycleResolvedArtifactPath(
  source: LifecycleArtifactSource,
  role: ModelFileRole
): string | undefined {
  const artifact = source.resolvedArtifacts.find((item) => item.role === role);
  return nonEmptyPath(artifact?.localPath);
}

export function resolveVLMArtifactsFromLifecycleResult(
  source: LifecycleArtifactSource
): VLMResolvedLifecycleArtifacts | null {
  const primaryModelPath = getLifecycleResolvedArtifactPath(
    source,
    ModelFileRole.MODEL_FILE_ROLE_PRIMARY_MODEL
  );
  const visionProjectorPath = getLifecycleResolvedArtifactPath(
    source,
    ModelFileRole.MODEL_FILE_ROLE_VISION_PROJECTOR
  );

  if (!primaryModelPath || !visionProjectorPath) {
    return null;
  }

  return { primaryModelPath, visionProjectorPath };
}

export async function loadModelLifecycle(
  request: ModelLoadRequestMessage
): Promise<ModelLoadResultMessage> {
  if (!isNativeModuleAvailable()) {
    return ModelLoadResult.fromPartial({
      success: false,
      modelId: request.modelId,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.modelLifecycleLoadProto(
    encode(request, ModelLoadRequest)
  );
  return decode(
    buffer,
    ModelLoadResult,
    ModelLoadResult.fromPartial({
      success: false,
      modelId: request.modelId,
      errorMessage: 'modelLifecycleLoadProto returned an empty result',
    })
  );
}

export async function unloadModelLifecycle(
  request: ModelUnloadRequestMessage
): Promise<ModelUnloadResultMessage> {
  if (!isNativeModuleAvailable()) {
    return ModelUnloadResult.fromPartial({
      success: false,
      errorMessage: 'Native module not available',
    });
  }

  const native = requireNativeModule();
  const buffer = await native.modelLifecycleUnloadProto(
    encode(request, ModelUnloadRequest)
  );
  return decode(
    buffer,
    ModelUnloadResult,
    ModelUnloadResult.fromPartial({
      success: false,
      errorMessage: 'modelLifecycleUnloadProto returned an empty result',
    })
  );
}

export async function getCurrentModel(
  request: CurrentModelRequestMessage = CurrentModelRequest.fromPartial({})
): Promise<CurrentModelResultMessage | null> {
  if (!isNativeModuleAvailable()) {
    return null;
  }

  const native = requireNativeModule();
  const buffer = await native.currentModelProto(
    encode(request, CurrentModelRequest)
  );
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? null : CurrentModelResult.decode(bytes);
}

export async function getComponentLifecycleSnapshot(
  component: SDKComponent
): Promise<ComponentLifecycleSnapshotMessage | null> {
  if (!isNativeModuleAvailable()) {
    return null;
  }

  const native = requireNativeModule();
  const buffer = await native.componentLifecycleSnapshotProto(component);
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0
    ? null
    : ComponentLifecycleSnapshot.decode(bytes);
}
