/**
 * RunAnywhere Web SDK - Logger
 *
 * Logging system matching the pattern across all SDKs.
 * Routes to console.* methods in the browser.
 */

export enum LogLevel {
  Trace = 0,
  Debug = 1,
  Info = 2,
  Warning = 3,
  Error = 4,
  Fatal = 5,
}

/** Map LogLevel to RACommons rac_log_level_t values */
export const LOG_LEVEL_TO_RAC: Record<LogLevel, number> = {
  [LogLevel.Trace]: 0,
  [LogLevel.Debug]: 1,
  [LogLevel.Info]: 2,
  [LogLevel.Warning]: 3,
  [LogLevel.Error]: 4,
  [LogLevel.Fatal]: 5,
};

export class SDKLogger {
  private static _level: LogLevel = LogLevel.Info;
  private static _enabled = true;

  private readonly category: string;

  constructor(category: string) {
    this.category = category;
  }

  static get level(): LogLevel {
    return SDKLogger._level;
  }

  static set level(level: LogLevel) {
    SDKLogger._level = level;
  }

  static get enabled(): boolean {
    return SDKLogger._enabled;
  }

  static set enabled(value: boolean) {
    SDKLogger._enabled = value;
  }

  trace(message: string): void {
    this.log(LogLevel.Trace, message);
  }

  debug(message: string): void {
    this.log(LogLevel.Debug, message);
  }

  info(message: string): void {
    this.log(LogLevel.Info, message);
  }

  warning(message: string): void {
    this.log(LogLevel.Warning, message);
  }

  error(message: string): void {
    this.log(LogLevel.Error, message);
  }

  private log(level: LogLevel, message: string): void {
    if (!SDKLogger._enabled || level < SDKLogger._level) {
      return;
    }

    const prefix = `[RunAnywhere:${this.category}]`;

    switch (level) {
      case LogLevel.Trace:
      case LogLevel.Debug:
        console.debug(prefix, message);
        break;
      case LogLevel.Info:
        console.info(prefix, message);
        break;
      case LogLevel.Warning:
        console.warn(prefix, message);
        break;
      case LogLevel.Error:
      case LogLevel.Fatal:
        console.error(prefix, message);
        break;
    }
  }
}
