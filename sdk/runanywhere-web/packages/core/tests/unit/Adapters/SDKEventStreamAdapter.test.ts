import { describe, expect, it } from 'vitest';
import {
  SDKEventStreamAdapter,
  type SDKEventStreamModule,
} from '../../../src/Adapters/SDKEventStreamAdapter';

describe('SDKEventStreamAdapter WASM_BIGINT boundary', () => {
  it('passes the uint64 subscription id back to unsubscribe as bigint', () => {
    const heap = new Uint8Array(128);
    const unsubscribed: bigint[] = [];
    const subscriptionId = 0x0000_0001_0000_0001n;
    const module: SDKEventStreamModule = {
      HEAPU8: heap,
      _malloc: () => 16,
      _free: () => undefined,
      _rac_proto_buffer_init: () => undefined,
      _rac_proto_buffer_free: () => undefined,
      _rac_wasm_sizeof_proto_buffer: () => 16,
      _rac_wasm_offsetof_proto_buffer_data: () => 0,
      _rac_wasm_offsetof_proto_buffer_size: () => 4,
      _rac_wasm_offsetof_proto_buffer_status: () => 8,
      _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
      addFunction: () => 7,
      removeFunction: () => undefined,
      _rac_sdk_event_subscribe: () => subscriptionId,
      _rac_sdk_event_unsubscribe: (value: bigint) => {
        unsubscribed.push(value);
      },
    };

    const unsubscribe = new SDKEventStreamAdapter(module).subscribe(() => undefined);
    expect(unsubscribe).not.toBeNull();
    unsubscribe?.();
    expect(unsubscribed).toEqual([subscriptionId]);
  });
});
