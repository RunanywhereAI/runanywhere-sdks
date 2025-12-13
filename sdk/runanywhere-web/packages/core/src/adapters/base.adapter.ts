/**
 * Base adapter class that properly implements typed event handling
 */

import { EventEmitter } from 'eventemitter3';

export abstract class BaseAdapter<TEvents extends Record<string, (...args: any[]) => void>> {
  protected emitter = new EventEmitter();

  on<K extends keyof TEvents>(event: K, handler: TEvents[K]): void {
    this.emitter.on(event as string, handler as any);
  }

  off<K extends keyof TEvents>(event: K, handler?: TEvents[K]): void {
    if (handler) {
      this.emitter.off(event as string, handler as any);
    } else {
      this.emitter.removeAllListeners(event as string);
    }
  }

  protected emit<K extends keyof TEvents>(
    event: K,
    ...args: Parameters<TEvents[K]>
  ): void {
    this.emitter.emit(event as string, ...args);
  }

  protected removeAllListeners(): void {
    this.emitter.removeAllListeners();
  }
}
