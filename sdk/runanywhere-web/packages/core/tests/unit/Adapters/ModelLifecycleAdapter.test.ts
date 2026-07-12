import { describe, expect, it } from 'vitest';
import { ModelLoadRequest } from '@runanywhere/proto-ts/model_types';
import { SDKComponent } from '@runanywhere/proto-ts/sdk_events';
import {
  ModelLifecycleAdapter,
  type ModelLifecycleModule,
} from '../../../src/Adapters/ModelLifecycleAdapter';
import { RAC_ERROR_NOT_FOUND } from '../../../src/Foundation/RACErrors';

function deferred<T>(): {
  promise: Promise<T>;
  resolve(value: T): void;
} {
  let resolve!: (value: T) => void;
  const promise = new Promise<T>((done) => { resolve = done; });
  return { promise, resolve };
}

function fakeModule(loadResult: Promise<number>): {
  module: ModelLifecycleModule;
  currentCalls(): number;
  snapshotCalls(): number;
} {
  const buffer = new ArrayBuffer(64 * 1024);
  const heapU8 = new Uint8Array(buffer);
  const heapU32 = new Uint32Array(buffer);
  const heap32 = new Int32Array(buffer);
  let nextAllocation = 1_024;
  let currentCalls = 0;
  let snapshotCalls = 0;

  const module: ModelLifecycleModule = {
    HEAPU8: heapU8,
    HEAPU32: heapU32,
    HEAP32: heap32,
    _malloc(size: number): number {
      const pointer = nextAllocation;
      nextAllocation += Math.max(8, (size + 7) & ~7);
      return pointer;
    },
    _free: () => undefined,
    _rac_proto_buffer_init(pointer: number): void {
      heapU32.fill(0, pointer >>> 2, (pointer >>> 2) + 4);
    },
    _rac_proto_buffer_free: () => undefined,
    _rac_wasm_sizeof_proto_buffer: () => 16,
    _rac_wasm_offsetof_proto_buffer_data: () => 0,
    _rac_wasm_offsetof_proto_buffer_size: () => 4,
    _rac_wasm_offsetof_proto_buffer_status: () => 8,
    _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
    _rac_get_model_registry: () => 1,
    _rac_model_lifecycle_load_proto: () => 0,
    _rac_model_lifecycle_unload_proto: () => RAC_ERROR_NOT_FOUND,
    _rac_model_lifecycle_current_model_proto: () => {
      currentCalls += 1;
      return RAC_ERROR_NOT_FOUND;
    },
    _rac_component_lifecycle_snapshot_proto: () => {
      snapshotCalls += 1;
      return RAC_ERROR_NOT_FOUND;
    },
    _rac_model_lifecycle_reset: () => undefined,
    ccall(name: string): unknown {
      return name === 'rac_model_lifecycle_load_proto'
        ? loadResult
        : RAC_ERROR_NOT_FOUND;
    },
  };

  return {
    module,
    currentCalls: () => currentCalls,
    snapshotCalls: () => snapshotCalls,
  };
}

describe('ModelLifecycleAdapter JSPI serialization', () => {
  it('does not synchronously re-enter a module while async model load is in flight', async () => {
    const pending = deferred<number>();
    const harness = fakeModule(pending.promise);
    const adapter = ModelLifecycleAdapter.fromModule(harness.module);

    const load = adapter.loadAsync(ModelLoadRequest.fromPartial({ modelId: 'model' }));
    await Promise.resolve();

    expect(adapter.currentModel()).toBeNull();
    expect(adapter.componentSnapshot(SDKComponent.SDK_COMPONENT_LLM)).toBeNull();
    expect(harness.currentCalls()).toBe(0);
    expect(harness.snapshotCalls()).toBe(0);

    pending.resolve(RAC_ERROR_NOT_FOUND);
    await expect(load).resolves.toBeNull();

    expect(adapter.currentModel()).toBeNull();
    expect(adapter.componentSnapshot(SDKComponent.SDK_COMPONENT_LLM)).toBeNull();
    expect(harness.currentCalls()).toBe(1);
    expect(harness.snapshotCalls()).toBe(1);
  });
});
