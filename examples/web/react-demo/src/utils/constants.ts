/**
 * Application constants for the voice demo
 */

// Application metadata
export const APP_NAME = 'RunAnywhere Voice Demo'
export const APP_VERSION = '1.0.0'
export const APP_DESCRIPTION = 'Ultra-low latency voice AI in your browser'

// Storage keys
export const STORAGE_KEYS = {
  SETTINGS: 'voice-demo-settings',
  METRICS_HISTORY: 'voice-demo-metrics-history',
  CONVERSATION_HISTORY: 'voice-demo-conversations',
  USER_PREFERENCES: 'voice-demo-preferences',
  CACHE_MANIFEST: 'voice-demo-cache-manifest'
} as const

// API configuration
export const API_CONFIG = {
  OPENAI_BASE_URL: 'https://api.openai.com/v1',
  TIMEOUT_MS: 30000,
  MAX_RETRIES: 3,
  RETRY_DELAY_MS: 1000
} as const

// Model configurations
export const MODEL_CONFIG = {
  STT: {
    WHISPER_TINY: {
      id: 'whisper-tiny',
      size: 39 * 1024 * 1024, // 39MB
      memoryEstimate: 100 * 1024 * 1024, // 100MB runtime
      latencyTarget: 150 // ms
    },
    WHISPER_BASE: {
      id: 'whisper-base',
      size: 74 * 1024 * 1024, // 74MB
      memoryEstimate: 200 * 1024 * 1024, // 200MB runtime
      latencyTarget: 300 // ms
    },
    WHISPER_SMALL: {
      id: 'whisper-small',
      size: 244 * 1024 * 1024, // 244MB
      memoryEstimate: 400 * 1024 * 1024, // 400MB runtime
      latencyTarget: 500 // ms
    }
  },
  TTS: {
    ONNX_VOICES: {
      JENNY: { id: 'jenny', sampleRate: 22050, quality: 'high' },
      RYAN: { id: 'ryan', sampleRate: 22050, quality: 'high' },
      SARA: { id: 'sara', sampleRate: 22050, quality: 'high' },
      MARK: { id: 'mark', sampleRate: 22050, quality: 'high' }
    }
  }
} as const

// Performance targets and thresholds
export const PERFORMANCE_TARGETS = {
  // Individual component targets (ms)
  VAD_LATENCY_TARGET: 30,
  STT_LATENCY_TARGET: 300,
  LLM_LATENCY_TARGET: 1500,
  TTS_LATENCY_TARGET: 200,

  // End-to-end targets
  TOTAL_LATENCY_TARGET: 500,
  TOTAL_LATENCY_ACCEPTABLE: 1000,

  // Memory targets
  MEMORY_TARGET_MB: 400,
  MEMORY_LIMIT_MB: 800,

  // Quality targets
  STT_CONFIDENCE_MIN: 0.7,
  AUDIO_LEVEL_MIN: 0.1,
  AUDIO_LEVEL_MAX: 0.9
} as const

// UI constants
export const UI_CONFIG = {
  // Animation durations (ms)
  ANIMATION_FAST: 150,
  ANIMATION_NORMAL: 300,
  ANIMATION_SLOW: 500,

  // Breakpoints (px)
  BREAKPOINTS: {
    SM: 640,
    MD: 768,
    LG: 1024,
    XL: 1280
  },

  // Z-index layers
  Z_INDEX: {
    DROPDOWN: 10,
    STICKY: 20,
    MODAL: 50,
    TOOLTIP: 100
  },

  // Component sizes
  VOICE_BUTTON_SIZE: 96, // px
  METRICS_CARD_HEIGHT: 120, // px
  CONVERSATION_MAX_HEIGHT: 400, // px

  // Colors for status indicators
  STATUS_COLORS: {
    GOOD: '#10B981', // green-500
    WARNING: '#F59E0B', // amber-500
    ERROR: '#EF4444' // red-500
  }
} as const

// Audio configuration
export const AUDIO_CONFIG = {
  // Sample rates (Hz)
  SAMPLE_RATE_INPUT: 16000,
  SAMPLE_RATE_OUTPUT: 22050,

  // Buffer sizes
  INPUT_BUFFER_SIZE: 4096,
  OUTPUT_BUFFER_SIZE: 2048,

  // VAD settings
  VAD_WINDOW_SIZE: 1024,
  VAD_HOP_LENGTH: 512,
  VAD_THRESHOLD_DEFAULT: 0.6,

  // Audio levels
  SILENCE_THRESHOLD: 0.01,
  NOISE_GATE_THRESHOLD: 0.05,
  MAX_AMPLITUDE: 1.0
} as const

// Conversation settings
export const CONVERSATION_CONFIG = {
  MAX_HISTORY_LENGTH: 50,
  MAX_MESSAGE_LENGTH: 500,
  TYPING_SPEED_MS: 30,

  // Context management
  MAX_CONTEXT_TOKENS: 2000,
  CONTEXT_OVERLAP_TOKENS: 200,

  // Auto-save settings
  AUTOSAVE_INTERVAL_MS: 5000,
  MAX_AUTOSAVES: 10
} as const

