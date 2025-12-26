/**
 * ErrorContext.ts
 *
 * Captures detailed error context for debugging and logging.
 * Matches iOS SDK: Foundation/ErrorTypes/ErrorContext.swift
 */

/**
 * Contextual information captured when an error occurs.
 */
export interface ErrorContext {
  /** Stack trace at error point */
  readonly stackTrace: string[];
  /** Source file where error occurred */
  readonly file: string;
  /** Line number */
  readonly line: number;
  /** Function name */
  readonly function: string;
  /** Error capture timestamp (ISO8601) */
  readonly timestamp: string;
  /** Thread info ("main" or "background") */
  readonly threadInfo: string;
}

/**
 * Create an error context from the current call site.
 * Note: In JavaScript, we can only capture stack traces, not file/line/function directly.
 */
export function createErrorContext(error?: Error): ErrorContext {
  const now = new Date().toISOString();
  const stackTrace = parseStackTrace(error?.stack ?? new Error().stack ?? '');

  // Extract location from first relevant stack frame
  const location = extractLocationFromStack(stackTrace);

  return {
    stackTrace,
    file: location.file,
    line: location.line,
    function: location.function,
    timestamp: now,
    threadInfo: 'main', // JS is single-threaded (main thread)
  };
}

/**
 * Parse a stack trace string into an array of frames.
 */
function parseStackTrace(stack: string): string[] {
  const lines = stack.split('\n');

  return lines
    .slice(1) // Skip "Error: message" line
    .map((line) => line.trim())
    .filter((line) => line.length > 0)
    .filter((line) => !isSystemFrame(line))
    .slice(0, 15); // Limit to 15 frames like iOS
}

/**
 * Check if a stack frame is a system/internal frame that should be filtered.
 */
function isSystemFrame(frame: string): boolean {
  const systemPatterns = [
    'node_modules',
    'internal/',
    '__webpack',
    'regenerator',
    'asyncToGenerator',
    'createErrorContext', // Filter ourselves out
    'parseStackTrace',
  ];

  return systemPatterns.some((pattern) => frame.includes(pattern));
}

/**
 * Extract file, line, and function from the first relevant stack frame.
 */
function extractLocationFromStack(stackTrace: string[]): {
  file: string;
  line: number;
  function: string;
} {
  if (stackTrace.length === 0) {
    return { file: 'unknown', line: 0, function: 'unknown' };
  }

  const firstFrame = stackTrace[0];

  // Try to parse "at functionName (file:line:column)" format
  const atMatch = firstFrame.match(/at\s+(.+?)\s+\((.+?):(\d+):(\d+)\)/);
  if (atMatch) {
    return {
      function: atMatch[1],
      file: atMatch[2],
      line: parseInt(atMatch[3], 10),
    };
  }

  // Try to parse "at file:line:column" format (anonymous function)
  const atFileMatch = firstFrame.match(/at\s+(.+?):(\d+):(\d+)/);
  if (atFileMatch) {
    return {
      function: 'anonymous',
      file: atFileMatch[1],
      line: parseInt(atFileMatch[2], 10),
    };
  }

  // Try to parse "functionName@file:line:column" format (Safari/Firefox)
  const atSignMatch = firstFrame.match(/(.+?)@(.+?):(\d+):(\d+)/);
  if (atSignMatch) {
    return {
      function: atSignMatch[1] || 'anonymous',
      file: atSignMatch[2],
      line: parseInt(atSignMatch[3], 10),
    };
  }

  return { file: 'unknown', line: 0, function: 'unknown' };
}

/**
 * Format the stack trace as a readable string.
 */
export function formatStackTrace(context: ErrorContext): string {
  if (context.stackTrace.length === 0) {
    return 'No stack trace available';
  }
  return context.stackTrace.join('\n');
}

/**
 * Get a formatted location string (file:line in function).
 */
export function formatLocation(context: ErrorContext): string {
  return `${context.file}:${context.line} in ${context.function}`;
}

/**
 * Get a complete formatted context string for logging.
 */
export function formatContext(context: ErrorContext): string {
  return [
    `Time: ${context.timestamp}`,
    `Thread: ${context.threadInfo}`,
    `Location: ${formatLocation(context)}`,
    `Stack Trace:`,
    formatStackTrace(context),
  ].join('\n');
}

/**
 * An error wrapper that includes context information.
 */
export class ContextualError extends Error {
  readonly context: ErrorContext;
  readonly originalError: Error;

  constructor(error: Error, context?: ErrorContext) {
    super(error.message);
    this.name = 'ContextualError';
    this.originalError = error;
    this.context = context ?? createErrorContext(error);

    // Maintain proper prototype chain
    Object.setPrototypeOf(this, ContextualError.prototype);
  }
}

/**
 * Wrap an error with context information.
 */
export function withContext(error: Error): ContextualError {
  if (error instanceof ContextualError) {
    return error; // Already has context
  }
  return new ContextualError(error);
}

/**
 * Extract error context from an error if available.
 */
export function getErrorContext(error: Error): ErrorContext | undefined {
  if (error instanceof ContextualError) {
    return error.context;
  }
  return undefined;
}

/**
 * Get the underlying error value, unwrapping ContextualError if needed.
 */
export function getUnderlyingError(error: Error): Error {
  if (error instanceof ContextualError) {
    return error.originalError;
  }
  return error;
}
