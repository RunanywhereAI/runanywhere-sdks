export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  NONE = 4
}

export interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: Date;
  category?: string;
  context?: Record<string, unknown>;
}

export interface LogHandler {
  (entry: LogEntry): void;
}

export class Logger {
  private static instance: Logger;
  private level: LogLevel = LogLevel.INFO;
  private handlers: LogHandler[] = [];

  private constructor() {
    // Default console handler with colored output
    this.addHandler((entry) => {
      const timestamp = entry.timestamp.toISOString();
      const prefix = `[${entry.category || 'SDK'}] ${timestamp}`;
      const contextStr = entry.context ? ` ${JSON.stringify(entry.context)}` : '';

      switch (entry.level) {
        case LogLevel.DEBUG:
          console.debug(`%c${prefix} DEBUG: ${entry.message}${contextStr}`, 'color: gray');
          break;
        case LogLevel.INFO:
          console.info(`%c${prefix} INFO: ${entry.message}${contextStr}`, 'color: blue');
          break;
        case LogLevel.WARN:
          console.warn(`%c${prefix} WARN: ${entry.message}${contextStr}`, 'color: orange');
          break;
        case LogLevel.ERROR:
          console.error(`%c${prefix} ERROR: ${entry.message}${contextStr}`, 'color: red');
          break;
      }
    });
  }

  static getInstance(): Logger {
    if (!Logger.instance) {
      Logger.instance = new Logger();
    }
    return Logger.instance;
  }

  setLevel(level: LogLevel): void {
    this.level = level;
  }

  getLevel(): LogLevel {
    return this.level;
  }

  addHandler(handler: LogHandler): void {
    this.handlers.push(handler);
  }

  removeHandler(handler: LogHandler): void {
    const index = this.handlers.indexOf(handler);
    if (index >= 0) {
      this.handlers.splice(index, 1);
    }
  }

  clearHandlers(): void {
    this.handlers = [];
  }

  private log(level: LogLevel, message: string, category?: string, context?: Record<string, unknown>): void {
    if (level < this.level) return;

    const entry: LogEntry = {
      level,
      message,
      timestamp: new Date(),
      category,
      context
    };

    this.handlers.forEach(handler => {
      try {
        handler(entry);
      } catch (error) {
        console.error('Logger handler error:', error);
      }
    });
  }

  debug(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.DEBUG, message, category, context);
  }

  info(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.INFO, message, category, context);
  }

  warn(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.WARN, message, category, context);
  }

  error(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.ERROR, message, category, context);
  }

  // Utility method for performance logging
  time(label: string, category?: string): void {
    if (typeof performance !== 'undefined') {
      performance.mark(`${label}-start`);
      this.debug(`Timer started: ${label}`, category);
    }
  }

  timeEnd(label: string, category?: string): void {
    if (typeof performance !== 'undefined') {
      performance.mark(`${label}-end`);
      try {
        performance.measure(label, `${label}-start`, `${label}-end`);
        const measure = performance.getEntriesByName(label)[0];
        if (measure) {
          this.debug(`Timer ended: ${label} (${measure.duration.toFixed(2)}ms)`, category);
        }
      } catch (error) {
        this.debug(`Timer ended: ${label}`, category);
      }
    }
  }
}

export const logger = Logger.getInstance();
