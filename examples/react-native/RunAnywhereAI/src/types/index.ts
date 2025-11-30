/**
 * Type Exports
 */

// Chat types
export * from './chat';

// Model types
export * from './model';

// Voice types
export * from './voice';

// Settings types
export * from './settings';

// Navigation types
export type RootTabParamList = {
  Chat: undefined;
  STT: undefined;
  TTS: undefined;
  VoiceAssistant: undefined;
  Settings: undefined;
};

// Common utility types
export type Optional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;
