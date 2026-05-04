import type { SDKEvent } from '@runanywhere/proto-ts/sdk_events';
import {
  SDKEventStreamAdapter,
  type SDKEventHandler,
  type SDKEventUnsubscribe,
} from '../../Adapters/SDKEventStreamAdapter';

function requireAdapter(): SDKEventStreamAdapter {
  const adapter = SDKEventStreamAdapter.tryDefault();
  if (!adapter) {
    throw new Error('RunAnywhere SDKEvent proto adapter is not installed');
  }
  return adapter;
}

export const SDKEvents = {
  subscribe(handler: SDKEventHandler): SDKEventUnsubscribe | null {
    return requireAdapter().subscribe(handler);
  },

  publish(event: SDKEvent): boolean {
    return requireAdapter().publish(event);
  },

  poll(): SDKEvent | null {
    return requireAdapter().poll();
  },

  publishFailure(options: {
    errorCode: number;
    message: string;
    component: string;
    operation: string;
    recoverable: boolean;
  }): boolean {
    return requireAdapter().publishFailure(options);
  },

  clearQueue(): void {
    requireAdapter().clearQueue();
  },
};
