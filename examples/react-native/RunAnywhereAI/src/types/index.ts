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
// Tab 0: Food (AI Food Ordering Demo - DoorDash Clone)
// Tab 1: Chat (LLM)
// Tab 2: Speech-to-Text
// Tab 3: Text-to-Speech
// Tab 4: Voice Assistant (STT + LLM + TTS)
// Tab 5: Tools (Tool Calling Demo)
// Tab 6: Settings
export type RootTabParamList = {
  Food: undefined;
  Chat: undefined;
  STT: undefined;
  TTS: undefined;
  Voice: undefined;
  Tools: undefined;
  Settings: undefined;
};

// Common utility types
export type Optional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;
