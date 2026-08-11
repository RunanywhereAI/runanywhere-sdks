// logging.ts — the `logging` namespace.
//
// Swift has six loose statics (`configureLogging`, `setLogLevel`,
// `setLocalLoggingEnabled`, `addLogDestination`, `setDebugMode`, `flushLogs`);
// this is the same six as one namespace, which is the shape every other v3
// capability uses.
//
// What differs from Swift is where the level lives. Swift filters SDK-side, in
// its own `Logging` service, so a record commons already formatted is thrown
// away in Swift. Here the level is commons' own `rac_logger_set_min_level`,
// which every RAC_LOG_* macro reads BEFORE it builds metadata or runs vsnprintf
// — so raising the level actually stops the work rather than hiding its output.
//
// `LoggingConfiguration`, `LogLevel`, and `LogEntry` are the generated types
// from `idl/logging.proto`; nothing here restates them. `LogLevel` mirrors
// `rac_log_level_t` ordinal-for-ordinal by design ("0 is TRACE, not
// UNSPECIFIED, to keep numeric parity with the C enum"), which is what lets a
// record cross the addon boundary as a plain number.

import { LogLevel } from '@runanywhere/proto-ts/logging';
import type { LogEntry, LoggingConfiguration } from '@runanywhere/proto-ts/logging';
import type { NativeLogRecord, RaBackend } from './backend';
import { bridgeStream } from './iter';

/** A sink that receives every record at or above the configured level. */
export type LogDestination = (entry: LogEntry) => void;

/** SDK diagnostics: level, sinks, and the record stream. */
export interface LoggingNamespace {
  /**
   * Apply a whole configuration at once.
   *
   * Only `minLogLevel` and `enableLocalLogging` have anywhere to land today:
   * `includeSourceLocation` and `includeDeviceMetadata` describe fields commons
   * fills on its own metadata struct and does not pass through the platform
   * adapter's log slot, and `enableRemoteLogging` needs a control plane that
   * accepts log batches. They are accepted and reported unchanged by
   * {@link configuration} rather than silently dropped.
   *
   * @example
   * RunAnywhere.logging.configure({ minLogLevel: LogLevel.LOG_LEVEL_DEBUG });
   */
  configure(config: Partial<LoggingConfiguration>): Promise<void>;
  /** What {@link configure} last applied, with the level read back from commons. */
  configuration(): Promise<LoggingConfiguration>;
  /** Drop every record below `level`. */
  setLevel(level: LogLevel): Promise<void>;
  /** The level commons is filtering at right now. */
  level(): Promise<LogLevel>;
  /** Whether records also go to this process's stderr. */
  setLocalEnabled(enabled: boolean): Promise<void>;
  /** Swift's `setDebugMode`: verbose level plus the local sink, or back to info. */
  setDebugMode(enabled: boolean): Promise<void>;
  /**
   * Add a sink. Returns the function that removes it again — a plain closure
   * rather than an identifier, so a caller cannot leak a subscription it has no
   * handle for.
   */
  addDestination(destination: LogDestination): Promise<() => void>;
  /**
   * Every record, as a stream. The same subscription {@link addDestination}
   * uses, in the shape the rest of the SDK's streaming verbs have.
   *
   * @example
   * for await (const entry of RunAnywhere.logging.records()) console.log(entry.message);
   */
  records(): AsyncIterableIterator<LogEntry>;
  /** Push whatever is buffered to its destinations now. */
  flush(): Promise<void>;
}

/** What the logging namespace needs from the facade. */
export interface LoggingDeps {
  backend: RaBackend;
}

/** The defaults commons itself starts at, so `configuration()` never invents one. */
const BASE_CONFIGURATION: LoggingConfiguration = {
  enableLocalLogging: true,
  minLogLevel: LogLevel.LOG_LEVEL_INFO,
  includeSourceLocation: false,
  includeDeviceMetadata: false,
  enableRemoteLogging: false,
};

/** One native record as the generated `LogEntry`. */
function toLogEntry(record: NativeLogRecord): LogEntry {
  return {
    timestampUnixMs: record.timestampUnixMs,
    // The addon hands over a rac_log_level_t, which is LogLevel's own numbering.
    level: record.level as LogLevel,
    category: record.category,
    message: record.message,
    metadata: {},
    // Commons carries source location and model context on its own
    // `rac_log_metadata_t`, which the platform adapter's log slot never sees —
    // it receives a level, a category, and an already-formatted message. Empty
    // is the honest value; a fabricated file/line would be worse than none.
    file: '',
    line: 0,
    function: '',
    errorCode: 0,
    modelId: '',
    framework: 0,
  };
}

/** Build the `logging` namespace over a backend. */
export function createLoggingNamespace(deps: LoggingDeps): LoggingNamespace {
  const destinations = new Set<LogDestination>();
  // Commons offers one process-wide log callback, so the subscription opens on
  // the first destination and closes with the last — a process that never asks
  // for records pays nothing, and never holds the addon's callback open.
  let watching: Promise<void> | null = null;
  let applied: LoggingConfiguration = { ...BASE_CONFIGURATION };

  const deliver = (record: NativeLogRecord): void => {
    const entry = toLogEntry(record);
    for (const destination of [...destinations]) destination(entry);
  };

  const attach = (destination: LogDestination): (() => void) => {
    destinations.add(destination);
    if (!watching) {
      watching = deps.backend.loggingWatch(deliver);
      // The watch settles only when the last destination detaches; a rejection
      // is reported to nobody, and must not become an unhandled rejection.
      watching.catch(() => undefined);
    }
    return () => {
      if (!destinations.delete(destination) || destinations.size > 0) return;
      watching = null;
      void deps.backend.loggingUnwatch();
    };
  };

  const setLevel = async (level: LogLevel): Promise<void> => {
    await deps.backend.loggingSetLevel(level);
    applied = { ...applied, minLogLevel: level };
  };

  const setLocalEnabled = async (enabled: boolean): Promise<void> => {
    await deps.backend.loggingSetLocalEnabled(enabled);
    applied = { ...applied, enableLocalLogging: enabled };
  };

  return {
    async configure(config) {
      const next: LoggingConfiguration = { ...BASE_CONFIGURATION, ...config };
      await setLevel(next.minLogLevel);
      await setLocalEnabled(next.enableLocalLogging);
      applied = next;
    },

    async configuration() {
      // Commons is the authority on the level: another component may have moved
      // it, and reporting the last value this namespace wrote would be a guess.
      return { ...applied, minLogLevel: (await deps.backend.loggingLevel()) as LogLevel };
    },

    setLevel,

    async level() {
      return (await deps.backend.loggingLevel()) as LogLevel;
    },

    setLocalEnabled,

    async setDebugMode(enabled) {
      await setLevel(enabled ? LogLevel.LOG_LEVEL_DEBUG : LogLevel.LOG_LEVEL_INFO);
      await setLocalEnabled(enabled);
    },

    async addDestination(destination) {
      return attach(destination);
    },

    records() {
      let detach: (() => void) | null = null;
      return bridgeStream<LogEntry>(
        (sink) => {
          detach = attach((entry) => sink.push(entry));
        },
        () => {
          detach?.();
          detach = null;
        }
      );
    },

    flush() {
      return deps.backend.loggingFlush();
    },
  };
}

export { LogLevel };
export type { LogEntry, LoggingConfiguration };
