/**
 * HandleStreamAdapter.ts (React Native)
 *
 * Generic per-handle fan-out over a Nitro proto-byte subscription. Port of
 * Swift `Adapters/HandleStreamAdapter.swift`: the LLM and VoiceAgent stream
 * adapters are identical except for (1) the proto Event type, (2) the Nitro
 * subscribe method, and (3) the optional terminal-event predicate. This
 * generic absorbs all three.
 *
 * Semantics (matched to Swift `HandleStreamAdapter` exactly):
 *   - The first subscriber installs one Nitro subscription per handle.
 *   - Subsequent subscribers fan out from the same subscription — the
 *     underlying C ABI exposes a SINGLE proto-callback slot per handle.
 *   - On the last subscriber detaching, the subscription is torn down and
 *     the per-handle fan-out is removed from the registry map.
 *   - If `isTerminalEvent` is supplied, an event satisfying the predicate
 *     finishes every subscriber and tears down the subscription immediately
 *     (the LLM `isFinal` semantics — Swift LLMStreamAdapter.swift:63). When
 *     omitted (the VoiceAgent case), events fan out until consumers detach
 *     or the native side signals done.
 */

/** A Nitro proto-byte subscription installer; returns the unsubscribe fn. */
export type NitroProtoSubscribe = (
  handle: number,
  onBytes: (bytes: ArrayBuffer) => void,
  onDone: () => void,
  onError: (err: string) => void
) => () => void;

interface Subscriber<Event> {
  onMessage: (e: Event) => void;
  onError: (err: Error) => void;
  onDone: () => void;
}

/** Configuration shared by every fan-out of one stream kind. */
export interface HandleStreamOptions<Event> {
  /** Human-readable label used in registration-failure errors. */
  label: string;
  /** Installs the single Nitro proto-byte subscription for a handle. */
  subscribe: NitroProtoSubscribe;
  /** Decodes raw proto bytes into the typed Event. */
  decode: (bytes: Uint8Array) => Event;
  /**
   * Classifies an event as terminal. When supplied and a broadcast event
   * satisfies it, every subscriber is finished and the subscription is torn
   * down deterministically instead of waiting for the native `onDone`.
   */
  isTerminalEvent?: (event: Event) => boolean;
}

/**
 * Per-handle fan-out state. Holds the active subscriber set and a single
 * Nitro unsubscribe closure installed for the lifetime of the first
 * through last subscriber against this handle.
 */
class HandleFanOut<Event> {
  private readonly subscribers = new Set<Subscriber<Event>>();
  private unsubscribeNitro: (() => void) | null = null;

  constructor(
    private readonly handle: number,
    private readonly options: HandleStreamOptions<Event>,
    private readonly onTornDown: () => void
  ) {}

  /**
   * Attach a subscriber. Installs the shared Nitro subscription on first
   * attach. Returns a cancel function that removes the subscriber (and
   * tears the Nitro subscription down when the last one leaves), or null
   * if the initial Nitro registration failed.
   */
  attach(sub: Subscriber<Event>): (() => void) | null {
    if (this.unsubscribeNitro === null) {
      const ok = this.installNitro();
      if (!ok) return null;
    }
    this.subscribers.add(sub);
    return () => this.detach(sub);
  }

  private installNitro(): boolean {
    try {
      this.unsubscribeNitro = this.options.subscribe(
        this.handle,
        (bytes: ArrayBuffer) => {
          let event: Event;
          try {
            event = this.options.decode(new Uint8Array(bytes));
          } catch (e) {
            this.broadcastError(e);
            return;
          }
          this.broadcast(event);
        },
        () => {
          // Native signalled end-of-stream; finish all subscribers.
          this.finishAll();
        },
        (err: string) => {
          this.broadcastError(new Error(err));
        }
      );
      return true;
    } catch {
      return false;
    }
  }

  private broadcast(event: Event): void {
    // Iterate a snapshot so a subscriber that cancels in its onMessage
    // handler cannot mutate the set underneath us.
    const snapshot = Array.from(this.subscribers);
    for (const s of snapshot) {
      try {
        s.onMessage(event);
      } catch (e) {
        // Deliver the throw to that subscriber only; don't starve peers.
        try {
          s.onError(e instanceof Error ? e : new Error(String(e)));
        } catch {
          /* swallow */
        }
        this.subscribers.delete(s);
      }
    }
    // Deterministic teardown on terminal events (Swift
    // LLMStreamAdapter.swift:63 finishes on `event.isFinal` instead of
    // waiting for the native onDone).
    if (this.options.isTerminalEvent?.(event)) {
      this.finishAll();
    }
  }

  private finishAll(): void {
    const snapshot = Array.from(this.subscribers);
    this.subscribers.clear();
    for (const s of snapshot) {
      try {
        s.onDone();
      } catch {
        /* swallow */
      }
    }
    this.tearDown();
  }

  private broadcastError(e: unknown): void {
    const err = e instanceof Error ? e : new Error(String(e));
    const snapshot = Array.from(this.subscribers);
    this.subscribers.clear();
    for (const s of snapshot) {
      try {
        s.onError(err);
      } catch {
        /* swallow */
      }
    }
    this.tearDown();
  }

  private detach(sub: Subscriber<Event>): void {
    this.subscribers.delete(sub);
    if (this.subscribers.size === 0) {
      this.tearDown();
    }
  }

  private tearDown(): void {
    if (this.unsubscribeNitro === null) return;
    const fn = this.unsubscribeNitro;
    this.unsubscribeNitro = null;
    try {
      fn();
    } catch {
      /* swallow */
    }
    this.onTornDown();
  }
}

/**
 * One registry per stream kind (LLM, VoiceAgent, ...). Keyed by native
 * handle; produces the structural transport object the proto-ts stream
 * factories (`generateLLM`, `streamVoiceAgent`) consume.
 */
export class HandleStreamFanOutRegistry<Event> {
  private readonly cache = new Map<number, HandleFanOut<Event>>();

  constructor(private readonly options: HandleStreamOptions<Event>) {}

  /** Build the proto-ts StreamTransport for one native handle. */
  transportFor(handle: number): {
    subscribe(
      req: unknown,
      onMessage: (e: Event) => void,
      onError: (err: Error) => void,
      onDone: () => void
    ): () => void;
  } {
    const registry = this;
    return {
      subscribe(_req, onMessage, onError, onDone) {
        let fan = registry.cache.get(handle);
        if (!fan) {
          fan = new HandleFanOut<Event>(handle, registry.options, () =>
            registry.cache.delete(handle)
          );
          registry.cache.set(handle, fan);
        }

        const sub: Subscriber<Event> = { onMessage, onError, onDone };
        const cancel = fan.attach(sub);
        if (!cancel) {
          onError(
            new Error(`${registry.options.label} failed for handle ${handle}`)
          );
          onDone();
          return () => {
            /* already torn down by attach() failure */
          };
        }
        return cancel;
      },
    };
  }
}
