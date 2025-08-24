/**
 * Demo-specific type definitions for the React Voice Demo
 */

export interface DemoSettings {
  apiKey: string
  sttModel: 'whisper-tiny' | 'whisper-base' | 'whisper-small'
  llmModel: 'gpt-3.5-turbo' | 'gpt-4' | 'gpt-4-turbo'
  ttsVoice: 'jenny' | 'ryan' | 'sara' | 'mark'
  language: 'en' | 'es' | 'fr' | 'de' | 'it' | 'pt' | 'ru' | 'ja' | 'ko' | 'zh'
  enableTTS: boolean
  enableCaching: boolean
  // Additional pipeline config
  whisperModel: 'whisper-tiny' | 'whisper-base' | 'whisper-small'
  llmEndpoint: string
  temperature: number
  maxTokens: number
  systemPrompt: string
  autoPlayTTS: boolean
  ttsRate: number
  ttsPitch: number
  ttsVolume: number
}

export interface ConversationMessage {
  id: string
  role: 'user' | 'assistant'
  content: string
  timestamp: number
}

export interface DemoState {
  isInitialized: boolean
  isActive: boolean
  isListening: boolean
  isProcessing: boolean
  isSpeaking: boolean
  error: Error | null
  currentTranscript: string
  currentResponse: string
  audioLevel: number
  conversationHistory: ConversationMessage[]
}

export interface ModelInfo {
  name: string
  size: string
  description: string
  speed: 'fast' | 'balanced' | 'quality'
  memoryUsage: string
  supported: boolean
}

export interface VoiceInfo {
  id: string
  name: string
  gender: 'male' | 'female'
  accent: string
  description: string
  sampleRate: number
}

export interface LanguageInfo {
  code: string
  name: string
  nativeName: string
  supported: boolean
  rtlScript?: boolean
}

export const SUPPORTED_STT_MODELS: Record<DemoSettings['sttModel'], ModelInfo> = {
  'whisper-tiny': {
    name: 'Whisper Tiny',
    size: '39MB',
    description: 'Fastest processing, good for quick demos',
    speed: 'fast',
    memoryUsage: '~100MB',
    supported: true
  },
  'whisper-base': {
    name: 'Whisper Base',
    size: '74MB',
    description: 'Balanced speed and accuracy',
    speed: 'balanced',
    memoryUsage: '~200MB',
    supported: true
  },
  'whisper-small': {
    name: 'Whisper Small',
    size: '244MB',
    description: 'Best accuracy, slower processing',
    speed: 'quality',
    memoryUsage: '~400MB',
    supported: true
  }
}

export const SUPPORTED_VOICES: Record<DemoSettings['ttsVoice'], VoiceInfo> = {
  jenny: {
    id: 'jenny',
    name: 'Jenny',
    gender: 'female',
    accent: 'US English',
    description: 'Clear, professional female voice',
    sampleRate: 22050
  },
  ryan: {
    id: 'ryan',
    name: 'Ryan',
    gender: 'male',
    accent: 'US English',
    description: 'Natural, conversational male voice',
    sampleRate: 22050
  },
  sara: {
    id: 'sara',
    name: 'Sara',
    gender: 'female',
    accent: 'UK English',
    description: 'Refined British female voice',
    sampleRate: 22050
  },
  mark: {
    id: 'mark',
    name: 'Mark',
    gender: 'male',
    accent: 'UK English',
    description: 'Authoritative British male voice',
    sampleRate: 22050
  }
}

export const SUPPORTED_LANGUAGES: Record<DemoSettings['language'], LanguageInfo> = {
  en: { code: 'en', name: 'English', nativeName: 'English', supported: true },
  es: { code: 'es', name: 'Spanish', nativeName: 'Español', supported: true },
  fr: { code: 'fr', name: 'French', nativeName: 'Français', supported: true },
  de: { code: 'de', name: 'German', nativeName: 'Deutsch', supported: true },
  it: { code: 'it', name: 'Italian', nativeName: 'Italiano', supported: true },
  pt: { code: 'pt', name: 'Portuguese', nativeName: 'Português', supported: true },
  ru: { code: 'ru', name: 'Russian', nativeName: 'Русский', supported: true, rtlScript: false },
  ja: { code: 'ja', name: 'Japanese', nativeName: '日本語', supported: true },
  ko: { code: 'ko', name: 'Korean', nativeName: '한국어', supported: true },
  zh: { code: 'zh', name: 'Chinese', nativeName: '中文', supported: true }
}

export const DEFAULT_DEMO_SETTINGS: DemoSettings = {
  apiKey: '',
  sttModel: 'whisper-base',
  llmModel: 'gpt-3.5-turbo',
  ttsVoice: 'jenny',
  language: 'en',
  enableTTS: true,
  enableCaching: true,
  // Additional pipeline config
  whisperModel: 'whisper-base',
  llmEndpoint: 'https://api.openai.com/v1',
  temperature: 0.7,
  maxTokens: 500,
  systemPrompt: 'You are a helpful voice assistant.',
  autoPlayTTS: true,
  ttsRate: 1.0,
  ttsPitch: 1.0,
  ttsVolume: 1.0
}
