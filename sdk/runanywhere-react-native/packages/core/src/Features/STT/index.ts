/**
 * STT Capability exports
 */

// Import first for local usage
import { STTCapability as _STTCapability } from './STTCapability';
import {
  STTConfigurationImpl as _STTConfigurationImpl,
  type STTConfiguration as _STTConfiguration,
} from './STTConfiguration';

// Export capability
export { STTCapability, STTServiceWrapper } from './STTCapability';

// Export configuration
export {
  type STTConfiguration,
  STTConfigurationImpl,
} from './STTConfiguration';

// Export models
export {
  type STTInput,
  type STTOutput,
  type STTOptions,
  type WordTimestamp,
  type TranscriptionAlternative,
  type TranscriptionMetadata,
  type STTTranscriptionResult,
  type TimestampInfo,
  type AlternativeTranscription,
  type STTStreamResult,
} from './STTModels';

// Export STTService from Core protocols
export type { STTService } from '../../Core/Protocols/Voice/STTService';

// Export errors
export { STTError } from './Errors/STTError';

/**
 * STT transcription mode
 */
export enum STTMode {
  /** Batch mode - transcribe complete audio */
  Batch = 'batch',
  /** Streaming mode - real-time transcription */
  Streaming = 'streaming',
}

/**
 * Default STT configuration
 */
export const DEFAULT_STT_CONFIGURATION = new _STTConfigurationImpl();

/**
 * Factory function to create an STT capability
 */
export function createSTTCapability(
  configuration?: ConstructorParameters<typeof _STTConfigurationImpl>[0]
): _STTCapability {
  const config = new _STTConfigurationImpl(configuration);
  return new _STTCapability(config);
}

/**
 * Factory function to create STT configuration
 */
export function createSTTConfiguration(
  options?: ConstructorParameters<typeof _STTConfigurationImpl>[0]
): _STTConfiguration {
  return new _STTConfigurationImpl(options);
}
