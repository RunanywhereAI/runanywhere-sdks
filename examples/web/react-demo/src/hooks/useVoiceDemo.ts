import { useState, useEffect, useCallback, useMemo } from 'react'
import { useVoicePipeline, type UseVoicePipelineOptions } from '@runanywhere/react'
import type {
  DemoSettings,
  ConversationMessage,
} from '../types/demo.types'
import { demoConfig } from '../services/demoConfig'
import { formatErrorMessage } from '../utils/formatters'

export function useVoiceDemo() {
  // Settings state management using service
  const [settings, setSettings] = useState<DemoSettings>(() => {
    return demoConfig.loadSettings()
  })

  // UI state
  const [showSettings, setShowSettings] = useState(false)
  const [conversationHistory, setConversationHistory] = useState<ConversationMessage[]>([])
  const [currentTranscript, setCurrentTranscript] = useState('')
  const [currentResponse, setCurrentResponse] = useState('')
  const [audioLevel, setAudioLevel] = useState(0)

  // Save settings using service
  useEffect(() => {
    demoConfig.saveSettings(settings)
  }, [settings])

  // Convert demo settings to pipeline options
  const pipelineOptions: UseVoicePipelineOptions = useMemo(() => ({
    enableTranscription: true,
    enableLLM: true,
    enableTTS: true,
    autoPlayTTS: settings.autoPlayTTS,
    whisperConfig: {
      model: settings.whisperModel as 'whisper-tiny' | 'whisper-base' | 'whisper-small'
    },
    llmConfig: {
      apiKey: settings.apiKey,
      baseUrl: settings.llmEndpoint,
      model: settings.llmModel,
      temperature: settings.temperature,
      maxTokens: settings.maxTokens,
      systemPrompt: settings.systemPrompt
    },
    ttsConfig: {
      voice: settings.ttsVoice,
      rate: settings.ttsRate,
      pitch: settings.ttsPitch,
      volume: settings.ttsVolume
    }
  }), [settings])

  // Use the real voice pipeline
  const [pipelineState, pipelineActions] = useVoicePipeline(pipelineOptions)

  // Debug logging
  console.log('useVoiceDemo state:', {
    settings,
    pipelineState,
    hasApiKey: !!settings.apiKey,
    showSettings: showSettings
  });

  // Update transcription history when pipeline detects speech
  useEffect(() => {
    if (pipelineState.transcription) {
      setCurrentTranscript(pipelineState.transcription)
    }
  }, [pipelineState.transcription])

  // Update LLM response history
  useEffect(() => {
    if (pipelineState.llmResponse) {
      setCurrentResponse(pipelineState.llmResponse)

      // Add to conversation history
      const now = Date.now()
      setConversationHistory(prev => [
        ...prev.filter(msg => msg.id !== 'temp-user' && msg.id !== 'temp-assistant'),
        {
          id: `user-${now}`,
          role: 'user',
          content: pipelineState.transcription,
          timestamp: now - 1000
        },
        {
          id: `assistant-${now}`,
          role: 'assistant',
          content: pipelineState.llmResponse,
          timestamp: now
        }
      ])

      // Clear current states
      setCurrentTranscript('')
      setCurrentResponse('')
    }
  }, [pipelineState.llmResponse, pipelineState.transcription])

  // Mock audio level for visual feedback (will be replaced with real VAD levels)
  useEffect(() => {
    let interval: number | null = null

    if (pipelineState.isListening && !pipelineState.isProcessing) {
      interval = setInterval(() => {
        setAudioLevel(Math.random() * 0.8 + 0.1)
      }, 100)
    } else {
      setAudioLevel(0)
    }

    return () => {
      if (interval) clearInterval(interval)
    }
  }, [pipelineState.isListening, pipelineState.isProcessing])

  // Auto-initialize when API key is available
  useEffect(() => {
    if (settings.apiKey && !pipelineState.isInitialized && !pipelineState.error) {
      pipelineActions.initialize().catch(console.error)
    }
  }, [settings.apiKey, pipelineState.isInitialized, pipelineState.error, pipelineActions])

  // Handlers
  const handleSettingsChange = useCallback((newSettings: Partial<DemoSettings>) => {
    setSettings(prev => ({ ...prev, ...newSettings }))
  }, [])

  const openSettings = useCallback(() => {
    console.log('openSettings called, setting showSettings to true');
    setShowSettings(true);
  }, [])
  const closeSettings = useCallback(() => setShowSettings(false), [])

  const startConversation = useCallback(async () => {
    try {
      if (!pipelineState.isInitialized) {
        await pipelineActions.initialize()
      }
      await pipelineActions.start()
    } catch (error: any) {
      console.error('Failed to start conversation:', error)
      throw new Error(formatErrorMessage(error))
    }
  }, [pipelineState.isInitialized, pipelineActions])

  const stopConversation = useCallback(async () => {
    try {
      await pipelineActions.stop()
    } catch (error: any) {
      console.error('Failed to stop conversation:', error)
      throw new Error(formatErrorMessage(error))
    }
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

    // Voice Pipeline State
    isInitialized: pipelineState.isInitialized,
    isActive: pipelineState.isListening || pipelineState.isProcessing,
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
    clearConversation,

    // Additional actions
    pauseConversation: pipelineActions.pause,
    resumeConversation: pipelineActions.resume,
    destroyPipeline: pipelineActions.destroy
  }
}
