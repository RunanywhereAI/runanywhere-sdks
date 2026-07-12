import { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import { describe, expect, it, vi } from 'vitest';
import {
  SDKEventStreamAdapter,
  type SDKEventStreamModule,
} from '../../../src/Adapters/SDKEventStreamAdapter';
import { LogLevel, SDKLogger } from '../../../src/Foundation/SDKLogger';

describe('SDKEventStreamAdapter WASM_BIGINT boundary', () => {
  it('contains callback failures and still quiesces before removing the function', () => {
    const heap = new Uint8Array(128);
    const unsubscribed: bigint[] = [];
    const retirementOrder: string[] = [];
    const subscriptionId = 0x0000_0001_0000_0001n;
    let nativeCallback: ((...args: number[]) => number | void) | undefined;
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
      addFunction: (callback) => {
        nativeCallback = callback;
        return 7;
      },
      removeFunction: () => {
        retirementOrder.push('remove');
      },
      _rac_sdk_event_subscribe: () => subscriptionId,
      _rac_sdk_event_unsubscribe: (value: bigint) => {
        unsubscribed.push(value);
        retirementOrder.push('unsubscribe');
      },
      _rac_sdk_event_quiesce: () => {
        retirementOrder.push('quiesce');
      },
    };

    const priorLoggingEnabled = SDKLogger.enabled;
    const priorLogLevel = SDKLogger.level;
    SDKLogger.enabled = true;
    SDKLogger.level = LogLevel.LOG_LEVEL_WARNING;
    const warningSpy = vi.spyOn(console, 'warn').mockImplementation(() => undefined);
    const privateError = 'private-handler-detail';

    try {
      let handlerCalls = 0;
      const unsubscribe = new SDKEventStreamAdapter(module).subscribe(() => {
        handlerCalls += 1;
        throw new Error(privateError);
      });
      expect(unsubscribe).not.toBeNull();
      expect(nativeCallback).toBeDefined();

      // Truncated length-delimited field: protobuf decoding throws before the
      // user handler. The WASM callback boundary must contain it.
      const invalidBytes = Uint8Array.of(0x0a, 0x02, 0x41);
      heap.set(invalidBytes, 8);
      expect(() => nativeCallback?.(8, invalidBytes.length)).not.toThrow();

      // A valid event reaches the handler, whose exception must be contained
      // by the same boundary so native dispatch can finish and quiesce.
      const validBytes = SDKEvent.encode(SDKEvent.fromPartial({ id: 'event-id' })).finish();
      heap.set(validBytes, 32);
      expect(() => nativeCallback?.(32, validBytes.length)).not.toThrow();
      expect(handlerCalls).toBe(1);

      unsubscribe?.();
      expect(unsubscribed).toEqual([subscriptionId]);
      expect(retirementOrder).toEqual(['unsubscribe', 'quiesce', 'remove']);
      expect(warningSpy).toHaveBeenCalledTimes(2);
      const warningText = warningSpy.mock.calls.flat().join(' ');
      expect(warningText).toContain('SDKEvent callback failed');
      expect(warningText).not.toContain(privateError);
    } finally {
      warningSpy.mockRestore();
      SDKLogger.enabled = priorLoggingEnabled;
      SDKLogger.level = priorLogLevel;
    }
  });

  it('does not register a callback when quiescence is unavailable', () => {
    let addFunctionCalls = 0;
    const module: SDKEventStreamModule = {
      HEAPU8: new Uint8Array(32),
      _malloc: () => 16,
      _free: () => undefined,
      _rac_proto_buffer_init: () => undefined,
      _rac_proto_buffer_free: () => undefined,
      _rac_wasm_sizeof_proto_buffer: () => 16,
      _rac_wasm_offsetof_proto_buffer_data: () => 0,
      _rac_wasm_offsetof_proto_buffer_size: () => 4,
      _rac_wasm_offsetof_proto_buffer_status: () => 8,
      _rac_wasm_offsetof_proto_buffer_error_message: () => 12,
      addFunction: () => {
        addFunctionCalls += 1;
        return 7;
      },
      removeFunction: () => undefined,
      _rac_sdk_event_subscribe: () => 1n,
      _rac_sdk_event_unsubscribe: () => undefined,
    };

    expect(new SDKEventStreamAdapter(module).subscribe(() => undefined)).toBeNull();
    expect(addFunctionCalls).toBe(0);
  });
});