// Network and caching
export const NETWORK_CONFIG = {
  // Request timeouts (ms)
  REQUEST_TIMEOUT: 30000,
  STREAMING_TIMEOUT: 60000,

  // Retry configuration
  MAX_RETRIES: 3,
  RETRY_BACKOFF_BASE: 1000,
  RETRY_BACKOFF_MAX: 10000,

  // Cache settings
  CACHE_MAX_AGE: 24 * 60 * 60 * 1000, // 24 hours
  CACHE_MAX_SIZE: 100 * 1024 * 1024, // 100MB

  // Connection types for optimization
  CONNECTION_TYPES: {
    SLOW_2G: 'slow-2g',
    FAST_3G: '3g',
    FAST_4G: '4g'
  }
} as const

// Error codes and messages
export const ERROR_CODES = {
  // Authentication errors
  INVALID_API_KEY: 'INVALID_API_KEY',
  API_KEY_MISSING: 'API_KEY_MISSING',

  // Network errors
  NETWORK_ERROR: 'NETWORK_ERROR',
  TIMEOUT_ERROR: 'TIMEOUT_ERROR',

  // Audio errors
  MICROPHONE_ERROR: 'MICROPHONE_ERROR',
  AUDIO_CONTEXT_ERROR: 'AUDIO_CONTEXT_ERROR',

  // Model errors
  MODEL_LOAD_ERROR: 'MODEL_LOAD_ERROR',
  MODEL_INFERENCE_ERROR: 'MODEL_INFERENCE_ERROR',

  // Generic errors
  UNKNOWN_ERROR: 'UNKNOWN_ERROR',
  INITIALIZATION_ERROR: 'INITIALIZATION_ERROR'
} as const

export const ERROR_MESSAGES: Record<keyof typeof ERROR_CODES, string> = {
  INVALID_API_KEY: 'Invalid OpenAI API key. Please check your key in settings.',
  API_KEY_MISSING: 'OpenAI API key is required. Please add it in settings.',
  NETWORK_ERROR: 'Network error. Please check your internet connection.',
  TIMEOUT_ERROR: 'Request timed out. Please try again.',
  MICROPHONE_ERROR: 'Unable to access microphone. Please check permissions.',
  AUDIO_CONTEXT_ERROR: 'Audio system error. Please refresh the page.',
  MODEL_LOAD_ERROR: 'Failed to load AI model. Please try again.',
  MODEL_INFERENCE_ERROR: 'AI model processing error. Please try again.',
  UNKNOWN_ERROR: 'An unexpected error occurred.',
  INITIALIZATION_ERROR: 'Failed to initialize voice system.'
}

// Feature flags
export const FEATURE_FLAGS = {
  // Core features
  ENABLE_VAD: true,
  ENABLE_STT: true,
  ENABLE_LLM: true,
  ENABLE_TTS: true,

  // Advanced features
  ENABLE_STREAMING: true,
  ENABLE_INTERRUPTION: true,
  ENABLE_BACKGROUND_PROCESSING: true,

  // Experimental features
  ENABLE_VOICE_CLONING: false,
  ENABLE_EMOTION_DETECTION: false,
  ENABLE_MULTI_SPEAKER: false,

  // Debug features
  ENABLE_PERFORMANCE_LOGGING: true,
  ENABLE_DEBUG_UI: false,
  ENABLE_MOCK_MODE: false
} as const

// Keyboard shortcuts
export const KEYBOARD_SHORTCUTS = {
  TOGGLE_RECORDING: 'Space',
  OPEN_SETTINGS: 'KeyS',
  OPEN_METRICS: 'KeyM',
  CLEAR_CONVERSATION: 'KeyC',
  FOCUS_SEARCH: 'KeyF'
} as const

// WebAssembly configuration
export const WASM_CONFIG = {
  REQUIRED_FEATURES: [
    'WebAssembly',
    'SharedArrayBuffer',
    'WebAssembly.instantiateStreaming'
  ],
  MEMORY_INITIAL_PAGES: 256, // 16MB
  MEMORY_MAXIMUM_PAGES: 2048, // 128MB
  ENABLE_SIMD: true,
  ENABLE_THREADS: true
} as const

// Browser compatibility
export const BROWSER_REQUIREMENTS = {
  CHROME: 90,
  FIREFOX: 90,
  SAFARI: 15,
  EDGE: 90
} as const

// Analytics events (if analytics are enabled)
export const ANALYTICS_EVENTS = {
  // User actions
  CONVERSATION_STARTED: 'conversation_started',
  CONVERSATION_ENDED: 'conversation_ended',
  MESSAGE_SENT: 'message_sent',
  SETTINGS_CHANGED: 'settings_changed',

  // Performance events
  MODEL_LOADED: 'model_loaded',
  INFERENCE_COMPLETED: 'inference_completed',
  ERROR_OCCURRED: 'error_occurred',

  // Feature usage
  FEATURE_USED: 'feature_used',
  SHORTCUT_USED: 'shortcut_used'
} as const
