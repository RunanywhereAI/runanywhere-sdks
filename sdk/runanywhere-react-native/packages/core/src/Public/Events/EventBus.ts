/**
 * Swift-shaped SDK event bus.
 *
 * Mirrors Swift's `EventBus.shared` surface while using the RN native
 * proto-byte SDKEvent subscription underneath.
 */

import type { SDKEvent as SDKEventMessage } from '@runanywhere/proto-ts/sdk_events';
import { EventCategory } from '@runanywhere/proto-ts/component_types';
import {
  publishSDKEvent,
  subscribeSDKEvents,
} from '../Extensions/Events/RunAnywhere+SDKEvents';

export type SDKEventHandler = (event: SDKEventMessage) => void;
export type EventBusCancellable = () => void;

type NativeUnsubscribe = () => Promise<void>;

export class EventBus {
  private static readonly singleton = new EventBus();

  static get shared(): EventBus {
    return EventBus.singleton;
  }

  private readonly listeners = new Set<SDKEventHandler>();
  private readonly categoryListeners = new Map<EventCategory, Set<SDKEventHandler>>();
  private nativeSubscription: Promise<NativeUnsubscribe> | null = null;

  private constructor() {
    this.ensureNativeSubscription();
  }

  /**
   * Async stream of all SDK events.
   */
  get events(): AsyncIterable<SDKEventMessage> {
    return this.stream();
  }

  /**
   * Publish an event through native commons, falling back to local listeners.
   */
  async publish(event: SDKEventMessage): Promise<boolean> {
    const didPublish = await publishSDKEvent(event);
    if (!didPublish) {
      this.dispatch(event);
    }
    return didPublish;
  }

  /**
   * Async stream filtered by event category.
   */
  eventsFor(category: EventCategory): AsyncIterable<SDKEventMessage> {
    return this.stream(category);
  }

  on(handler: SDKEventHandler): EventBusCancellable;
  on(category: EventCategory, handler: SDKEventHandler): EventBusCancellable;
  on(
    categoryOrHandler: EventCategory | SDKEventHandler,
    maybeHandler?: SDKEventHandler
  ): EventBusCancellable {
    this.ensureNativeSubscription();

    if (typeof categoryOrHandler === 'function') {
      this.listeners.add(categoryOrHandler);
      return () => {
        this.listeners.delete(categoryOrHandler);
      };
    }

    const category = categoryOrHandler;
    const handler = maybeHandler;
    if (!handler) {
      return () => undefined;
    }

    let handlers = this.categoryListeners.get(category);
    if (!handlers) {
      handlers = new Set<SDKEventHandler>();
      this.categoryListeners.set(category, handlers);
    }
    handlers.add(handler);
    return () => {
      handlers?.delete(handler);
      if (handlers?.size === 0) {
        this.categoryListeners.delete(category);
      }
    };
  }

  private ensureNativeSubscription(): void {
    if (this.nativeSubscription) {
      return;
    }

    const subscription = subscribeSDKEvents((event) => {
      this.dispatch(event);
    });
    this.nativeSubscription = subscription;
    void subscription.catch(() => {
      if (this.nativeSubscription === subscription) {
        this.nativeSubscription = null;
      }
    });
  }

  private dispatch(event: SDKEventMessage): void {
    for (const listener of Array.from(this.listeners)) {
      try {
        listener(event);
      } catch (e) {
        console.warn('SDK EventBus listener error:', e);
      }
    }
    const categoryListeners = this.categoryListeners.get(event.category);
    if (!categoryListeners) {
      return;
    }
    for (const listener of Array.from(categoryListeners)) {
      try {
        listener(event);
      } catch (e) {
        console.warn('SDK EventBus category listener error:', e);
      }
    }
  }

  private stream(category?: EventCategory): AsyncIterable<SDKEventMessage> {
    return {
      [Symbol.asyncIterator]: (): AsyncIterator<SDKEventMessage> => {
        const queue: SDKEventMessage[] = [];
        let resolver:
          | ((value: IteratorResult<SDKEventMessage>) => void)
          | null = null;
        let isClosed = false;

        const unsubscribe = category === undefined
          ? this.on((event) => {
            if (resolver) {
              resolver({ value: event, done: false });
              resolver = null;
            } else {
              queue.push(event);
            }
          })
          : this.on(category, (event) => {
            if (resolver) {
              resolver({ value: event, done: false });
              resolver = null;
            } else {
              queue.push(event);
            }
          });

        return {
          async next(): Promise<IteratorResult<SDKEventMessage>> {
            if (queue.length > 0) {
              return { value: queue.shift()!, done: false };
            }
            if (isClosed) {
              return {
                value: undefined as unknown as SDKEventMessage,
                done: true,
              };
            }
            return new Promise<IteratorResult<SDKEventMessage>>((resolve) => {
              resolver = resolve;
            });
          },
          async return(): Promise<IteratorResult<SDKEventMessage>> {
            isClosed = true;
            unsubscribe();
            if (resolver) {
              resolver({
                value: undefined as unknown as SDKEventMessage,
                done: true,
              });
              resolver = null;
            }
            return {
              value: undefined as unknown as SDKEventMessage,
              done: true,
            };
          },
        };
      },
    };
  }
}
