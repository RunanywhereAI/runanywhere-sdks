export * from './chat';
export * from './model';
export * from './voice';
export * from './settings';

export type RootStackParamList = {
  MainTabs: undefined;
  ConversationList: undefined;
  ChatAnalytics: { messageId?: string } | undefined;
};

export type RootTabParamList = {
  Chat: undefined;
  Vision: undefined;
  More: undefined;
  Settings: undefined;
};

export type MoreStackParamList = {
  MoreHome: undefined;
  STT: undefined;
  TTS: undefined;
  Voice: undefined;
  RAG: undefined;
  Models: undefined;
};

export type VisionStackParamList = {
  VisionHub: undefined;
  VLM: undefined;
};

export type Optional<T, K extends keyof T> = Omit<T, K> & Partial<Pick<T, K>>;
