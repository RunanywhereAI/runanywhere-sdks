import {
  SDKEvent,
  type SDKEvent as ProtoSDKEvent,
} from '@runanywhere/proto-ts/sdk_events';
import { SDKLogger } from '../Foundation/SDKLogger';
import { ProtoWasmBridge, type ProtoWasmModule } from '../runtime/ProtoWasm';

const logger = new SDKLogger('SDKEventStreamAdapter');

export interface SDKEventStreamModule extends ProtoWasmModule {
  addFunction?(fn: (...args: number[]) => number | void, signature: string): number;
  removeFunction?(ptr: number): void;
  _rac_sdk_event_subscribe?(callbackPtr: number, userData: number): number | bigint;
  _rac_sdk_event_unsubscribe?(subscriptionId: number | bigint): void;
  _rac_sdk_event_publish_proto?(protoBytes: number, protoSize: number): number;
  _rac_sdk_event_poll?(outEvent: number): number;
  _rac_sdk_event_publish_failure?(
    errorCode: number,
    message: number,
    component: number,
    operation: number,
    recoverable: number,
  ): number;
  _rac_sdk_event_clear_queue?(): void;
}

export type SDKEventHandler = (event: ProtoSDKEvent) => void;
export type SDKEventUnsubscribe = () => void;

let defaultModule: SDKEventStreamModule | null = null;

export class SDKEventStreamAdapter {
  static setDefaultModule(module: SDKEventStreamModule): void {
    defaultModule = module;
  }

  static clearDefaultModule(): void {
    defaultModule = null;
  }

  static tryDefault(): SDKEventStreamAdapter | null {
    return defaultModule ? new SDKEventStreamAdapter(defaultModule) : null;
  }

  private readonly callbackPtrs = new Map<string, number>();

  constructor(private readonly module: SDKEventStreamModule) {}

  supportsProtoEvents(): boolean {
    return this.missingExports().length === 0;
  }

  subscribe(handler: SDKEventHandler): SDKEventUnsubscribe | null {
    const mod = this.module;
    if (!this.ensureExports('subscribe', ['_rac_sdk_event_subscribe'])) return null;
    if (!mod.addFunction || !mod.removeFunction || !mod.HEAPU8) {
      logger.warning('subscribe: module missing addFunction/removeFunction/HEAPU8');
      return null;
    }

    const callbackPtr = mod.addFunction((bytesPtr: number, size: number) => {
      if (!bytesPtr || size <= 0) return;
      const bytes = mod.HEAPU8!.slice(bytesPtr, bytesPtr + size);
      handler(SDKEvent.decode(bytes));
    }, 'viii');

    const subscriptionId = mod._rac_sdk_event_subscribe!(callbackPtr, 0);
    if (isZeroSubscription(subscriptionId)) {
      mod.removeFunction(callbackPtr);
      logger.warning('rac_sdk_event_subscribe returned subscription id 0');
      return null;
    }

    const key = subscriptionKey(subscriptionId);
    this.callbackPtrs.set(key, callbackPtr);
    return () => {
      mod._rac_sdk_event_unsubscribe?.(subscriptionId);
      const storedPtr = this.callbackPtrs.get(key);
      if (storedPtr) {
        mod.removeFunction?.(storedPtr);
        this.callbackPtrs.delete(key);
      }
    };
  }

  publish(event: ProtoSDKEvent): boolean {
    if (!this.ensureExports('publish', ['_rac_sdk_event_publish_proto'])) return false;
    const bytes = SDKEvent.encode(event).finish();
    return this.bridge().withHeapBytes(bytes, (ptr, size) => (
      this.module._rac_sdk_event_publish_proto!(ptr, size) === 0
    ));
  }

  poll(): ProtoSDKEvent | null {
    if (!this.ensureExports('poll', ['_rac_sdk_event_poll'])) return null;
    return this.bridge().callResultProto(
      SDKEvent,
      (outEvent) => this.module._rac_sdk_event_poll!(outEvent),
      'rac_sdk_event_poll',
    );
  }

  publishFailure(options: {
    errorCode: number;
    message: string;
    component: string;
    operation: string;
    recoverable: boolean;
  }): boolean {
    if (!this.ensureExports('publishFailure', ['_rac_sdk_event_publish_failure'])) return false;
    const bridge = this.bridge();
    const messagePtr = bridge.allocUtf8(options.message);
    const componentPtr = bridge.allocUtf8(options.component);
    const operationPtr = bridge.allocUtf8(options.operation);
    if (!messagePtr || !componentPtr || !operationPtr) {
      bridge.free(messagePtr);
      bridge.free(componentPtr);
      bridge.free(operationPtr);
      return false;
    }
    try {
      return this.module._rac_sdk_event_publish_failure!(
        options.errorCode,
        messagePtr,
        componentPtr,
        operationPtr,
        options.recoverable ? 1 : 0,
      ) === 0;
    } finally {
      bridge.free(messagePtr);
      bridge.free(componentPtr);
      bridge.free(operationPtr);
    }
  }

  clearQueue(): void {
    this.module._rac_sdk_event_clear_queue?.();
  }

  private bridge(): ProtoWasmBridge {
    return new ProtoWasmBridge(this.module, logger);
  }

  private missingExports(): string[] {
    const required: Array<keyof SDKEventStreamModule> = [
      '_rac_sdk_event_subscribe',
      '_rac_sdk_event_unsubscribe',
      '_rac_sdk_event_publish_proto',
      '_rac_sdk_event_poll',
      '_rac_sdk_event_publish_failure',
    ];
    return [
      ...this.bridge().missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
  }

  private ensureExports(
    operation: string,
    required: Array<keyof SDKEventStreamModule>,
  ): boolean {
    const missing = [
      ...this.bridge().missingProtoBufferExports(),
      ...required.filter((key) => !this.module[key]).map(String),
    ];
    if (missing.length > 0) {
      logger.warning(`${operation}: module missing SDKEvent proto exports: ${missing.join(', ')}`);
      return false;
    }
    return true;
  }
}

function isZeroSubscription(subscriptionId: number | bigint): boolean {
  return typeof subscriptionId === 'bigint' ? subscriptionId === 0n : subscriptionId === 0;
}

function subscriptionKey(subscriptionId: number | bigint): string {
  return typeof subscriptionId === 'bigint' ? subscriptionId.toString() : String(subscriptionId);
}
