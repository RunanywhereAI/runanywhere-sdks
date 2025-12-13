export { WhisperService } from './services/whisper-service';
export * from './types';

// Service token for DI
export const WHISPER_SERVICE_TOKEN = Symbol.for('WhisperService');
