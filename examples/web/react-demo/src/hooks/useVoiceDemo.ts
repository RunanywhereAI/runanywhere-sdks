import { useState, useEffect, useCallback } from 'react'
// import { useVoicePipeline, type UseVoicePipelineOptions } from '@runanywhere/react'
import type {
  DemoSettings,
  ConversationMessage,
  DemoPerformanceMetrics,

} from '../types/demo.types'

const STORAGE_KEY = 'voice-demo-settings'

const defaultSettings: DemoSettings = {
  apiKey: '',
  sttModel: 'whisper-base',
  llmModel: 'gpt-3.5-turbo',
  ttsVoice: 'jenny',
  language: 'en',
  enableTTS: true,
  enableCaching: true,
  enableAnalytics: true
}

export function useVoiceDemo() {
  // Settings state management
  const [settings, setSettings] = useState<DemoSettings>(() => {
    try {
      const saved = localStorage.getItem(STORAGE_KEY)
      return saved ? { ...defaultSettings, ...JSON.parse(saved) } : defaultSettings
    } catch {
      return defaultSettings
    }
  })

  // UI state
  const [showSettings, setShowSettings] = useState(false)
  const [showMetrics, setShowMetrics] = useState(false)
  const [conversationHistory, setConversationHistory] = useState<ConversationMessage[]>([])
  const [currentTranscript, setCurrentTranscript] = useState('')
  const [currentResponse, setCurrentResponse] = useState('')
  const [audioLevel, setAudioLevel] = useState(0)
  const [performance, setPerformance] = useState<DemoPerformanceMetrics | null>(null)

  // Save settings to localStorage
  useEffect(() => {
    try {
      localStorage.setItem(STORAGE_KEY, JSON.stringify(settings))
    } catch (error) {
      console.warn('Failed to save settings to localStorage:', error)
    }
  }, [settings])

  // Convert demo settings to pipeline options
  // const pipelineOptions: UseVoicePipelineOptions = useMemo(() => ({
  //   // VAD configuration
  //   vad: {
  //     enabled: true,
  //     config: {
  //       threshold: 0.6,
  //       windowSize: 1024,
  //       smoothing: 0.8
  //     }
  //   },
  //   // STT configuration
  //   stt: {
  //     enabled: true,
  //     modelId: settings.sttModel,
  //     language: settings.language
  //   },
  //   // LLM configuration
  //   llm: {
  //     enabled: true,
  //     modelId: settings.llmModel,
  //     systemPrompt: 'You are a helpful voice assistant. Keep responses concise and conversational.',
  //     temperature: 0.7
  //   },
  //   // TTS configuration
  //   tts: {
  //     enabled: settings.enableTTS,
  //     voice: settings.ttsVoice,
  //     speed: 1.0
  //   },
  //   // Performance settings
  //   performance: {
  //     useWebWorkers: true,
  //     bufferSize: 4096,
  //     maxConcurrentOperations: 3
  //   }
  // }), [settings])

  // Mock pipeline state for demo
  const pipelineState = {
    isInitialized: !!settings.apiKey,
    isListening: false,
    isProcessing: false,
    error: null,
    transcription: '',
    llmResponse: '',
    isPlaying: false
  }

  const pipelineActions = {
    initialize: async () => {},
    start: async () => {},
    stop: async () => {},
    pause: async () => {},
    resume: async () => {},
    destroy: () => {}
  }

  // Track performance metrics
  useEffect(() => {
    if (pipelineState.transcription || pipelineState.llmResponse) {
      // Mock performance data - in a real implementation, this would come from the pipeline
      const mockPerformance: DemoPerformanceMetrics = {
        vadLatency: Math.random() * 30 + 20, // 20-50ms
        sttLatency: Math.random() * 200 + 100, // 100-300ms
        llmLatency: Math.random() * 1500 + 500, // 500-2000ms
        ttsLatency: Math.random() * 150 + 100, // 100-250ms
        totalDuration: 0,
        memoryUsage: Math.random() * 200 + 300, // 300-500MB
        modelLoadTime: Math.random() * 5000 + 2000, // 2-7s
      }
      mockPerformance.totalDuration =
        mockPerformance.vadLatency +
        mockPerformance.sttLatency +
        mockPerformance.llmLatency +
        mockPerformance.ttsLatency

      setPerformance(mockPerformance)
    }
  }, [pipelineState.transcription, pipelineState.llmResponse])

  // Handle conversation completion
  useEffect(() => {
    if (pipelineState.transcription && pipelineState.llmResponse) {
      const now = new Date()
      const userMessage: ConversationMessage = {
        id: `user-${now.getTime()}`,
        type: 'user',
        content: pipelineState.transcription,
        timestamp: now,
        duration: performance?.sttLatency
      }

      const assistantMessage: ConversationMessage = {
        id: `assistant-${now.getTime() + 1}`,
        type: 'assistant',
        content: pipelineState.llmResponse,
        timestamp: new Date(now.getTime() + 100),
        duration: performance?.totalDuration
      }

      setConversationHistory(prev => [...prev, userMessage, assistantMessage])
      setCurrentTranscript('')
      setCurrentResponse('')
    }
  }, [pipelineState.transcription, pipelineState.llmResponse, performance])

  // Update current states
  useEffect(() => {
    if (pipelineState.isProcessing && pipelineState.transcription) {
      setCurrentTranscript(pipelineState.transcription)
    }
  }, [pipelineState.isProcessing, pipelineState.transcription])

  useEffect(() => {
    if (pipelineState.llmResponse) {
      setCurrentResponse(pipelineState.llmResponse)
    }
  }, [pipelineState.llmResponse])

  // Mock audio level updates
  useEffect(() => {
    let interval: number | null = null

    if (pipelineState.isListening) {
      interval = setInterval(() => {
        setAudioLevel(Math.random() * 0.8 + 0.1) // 0.1-0.9
      }, 100)
    } else {
      setAudioLevel(0)
    }

    return () => {
      if (interval) clearInterval(interval)
    }
  }, [pipelineState.isListening])

  // Initialize pipeline when settings change (if API key is available)
  useEffect(() => {
    if (settings.apiKey && !pipelineState.isInitialized) {
      pipelineActions.initialize().catch(error => {
        console.error('Failed to initialize voice pipeline:', error)
      })
    }
  }, [settings.apiKey, pipelineState.isInitialized, pipelineActions])

  // Handlers
  const handleSettingsChange = useCallback((newSettings: Partial<DemoSettings>) => {
    setSettings(prev => ({ ...prev, ...newSettings }))
  }, [])

  const openSettings = useCallback(() => setShowSettings(true), [])
  const closeSettings = useCallback(() => setShowSettings(false), [])
  const openMetrics = useCallback(() => setShowMetrics(true), [])
  const closeMetrics = useCallback(() => setShowMetrics(false), [])

  const startConversation = useCallback(async () => {
    if (!pipelineState.isInitialized) {
      await pipelineActions.initialize()
    }
    await pipelineActions.start()
  }, [pipelineState.isInitialized, pipelineActions])

  const stopConversation = useCallback(async () => {
    await pipelineActions.stop()
  }, [pipelineActions])

  const clearConversation = useCallback(() => {
    setConversationHistory([])
    setCurrentTranscript('')
    setCurrentResponse('')
  }, [])

  return {
    // Settings
    settings,
    handleSettingsChange,
    showSettings,
    openSettings,
    closeSettings,

    // Metrics
    showMetrics,
    openMetrics,
    closeMetrics,
    performance,

    // Voice Pipeline State
    isInitialized: pipelineState.isInitialized,
    isActive: pipelineState.isListening,
    isListening: pipelineState.isListening,
    isProcessing: pipelineState.isProcessing,
    isSpeaking: pipelineState.isPlaying,
    error: pipelineState.error,
    currentTranscript,
    currentResponse,
    audioLevel,
    conversationHistory,

    // Actions
    initialize: pipelineActions.initialize,
    startConversation,
    stopConversation,
    clearConversation
  }
}
