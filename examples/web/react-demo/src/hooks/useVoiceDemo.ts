import { useState, useEffect, useCallback } from 'react'
// TODO: import { useVoicePipeline, type UseVoicePipelineOptions } from '@runanywhere/react'
import type {
  DemoSettings,
  ConversationMessage,
  DemoPerformanceMetrics,
} from '../types/demo.types'
import { demoConfig } from '../services/demoConfig'
// TODO: import { metricsService } from '../services/metricsService'
// TODO: import { storageService } from '../services/storageService'
import { formatErrorMessage } from '../utils/formatters'
// TODO: import { STORAGE_KEYS } from '../utils/constants'

export function useVoiceDemo() {
  // Settings state management using service
  const [settings, setSettings] = useState<DemoSettings>(() => {
    return demoConfig.loadSettings()
  })

  // UI state
  const [showSettings, setShowSettings] = useState(false)
  const [showMetrics, setShowMetrics] = useState(false)
  const [conversationHistory, setConversationHistory] = useState<ConversationMessage[]>([])
  const [currentTranscript, setCurrentTranscript] = useState('')
  const [currentResponse, setCurrentResponse] = useState('')
  const [audioLevel, setAudioLevel] = useState(0)
  const [performance, setPerformance] = useState<DemoPerformanceMetrics | null>(null)

  // Save settings using service
  useEffect(() => {
    demoConfig.saveSettings(settings)
  }, [settings])

  // TODO: Convert demo settings to pipeline options when SDK is ready
  // const pipelineOptions = useMemo(() => ({ ... }), [settings])

  // Mock pipeline state and actions for demo (until SDK is integrated)
  const [mockPipelineState, setMockPipelineState] = useState({
    isInitialized: !!settings.apiKey,
    isListening: false,
    isProcessing: false,
    isPlaying: false,
    error: null as Error | null,
    transcription: '',
    llmResponse: '',
    audioLevel: 0,
    performance: null as any
  })

  // Mock pipeline actions
  const initialize = useCallback(async () => {
    console.log('Mock: Initializing voice pipeline...')
    // Simulate initialization delay
    await new Promise(resolve => setTimeout(resolve, 1000))
  }, [])

  const start = useCallback(async () => {
    console.log('Mock: Starting conversation...')
    setMockPipelineState(prev => ({ ...prev, isListening: true }))
  }, [])

  const stop = useCallback(async () => {
    console.log('Mock: Stopping conversation...')
    setMockPipelineState(prev => ({
      ...prev,
      isListening: false,
      isProcessing: false,
      isPlaying: false
    }))
  }, [])

  const pause = useCallback(async () => {
    console.log('Mock: Pausing conversation...')
    setMockPipelineState(prev => ({ ...prev, isListening: false }))
  }, [])

  const resume = useCallback(async () => {
    console.log('Mock: Resuming conversation...')
    setMockPipelineState(prev => ({ ...prev, isListening: true }))
  }, [])

  const destroy = useCallback(() => {
    console.log('Mock: Destroying pipeline...')
    setMockPipelineState({
      isInitialized: false,
      isListening: false,
      isProcessing: false,
      isPlaying: false,
      error: null,
      transcription: '',
      llmResponse: '',
      audioLevel: 0,
      performance: null
    })
  }, [])

  // Mock audio level updates
  useEffect(() => {
    let interval: number | null = null

    if (mockPipelineState.isListening) {
      interval = setInterval(() => {
        setAudioLevel(Math.random() * 0.8 + 0.1) // 0.1-0.9

        // Simulate mock performance data
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
      }, 100)
    } else {
      setAudioLevel(0)
    }

    return () => {
      if (interval) clearInterval(interval)
    }
  }, [mockPipelineState.isListening])

  // Initialize mock pipeline when API key is available
  useEffect(() => {
    if (settings.apiKey && !mockPipelineState.isInitialized) {
      setMockPipelineState(prev => ({ ...prev, isInitialized: true }))
    }
  }, [settings.apiKey, mockPipelineState.isInitialized])

  // Handlers
  const handleSettingsChange = useCallback((newSettings: Partial<DemoSettings>) => {
    setSettings(prev => ({ ...prev, ...newSettings }))
  }, [])

  const openSettings = useCallback(() => setShowSettings(true), [])
  const closeSettings = useCallback(() => setShowSettings(false), [])
  const openMetrics = useCallback(() => setShowMetrics(true), [])
  const closeMetrics = useCallback(() => setShowMetrics(false), [])

  const startConversation = useCallback(async () => {
    try {
      if (!mockPipelineState.isInitialized) {
        await initialize()
      }
      await start()
    } catch (error: any) {
      console.error('Failed to start conversation:', error)
      throw new Error(formatErrorMessage(error))
    }
  }, [mockPipelineState.isInitialized, initialize, start])

  const stopConversation = useCallback(async () => {
    try {
      await stop()
    } catch (error: any) {
      console.error('Failed to stop conversation:', error)
      throw new Error(formatErrorMessage(error))
    }
  }, [stop])

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
    isInitialized: mockPipelineState.isInitialized,
    isActive: mockPipelineState.isListening || mockPipelineState.isProcessing,
    isListening: mockPipelineState.isListening,
    isProcessing: mockPipelineState.isProcessing,
    isSpeaking: mockPipelineState.isPlaying,
    error: mockPipelineState.error,
    currentTranscript,
    currentResponse,
    audioLevel,
    conversationHistory,

    // Actions
    initialize,
    startConversation,
    stopConversation,
    clearConversation,

    // Additional actions
    pauseConversation: pause,
    resumeConversation: resume,
    destroyPipeline: destroy
  }
}
