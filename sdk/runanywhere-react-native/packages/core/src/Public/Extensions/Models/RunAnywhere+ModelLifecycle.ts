/**
 * Canonical model/component lifecycle extension.
 *
 * These helpers expose the stable runanywhere-commons lifecycle proto ABI
 * directly as generated proto-ts request/result types.
 */

import { requireNativeModule, isNativeModuleAvailable } from '../../../native';
import { ensureServicesReadyOrIgnore } from '../../../Foundation/Initialization/ServicesReadyGuard';
import {
  CurrentModelRequest,
  CurrentModelResult,
  ModelCategory,
  ModelLoadRequest,
  ModelLoadResult,
  ModelUnloadRequest,
  ModelUnloadResult,
} from '@runanywhere/proto-ts/model_types';
import type {
  CurrentModelRequest as CurrentModelRequestMessage,
  CurrentModelResult as CurrentModelResultMessage,
  ModelInfo,
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
import { arrayBufferToBytes } from '../../../services/ProtoBytes';
import { encodeProtoMessage } from '../../../services/ProtoWire';

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

function encode<T>(
  message: T,
  codec: { encode(value: T, writer?: { finish(): Uint8Array }): { finish(): Uint8Array } }
): ArrayBuffer {
  return encodeProtoMessage(message, codec);
}

function decode<T>(
  buffer: ArrayBuffer,
  codec: { decode(bytes: Uint8Array): T },
  fallback: T
): T {
  const bytes = arrayBufferToBytes(buffer);
  return bytes.byteLength === 0 ? fallback : codec.decode(bytes);
}

export async function loadModel(
  request: ModelLoadRequestMessage
): Promise<ModelLoadResultMessage> {
  if (!isNativeModuleAvailable()) {
    return ModelLoadResult.fromPartial({
      success: false,
      modelId: request.modelId,
      errorMessage: 'Native module not available',
    });
  }

  // Swift parity: `try? await ensureServicesReady()` (ModelLifecycle.swift:32).
  await ensureServicesReadyOrIgnore();
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

export async function unloadModel(
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

export async function currentModel(
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

/**
 * Convenience wrapper around `currentModel(...)` that returns the full
 * `ModelInfo` snapshot for the model currently loaded under the given
 * category, or `null` when nothing is loaded.
 *
 * Mirrors the iOS surface used by view-models that need the loaded
 * model's display name / framework without fabricating a stand-in
 * `ModelInfo`. Forces `includeModelMetadata=true` so the commons
 * lifecycle returns the full proto rather than just the id.
 */
export async function modelInfoForCategory(
  category: ModelCategory
): Promise<ModelInfo | null> {
  const result = await currentModel(
    CurrentModelRequest.fromPartial({
      category,
      includeModelMetadata: true,
    })
  );
  if (!result || !result.found) return null;
  return result.model ?? null;
}

export async function componentLifecycleSnapshot(
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
