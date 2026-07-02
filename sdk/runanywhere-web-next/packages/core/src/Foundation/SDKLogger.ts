import { LogLevel, type LoggingConfiguration } from '@runanywhere/proto-ts/logging';
import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';

export { LogLevel };
export type { LoggingConfiguration };

export type LogSource = 'main' | 'worker';

export interface LogRecord {
  level: LogLevel;
  category: string;
  message: string;
  timestampMs: number;
  fields?: Readonly<Record<string, unknown>>;
  source: LogSource;
}

export interface LogSink {
  write(record: LogRecord): void;
  flush?(): void;
  close?(): void;
}

export type SinkDisposer = () => void;

export const LOG_LEVEL_TO_RAC: Record<LogLevel, number> = {
  [LogLevel.LOG_LEVEL_TRACE]: 0,
  [LogLevel.LOG_LEVEL_DEBUG]: 1,
  [LogLevel.LOG_LEVEL_INFO]: 2,
  [LogLevel.LOG_LEVEL_WARNING]: 3,
  [LogLevel.LOG_LEVEL_ERROR]: 4,
  [LogLevel.LOG_LEVEL_FATAL]: 5,
  [LogLevel.UNRECOGNIZED]: -1,
};

export function loggingConfigurationForEnvironment(
  environment: SDKEnvironment,
): LoggingConfiguration {
  switch (environment) {
    case SDKEnvironment.SDK_ENVIRONMENT_STAGING:
      return {
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_INFO,
        includeSourceLocation: false,
        includeDeviceMetadata: true,
        enableRemoteLogging: false,
        enableSentryLogging: false,
      };
    case SDKEnvironment.SDK_ENVIRONMENT_PRODUCTION:
      return {
        enableLocalLogging: false,
        minLogLevel: LogLevel.LOG_LEVEL_WARNING,
        includeSourceLocation: false,
        includeDeviceMetadata: true,
        enableRemoteLogging: false,
        enableSentryLogging: false,
      };
    default:
      return {
        enableLocalLogging: true,
        minLogLevel: LogLevel.LOG_LEVEL_DEBUG,
        includeSourceLocation: false,
        includeDeviceMetadata: false,
        enableRemoteLogging: false,
        enableSentryLogging: true,
      };
  }
}

class LogRouter {
  private level: LogLevel = LogLevel.LOG_LEVEL_INFO;
  private enabled = true;
  private readonly sinks = new Set<LogSink>();
  source: LogSource = 'main';

  attach(sink: LogSink): SinkDisposer {
    this.sinks.add(sink);
    return () => this.detach(sink);
  }

  detach(sink: LogSink): void {
    if (this.sinks.delete(sink)) {
      try { sink.close?.(); } catch {}
    }
  }

  detachAll(): void {
    for (const sink of [...this.sinks]) this.detach(sink);
  }

  setLevel(level: LogLevel): void { this.level = level; }
  setEnabled(enabled: boolean): void { this.enabled = enabled; }

  configure(config: LoggingConfiguration): void {
    this.enabled = config.enableLocalLogging;
    this.level = config.minLogLevel;
  }

  applyEnvironmentConfiguration(environment: SDKEnvironment): void {
    this.configure(loggingConfigurationForEnvironment(environment));
  }

  flush(): void {
    for (const sink of this.sinks) {
      try { sink.flush?.(); } catch {}
    }
  }

  isEnabled(level: LogLevel): boolean {
    return this.enabled && level >= this.level;
  }

  emit(record: LogRecord): void {
    if (!this.isEnabled(record.level)) return;
    for (const sink of this.sinks) {
      try { sink.write(record); } catch {}
    }
  }
}

export class ConsoleSink implements LogSink {
  write(record: LogRecord): void {
    const prefix = `[RunAnywhere:${record.category}]`;
    const args: unknown[] = record.fields ? [prefix, record.message, record.fields] : [prefix, record.message];
    switch (record.level) {
      case LogLevel.LOG_LEVEL_TRACE:
      case LogLevel.LOG_LEVEL_DEBUG:
        console.debug(...args);
        break;
      case LogLevel.LOG_LEVEL_INFO:
        console.info(...args);
        break;
      case LogLevel.LOG_LEVEL_WARNING:
        console.warn(...args);
        break;
      default:
        console.error(...args);
    }
  }
}

export const Logging = new LogRouter();
Logging.attach(new ConsoleSink());

export class SDKLogger {
  constructor(
    private readonly category: string,
    private readonly router: LogRouter = Logging,
  ) {}

  debug(message: string, fields?: Record<string, unknown>): void {
    this.log(LogLevel.LOG_LEVEL_DEBUG, message, fields);
  }

  info(message: string, fields?: Record<string, unknown>): void {
    this.log(LogLevel.LOG_LEVEL_INFO, message, fields);
  }

  warning(message: string, fields?: Record<string, unknown>): void {
    this.log(LogLevel.LOG_LEVEL_WARNING, message, fields);
  }

  error(message: string, fields?: Record<string, unknown>): void {
    this.log(LogLevel.LOG_LEVEL_ERROR, message, fields);
  }

  fault(message: string, fields?: Record<string, unknown>): void {
    this.log(LogLevel.LOG_LEVEL_FATAL, message, fields);
  }

  private log(level: LogLevel, message: string, fields?: Record<string, unknown>): void {
    if (!this.router.isEnabled(level)) return;
    this.router.emit({
      level,
      category: this.category,
      message,
      timestampMs: Date.now(),
      fields,
      source: this.router.source,
    });
  }
}
