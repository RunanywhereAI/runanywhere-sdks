/**
 * LogLevel.ts
 *
 * Log severity levels for the SDK. Re-exports the generated `LogLevel` from
 * `@runanywhere/proto-ts/logging` so the SDK shares the exact C-ABI numbering
 * (LOG_LEVEL_TRACE=0 .. LOG_LEVEL_FATAL=5) used across commons and the other
 * SDKs. The relative ordering (trace < debug < info < warning < error < fatal)
 * is what the level comparisons in LoggingManager and custom destinations rely on.
 */

export { LogLevel } from '@runanywhere/proto-ts/logging';
