/**
 * VAD Capability exports
 *
 * Exports all VAD-related types, interfaces, and capabilities
 * matching the Swift SDK architecture.
 */
export {
  VADCapability,
  createVADCapability,
  createVADConfiguration,
  createVADInput,
  type VADConfiguration,
  type VADInput,
  type VADOutput,
  type VADSegment,
  type VADService,
  type VADStatistics,
  SpeechActivityEvent,
  DEFAULT_VAD_CONFIG,
} from './VADCapability';

export { VADError } from './Errors/VADError';
