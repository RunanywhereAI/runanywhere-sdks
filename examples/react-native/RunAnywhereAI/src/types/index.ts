/**
 * Type Exports
 *
 * Reference: Swift sample app structure
 * Tabs: Chat, STT, TTS, Voice (VoiceAssistant), Settings
 */

// Chat types
export * from './chat';

// Model types
export * from './model';

// Voice types
export * from './voice';

// Settings types
export * from './settings';

// Navigation types - matching Swift sample app (ContentView.swift)
// Tab 0: Chat (LLM)
// Tab 1: Speech-to-Text
// Tab 2: Text-to-Speech
// Tab 3: Voice Assistant (STT + LLM + TTS)
// Tab 4: Settings
export type RootTabParamList = {
  Chat: undefined;
  STT: undefined;
  TTS: undefined;
  Voice: undefined;
  Settings: undefined;
};

// Common utility types
export type Optional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;
