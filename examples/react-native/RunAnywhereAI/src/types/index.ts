/**
 * Type Exports
 *
 * Reference: Swift sample app structure
 * Tabs: Chat, Vision, Voice, More, Settings
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
// Tab 0: Chat
// Tab 1: Vision
// Tab 2: Voice
// Tab 3: More
// Tab 4: Settings
export type RootTabParamList = {
  Chat: undefined;
  Vision: undefined;
  Voice: undefined;
  More: undefined;
  Settings: undefined;
};

/** Vision tab stack: hub list -> VLM */
export type VisionStackParamList = {
  VisionHub: undefined;
  VLM: undefined;
};

export type MoreStackParamList = {
  MoreHome: undefined;
  STT: undefined;
  TTS: undefined;
  RAG: undefined;
  VAD: undefined;
  Storage: undefined;
  Solutions: undefined;
};

/**
 * Settings tab stack: settings home -> Benchmarks
 * (mirrors iOS CombinedSettingsView -> BenchmarkDashboardView)
 */
export type SettingsStackParamList = {
  SettingsHome: undefined;
  Benchmarks: undefined;
};

// Common utility types
export type Optional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;
