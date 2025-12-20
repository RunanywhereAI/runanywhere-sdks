/**
 * TTS Capability exports
 */

// Import first for local usage
import { TTSCapability as _TTSCapability, TTSServiceWrapper as _TTSServiceWrapper } from './TTSCapability';
import { TTSConfigurationImpl as _TTSConfigurationImpl, type TTSConfiguration as _TTSConfiguration } from './TTSConfiguration';

// Export capability
export { TTSCapability, TTSServiceWrapper } from './TTSCapability';

// Export configuration
export { TTSConfigurationImpl, type TTSConfiguration } from './TTSConfiguration';

// Export models
export {
  type TTSInput,
  type TTSOutput,
  type TTSOptions,
  type PhonemeTimestamp,
  type SynthesisMetadata,
} from './TTSModels';

// Export service and types from Core protocols
export type { TTSService, VoiceInfo } from '../../Core/Protocols/Voice/TTSService';

/**
 * Default TTS configuration
 */
export const DEFAULT_TTS_CONFIGURATION = new _TTSConfigurationImpl();

/**
 * Factory function to create a TTS capability
 */
export function createTTSCapability(
  configuration?: ConstructorParameters<typeof _TTSConfigurationImpl>[0]
): _TTSCapability {
  const config = new _TTSConfigurationImpl(configuration);
  return new _TTSCapability(config);
}

/**
 * Factory function to create TTS configuration
 */
export function createTTSConfiguration(
  options?: ConstructorParameters<typeof _TTSConfigurationImpl>[0]
): _TTSConfiguration {
  return new _TTSConfigurationImpl(options);
}

/**
 * Get sample rate for audio format
 */
export function getAudioFormatSampleRate(format: string): number {
  switch (format.toLowerCase()) {
    case 'pcm':
    case 'wav':
      return 22050;
    case 'mp3':
      return 44100;
    case 'opus':
      return 48000;
    default:
      return 22050;
  }
}
