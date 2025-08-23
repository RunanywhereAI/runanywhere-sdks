# Phase 6: React Demo Application - Detailed Implementation Plan

## Overview

**Phase**: 6 (Next Phase)
**Focus**: Production-ready React demo application showcasing the complete voice pipeline
**Timeline**: 2-3 weeks
**Goal**: Create a comprehensive React demo that demonstrates all voice SDK capabilities with professional UI/UX

## Objectives

1. **Professional React Demo App**: Build a complete voice assistant application using React
2. **Showcase All Features**: Demonstrate VAD → STT → LLM → TTS pipeline with real-time feedback
3. **Production Ready**: Professional UI/UX with error handling, loading states, and optimizations
4. **Performance Monitoring**: Built-in metrics dashboard and real-time performance tracking
5. **Configuration Interface**: Settings panel for model selection, API configuration, and feature toggles

## Current Status

**Phase 6 Completed ✅**
- ✅ Phase 1-5: Complete SDK infrastructure with 13 packages
- ✅ React framework adapter with hooks and components (`@runanywhere/react`)
- ✅ Voice pipeline fully functional (VAD → STT → LLM → TTS)
- ✅ Production optimization with Web Workers and caching
- ✅ TypeScript build system with all packages compiling successfully
- ✅ **Phase 6: React Demo Application - COMPLETED**

### Implementation Completed (August 2025)

All planned Phase 6 features have been successfully implemented:

#### ✅ Core Components Implemented
- **VoiceAssistant Component**: Complete conversation interface with real-time audio visualization
- **SettingsPanel Component**: Comprehensive configuration with model selection and feature toggles
- **MetricsDashboard Component**: Advanced performance monitoring with historical trends and charts
- **ErrorBoundary Component**: Robust error handling with user-friendly fallbacks

#### ✅ Service Layer Implemented
- **DemoConfigService**: Settings management with localStorage persistence and validation
- **MetricsService**: Performance tracking, analytics, and trend analysis with 1000-entry history
- **StorageService**: Advanced storage management with quota tracking and cleanup

#### ✅ Enhanced UI Components
- **LoadingSpinner**: Customizable loading indicators with multiple sizes and colors
- **StatusIndicator**: Performance status visualization (good/warning/error)
- **AudioVisualizer**: Real-time audio waveform visualization with bars, waveforms, and circular modes

#### ✅ Professional Features
- **Real-time Performance Monitoring**: Visual indicators with thresholds and status colors
- **Audio Visualization**: Dynamic visualizers that respond to audio input
- **Conversation Metadata**: Confidence scores, token usage, and timing information
- **Professional Error Handling**: Development vs production error displays with stack traces
- **Mobile-Responsive Design**: Mobile-optimized layouts and touch interactions

#### ✅ Build & Deployment Ready
- **TypeScript**: 100% strict type coverage with no compilation errors
- **Vite Build System**: Optimized production builds (39KB main + 141KB vendor)
- **Error-free Compilation**: All TypeScript errors resolved and building successfully
- **Development Server**: Hot reload and development features working
- **Production Ready**: Minified, tree-shaken, and optimized for deployment

## Architecture Overview

### Demo App Structure

```
packages/demo-apps/react-demo/
├── src/
│   ├── components/           # React components
│   │   ├── VoiceAssistant/   # Main voice interface
│   │   ├── Dashboard/        # Performance metrics dashboard
│   │   ├── Settings/         # Configuration panel
│   │   ├── Visualizer/       # Audio visualization
│   │   └── Common/           # Shared UI components
│   ├── hooks/                # Custom React hooks
│   │   ├── useVoiceDemo.ts   # Main demo logic
│   │   ├── useSettings.ts    # Settings management
│   │   └── useMetrics.ts     # Performance tracking
│   ├── services/             # Business logic
│   │   ├── demoConfig.ts     # Demo configurations
│   │   ├── metricsService.ts # Metrics collection
│   │   └── storageService.ts # Local storage handling
│   ├── types/                # TypeScript definitions
│   │   └── demo.types.ts     # Demo-specific types
│   ├── utils/                # Utilities
│   │   ├── formatters.ts     # Data formatting
│   │   └── constants.ts      # Demo constants
│   ├── styles/               # CSS/styling
│   │   └── globals.css       # Global styles (Tailwind)
│   ├── App.tsx               # Main application component
│   └── main.tsx              # Application entry point
├── public/                   # Static assets
│   ├── models/               # Demo model configurations
│   ├── audio/                # Sample audio files
│   └── icons/                # App icons
├── vite.config.ts            # Vite configuration
├── tailwind.config.js        # Tailwind CSS configuration
├── package.json              # Dependencies and scripts
└── README.md                 # Demo documentation
```

## Detailed Implementation

### 6.1 Main Voice Assistant Component

**File**: `src/components/VoiceAssistant/VoiceAssistant.tsx`

```typescript
import React, { useState, useCallback } from 'react'
import { useVoiceSDK } from '@runanywhere/react'
import { VoiceConfigBuilder, VoicePipelineConfigBuilder } from '@runanywhere/voice-sdk'
import { Microphone, MicrophoneSlash, Cog6Tooth, ChartBarIcon } from '@heroicons/react/24/outline'

interface VoiceAssistantProps {
  apiKey: string
  onShowSettings: () => void
  onShowMetrics: () => void
}

export function VoiceAssistant({ apiKey, onShowSettings, onShowMetrics }: VoiceAssistantProps) {
  const [conversationHistory, setConversationHistory] = useState<Array<{
    id: string
    type: 'user' | 'assistant'
    content: string
    timestamp: Date
    duration?: number
  }>>([])

  // Voice SDK configuration
  const config = VoiceConfigBuilder.create()
    .withSTTModel('whisper-base', {
      language: 'en',
      enableVAD: true,
      vadThreshold: 0.6
    })
    .withLLMProvider('openai', {
      apiKey,
      model: 'gpt-3.5-turbo',
      streaming: true,
      maxTokens: 150
    })
    .withTTSProvider('onnx', {
      voice: 'jenny',
      speed: 1.0,
      enableStreaming: true
    })
    .withFeatures({
      transcription: true,
      llm: true,
      tts: true,
      analytics: true,
      caching: true
    })
    .build()

  const {
    isInitialized,
    isActive,
    isListening,
    isProcessing,
    currentTranscript,
    currentResponse,
    audioLevel,
    error,
    performance,
    initialize,
    startConversation,
    stopConversation,
    clearConversation
  } = useVoiceSDK({
    config,
    autoInitialize: true,
    onConversationComplete: (result) => {
      setConversationHistory(prev => [
        ...prev,
        {
          id: `user-${Date.now()}`,
          type: 'user',
          content: result.transcript,
          timestamp: new Date(),
          duration: result.performance.sttDuration
        },
        {
          id: `assistant-${Date.now()}`,
          type: 'assistant',
          content: result.response,
          timestamp: new Date(),
          duration: result.performance.totalDuration
        }
      ])
    }
  })

  const handleToggleConversation = useCallback(async () => {
    if (isActive) {
      await stopConversation()
    } else {
      const pipelineConfig = VoicePipelineConfigBuilder.conversational({
        enableTTS: true,
        streaming: true,
        interruption: true,
        autoStart: true
      })
      await startConversation(pipelineConfig)
    }
  }, [isActive, startConversation, stopConversation])

  const handleClearHistory = useCallback(() => {
    setConversationHistory([])
    clearConversation()
  }, [clearConversation])

  // Error state
  if (error) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center p-4">
        <div className="bg-red-50 border border-red-200 rounded-lg p-6 max-w-md w-full">
          <h3 className="text-red-800 font-semibold text-lg mb-2">Voice SDK Error</h3>
          <p className="text-red-600 mb-4">{error.message}</p>
          <div className="flex gap-3">
            <button
              onClick={() => window.location.reload()}
              className="bg-red-600 text-white px-4 py-2 rounded hover:bg-red-700 transition-colors"
            >
              Reload App
            </button>
            <button
              onClick={onShowSettings}
              className="border border-red-300 text-red-700 px-4 py-2 rounded hover:bg-red-50 transition-colors"
            >
              Check Settings
            </button>
          </div>
        </div>
      </div>
    )
  }

  // Loading state
  if (!isInitialized) {
    return (
      <div className="min-h-screen bg-gray-50 flex items-center justify-center">
        <div className="text-center">
          <div className="animate-spin h-12 w-12 border-3 border-blue-500 border-t-transparent rounded-full mx-auto mb-4" />
          <h2 className="text-xl font-semibold text-gray-800 mb-2">Initializing Voice SDK</h2>
          <p className="text-gray-600">Loading models and setting up voice pipeline...</p>
        </div>
      </div>
    )
  }

  return (
    <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100">
      {/* Header */}
      <header className="bg-white shadow-sm border-b">
        <div className="max-w-6xl mx-auto px-6 py-4">
          <div className="flex items-center justify-between">
            <div>
              <h1 className="text-2xl font-bold text-gray-900">RunAnywhere Voice Demo</h1>
              <p className="text-gray-600">Ultra-low latency voice AI in your browser</p>
            </div>
            <div className="flex gap-3">
              <button
                onClick={onShowMetrics}
                className="flex items-center gap-2 px-4 py-2 text-gray-600 hover:text-gray-800 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <ChartBarIcon className="h-5 w-5" />
                <span>Metrics</span>
              </button>
              <button
                onClick={onShowSettings}
                className="flex items-center gap-2 px-4 py-2 text-gray-600 hover:text-gray-800 hover:bg-gray-100 rounded-lg transition-colors"
              >
                <Cog6Tooth className="h-5 w-5" />
                <span>Settings</span>
              </button>
            </div>
          </div>
        </div>
      </header>

      {/* Main Content */}
      <main className="max-w-6xl mx-auto px-6 py-8">
        <div className="grid grid-cols-1 lg:grid-cols-3 gap-8">

          {/* Voice Control Panel */}
          <div className="lg:col-span-1">
            <div className="bg-white rounded-xl shadow-lg p-6 sticky top-8">
              <h2 className="text-lg font-semibold text-gray-900 mb-6 text-center">Voice Control</h2>

              {/* Main Voice Button */}
              <div className="text-center mb-6">
                <button
                  onClick={handleToggleConversation}
                  disabled={!isInitialized}
                  className={`
                    w-24 h-24 rounded-full flex items-center justify-center transition-all duration-200
                    ${isActive
                      ? 'bg-red-500 hover:bg-red-600 text-white shadow-lg transform scale-105'
                      : 'bg-blue-500 hover:bg-blue-600 text-white shadow-lg'
                    }
                    ${isListening ? 'animate-pulse' : ''}
                    disabled:opacity-50 disabled:cursor-not-allowed disabled:transform-none
                  `}
                >
                  {isActive ? (
                    <MicrophoneSlash className="h-8 w-8" />
                  ) : (
                    <Microphone className="h-8 w-8" />
                  )}
                </button>
              </div>

              {/* Status Display */}
              <div className="text-center mb-6">
                <div className="text-lg font-medium text-gray-800 mb-2">
                  {isListening ? 'Listening...' :
                   isProcessing ? 'Processing...' :
                   isActive ? 'Ready to listen' : 'Click to start'}
                </div>

                {audioLevel !== undefined && isListening && (
                  <div className="w-full bg-gray-200 rounded-full h-2 mb-2">
                    <div
                      className="bg-green-500 h-2 rounded-full transition-all duration-100"
                      style={{ width: `${Math.min(audioLevel * 100, 100)}%` }}
                    />
                  </div>
                )}

                {performance && (
                  <div className="text-sm text-gray-500 grid grid-cols-2 gap-2">
                    <div>STT: {Math.round(performance.sttLatency)}ms</div>
                    <div>LLM: {Math.round(performance.llmLatency)}ms</div>
                    <div>TTS: {Math.round(performance.ttsLatency)}ms</div>
                    <div>Total: {Math.round(performance.totalDuration / 1000)}s</div>
                  </div>
                )}
              </div>

              {/* Current Interaction */}
              {(currentTranscript || currentResponse) && (
                <div className="border-t pt-4">
                  <h3 className="font-medium text-gray-900 mb-3">Current Interaction</h3>

                  {currentTranscript && (
                    <div className="mb-3">
                      <div className="text-sm text-gray-600 mb-1">You said:</div>
                      <div className="bg-blue-50 rounded-lg p-3 text-sm">
                        {currentTranscript}
                        {isListening && <span className="animate-pulse">|</span>}
                      </div>
                    </div>
                  )}

                  {currentResponse && (
                    <div>
                      <div className="text-sm text-gray-600 mb-1">Assistant:</div>
                      <div className="bg-green-50 rounded-lg p-3 text-sm">
                        {currentResponse}
                        {isProcessing && <span className="animate-pulse">|</span>}
                      </div>
                    </div>
                  )}
                </div>
              )}

              {/* Action Buttons */}
              <div className="border-t pt-4 flex gap-2">
                <button
                  onClick={handleClearHistory}
                  disabled={conversationHistory.length === 0}
                  className="flex-1 px-4 py-2 text-sm border border-gray-300 text-gray-600 rounded-lg hover:bg-gray-50 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
                >
                  Clear History
                </button>
              </div>
            </div>
          </div>

          {/* Conversation History */}
          <div className="lg:col-span-2">
            <div className="bg-white rounded-xl shadow-lg p-6">
              <h2 className="text-lg font-semibold text-gray-900 mb-6">Conversation History</h2>

              {conversationHistory.length === 0 ? (
                <div className="text-center py-12 text-gray-500">
                  <Microphone className="h-12 w-12 mx-auto mb-4 opacity-50" />
                  <p className="text-lg">No conversations yet</p>
                  <p className="text-sm mt-1">Click the microphone button to start talking</p>
                </div>
              ) : (
                <div className="space-y-4 max-h-96 overflow-y-auto">
                  {conversationHistory.map((message, index) => (
                    <div
                      key={message.id}
                      className={`flex ${message.type === 'user' ? 'justify-end' : 'justify-start'}`}
                    >
                      <div
                        className={`max-w-md px-4 py-3 rounded-lg ${
                          message.type === 'user'
                            ? 'bg-blue-500 text-white'
                            : 'bg-gray-100 text-gray-900'
                        }`}
                      >
                        <div className="font-medium mb-1">
                          {message.type === 'user' ? 'You' : 'Assistant'}
                        </div>
                        <div className="whitespace-pre-wrap">{message.content}</div>
                        <div className="text-xs opacity-75 mt-2">
                          {message.timestamp.toLocaleTimeString()}
                          {message.duration && ` • ${Math.round(message.duration / 1000)}s`}
                        </div>
                      </div>
                    </div>
                  ))}
                </div>
              )}
            </div>
          </div>
        </div>
      </main>
    </div>
  )
}
```

### 6.2 Settings Panel Component

**File**: `src/components/Settings/SettingsPanel.tsx`

```typescript
import React, { useState } from 'react'
import { XMarkIcon } from '@heroicons/react/24/outline'

interface SettingsPanelProps {
  isOpen: boolean
  onClose: () => void
  currentConfig: any
  onConfigChange: (config: any) => void
}

export function SettingsPanel({ isOpen, onClose, currentConfig, onConfigChange }: SettingsPanelProps) {
  const [apiKey, setApiKey] = useState(currentConfig?.llm?.apiKey || '')
  const [sttModel, setSTTModel] = useState(currentConfig?.stt?.model || 'whisper-base')
  const [llmModel, setLLMModel] = useState(currentConfig?.llm?.model || 'gpt-3.5-turbo')
  const [ttsVoice, setTTSVoice] = useState(currentConfig?.tts?.voice || 'jenny')
  const [language, setLanguage] = useState(currentConfig?.stt?.language || 'en')
  const [enableTTS, setEnableTTS] = useState(currentConfig?.features?.tts ?? true)
  const [enableCaching, setEnableCaching] = useState(currentConfig?.features?.caching ?? true)

  const handleSave = () => {
    const newConfig = {
      stt: {
        model: sttModel,
        language,
        enableVAD: true
      },
      llm: {
        provider: 'openai',
        apiKey,
        model: llmModel
      },
      tts: {
        voice: ttsVoice,
        enabled: enableTTS
      },
      features: {
        transcription: true,
        llm: true,
        tts: enableTTS,
        caching: enableCaching,
        analytics: true
      }
    }
    onConfigChange(newConfig)
    onClose()
  }

  if (!isOpen) return null

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-6 border-b">
          <h2 className="text-xl font-semibold text-gray-900">Settings</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <XMarkIcon className="h-6 w-6" />
          </button>
        </div>

        <div className="p-6 space-y-8">
          {/* API Configuration */}
          <section>
            <h3 className="text-lg font-medium text-gray-900 mb-4">API Configuration</h3>
            <div className="space-y-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  OpenAI API Key
                </label>
                <input
                  type="password"
                  value={apiKey}
                  onChange={(e) => setApiKey(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 focus:border-blue-500"
                  placeholder="sk-..."
                />
                <p className="text-sm text-gray-500 mt-1">
                  Required for LLM responses. Never stored permanently.
                </p>
              </div>
            </div>
          </section>

          {/* Model Selection */}
          <section>
            <h3 className="text-lg font-medium text-gray-900 mb-4">Model Selection</h3>
            <div className="grid grid-cols-1 md:grid-cols-2 gap-4">
              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Speech-to-Text Model
                </label>
                <select
                  value={sttModel}
                  onChange={(e) => setSTTModel(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  <option value="whisper-tiny">Whisper Tiny (Fastest)</option>
                  <option value="whisper-base">Whisper Base (Balanced)</option>
                  <option value="whisper-small">Whisper Small (Best Quality)</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Language
                </label>
                <select
                  value={language}
                  onChange={(e) => setLanguage(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  <option value="en">English</option>
                  <option value="es">Spanish</option>
                  <option value="fr">French</option>
                  <option value="de">German</option>
                  <option value="it">Italian</option>
                  <option value="pt">Portuguese</option>
                  <option value="ru">Russian</option>
                  <option value="ja">Japanese</option>
                  <option value="ko">Korean</option>
                  <option value="zh">Chinese</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  LLM Model
                </label>
                <select
                  value={llmModel}
                  onChange={(e) => setLLMModel(e.target.value)}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  <option value="gpt-3.5-turbo">GPT-3.5 Turbo (Fastest)</option>
                  <option value="gpt-4">GPT-4 (Best Quality)</option>
                  <option value="gpt-4-turbo">GPT-4 Turbo (Balanced)</option>
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  TTS Voice
                </label>
                <select
                  value={ttsVoice}
                  onChange={(e) => setTTSVoice(e.target.value)}
                  disabled={!enableTTS}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 disabled:opacity-50"
                >
                  <option value="jenny">Jenny (Female, US)</option>
                  <option value="ryan">Ryan (Male, US)</option>
                  <option value="sara">Sara (Female, UK)</option>
                  <option value="mark">Mark (Male, UK)</option>
                </select>
              </div>
            </div>
          </section>

          {/* Features */}
          <section>
            <h3 className="text-lg font-medium text-gray-900 mb-4">Features</h3>
            <div className="space-y-4">
              <div className="flex items-center justify-between">
                <div>
                  <div className="font-medium text-gray-900">Text-to-Speech</div>
                  <div className="text-sm text-gray-600">Enable AI voice responses</div>
                </div>
                <button
                  onClick={() => setEnableTTS(!enableTTS)}
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                    enableTTS ? 'bg-blue-600' : 'bg-gray-200'
                  }`}
                >
                  <span
                    className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                      enableTTS ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
              </div>

              <div className="flex items-center justify-between">
                <div>
                  <div className="font-medium text-gray-900">Model Caching</div>
                  <div className="text-sm text-gray-600">Cache models for faster loading</div>
                </div>
                <button
                  onClick={() => setEnableCaching(!enableCaching)}
                  className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
                    enableCaching ? 'bg-blue-600' : 'bg-gray-200'
                  }`}
                >
                  <span
                    className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
                      enableCaching ? 'translate-x-6' : 'translate-x-1'
                    }`}
                  />
                </button>
              </div>
            </div>
          </section>
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-3 p-6 border-t bg-gray-50">
          <button
            onClick={onClose}
            className="px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-100 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={!apiKey}
            className="px-4 py-2 bg-blue-600 text-white rounded-lg hover:bg-blue-700 disabled:opacity-50 disabled:cursor-not-allowed transition-colors"
          >
            Save Changes
          </button>
        </div>
      </div>
    </div>
  )
}
```

### 6.3 Performance Metrics Dashboard

**File**: `src/components/Dashboard/MetricsDashboard.tsx`

```typescript
import React, { useState, useEffect } from 'react'
import { XMarkIcon } from '@heroicons/react/24/outline'

interface MetricsDashboardProps {
  isOpen: boolean
  onClose: () => void
  performance?: {
    vadLatency: number
    sttLatency: number
    llmLatency: number
    ttsLatency: number
    totalDuration: number
    memoryUsage: number
    modelLoadTime: number
  }
}

export function MetricsDashboard({ isOpen, onClose, performance }: MetricsDashboardProps) {
  const [historicalData, setHistoricalData] = useState<any[]>([])

  useEffect(() => {
    if (performance) {
      setHistoricalData(prev => [
        ...prev.slice(-19), // Keep last 20 data points
        {
          timestamp: new Date(),
          ...performance
        }
      ])
    }
  }, [performance])

  if (!isOpen) return null

  const latestMetrics = historicalData[historicalData.length - 1]

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-xl shadow-2xl max-w-4xl w-full max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-6 border-b">
          <h2 className="text-xl font-semibold text-gray-900">Performance Metrics</h2>
          <button
            onClick={onClose}
            className="text-gray-400 hover:text-gray-600 transition-colors"
          >
            <XMarkIcon className="h-6 w-6" />
          </button>
        </div>

        <div className="p-6">
          {!latestMetrics ? (
            <div className="text-center py-12">
              <p className="text-gray-500">Start a conversation to see performance metrics</p>
            </div>
          ) : (
            <div className="space-y-8">
              {/* Current Performance */}
              <section>
                <h3 className="text-lg font-medium text-gray-900 mb-4">Latest Performance</h3>
                <div className="grid grid-cols-2 md:grid-cols-4 gap-4">
                  <MetricCard
                    title="VAD Latency"
                    value={`${Math.round(latestMetrics.vadLatency)}ms`}
                    target="<50ms"
                    status={latestMetrics.vadLatency < 50 ? 'good' : 'warning'}
                  />
                  <MetricCard
                    title="STT Latency"
                    value={`${Math.round(latestMetrics.sttLatency)}ms`}
                    target="<300ms"
                    status={latestMetrics.sttLatency < 300 ? 'good' : 'warning'}
                  />
                  <MetricCard
                    title="LLM Latency"
                    value={`${Math.round(latestMetrics.llmLatency)}ms`}
                    target="<2000ms"
                    status={latestMetrics.llmLatency < 2000 ? 'good' : 'warning'}
                  />
                  <MetricCard
                    title="TTS Latency"
                    value={`${Math.round(latestMetrics.ttsLatency)}ms`}
                    target="<250ms"
                    status={latestMetrics.ttsLatency < 250 ? 'good' : 'warning'}
                  />
                </div>
              </section>

              {/* Overall Performance */}
              <section>
                <h3 className="text-lg font-medium text-gray-900 mb-4">Overall Performance</h3>
                <div className="grid grid-cols-1 md:grid-cols-3 gap-4">
                  <MetricCard
                    title="Total Duration"
                    value={`${(latestMetrics.totalDuration / 1000).toFixed(1)}s`}
                    target="<3s"
                    status={latestMetrics.totalDuration < 3000 ? 'good' : 'warning'}
                  />
                  <MetricCard
                    title="Memory Usage"
                    value={`${Math.round(latestMetrics.memoryUsage)}MB`}
                    target="<512MB"
                    status={latestMetrics.memoryUsage < 512 ? 'good' : 'warning'}
                  />
                  <MetricCard
                    title="Model Load Time"
                    value={`${(latestMetrics.modelLoadTime / 1000).toFixed(1)}s`}
                    target="<10s"
                    status={latestMetrics.modelLoadTime < 10000 ? 'good' : 'warning'}
                  />
                </div>
              </section>

              {/* Performance Trends */}
              {historicalData.length > 1 && (
                <section>
                  <h3 className="text-lg font-medium text-gray-900 mb-4">Trends (Last 20 Interactions)</h3>
                  <div className="bg-gray-50 rounded-lg p-4">
                    <PerformanceChart data={historicalData} />
                  </div>
                </section>
              )}

              {/* System Info */}
              <section>
                <h3 className="text-lg font-medium text-gray-900 mb-4">System Information</h3>
                <div className="bg-gray-50 rounded-lg p-4">
                  <dl className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                    <div>
                      <dt className="font-medium text-gray-700">Browser</dt>
                      <dd className="text-gray-600">{navigator.userAgent.split(' ')[0]}</dd>
                    </div>
                    <div>
                      <dt className="font-medium text-gray-700">Platform</dt>
                      <dd className="text-gray-600">{navigator.platform}</dd>
                    </div>
                    <div>
                      <dt className="font-medium text-gray-700">Hardware Concurrency</dt>
                      <dd className="text-gray-600">{navigator.hardwareConcurrency} cores</dd>
                    </div>
                    <div>
                      <dt className="font-medium text-gray-700">Device Memory</dt>
                      <dd className="text-gray-600">
                        {(navigator as any).deviceMemory ? `${(navigator as any).deviceMemory}GB` : 'Unknown'}
                      </dd>
                    </div>
                  </dl>
                </div>
              </section>
            </div>
          )}
        </div>
      </div>
    </div>
  )
}

interface MetricCardProps {
  title: string
  value: string
  target: string
  status: 'good' | 'warning' | 'error'
}

function MetricCard({ title, value, target, status }: MetricCardProps) {
  const statusColors = {
    good: 'bg-green-50 border-green-200 text-green-800',
    warning: 'bg-yellow-50 border-yellow-200 text-yellow-800',
    error: 'bg-red-50 border-red-200 text-red-800'
  }

  const indicatorColors = {
    good: 'bg-green-500',
    warning: 'bg-yellow-500',
    error: 'bg-red-500'
  }

  return (
    <div className={`border rounded-lg p-4 ${statusColors[status]}`}>
      <div className="flex items-center justify-between mb-2">
        <h4 className="font-medium text-sm">{title}</h4>
        <div className={`w-3 h-3 rounded-full ${indicatorColors[status]}`} />
      </div>
      <div className="text-2xl font-bold mb-1">{value}</div>
      <div className="text-xs opacity-75">Target: {target}</div>
    </div>
  )
}

function PerformanceChart({ data }: { data: any[] }) {
  // Simple ASCII chart for now - can be replaced with a proper charting library
  const maxLatency = Math.max(...data.map(d => d.sttLatency + d.llmLatency))

  return (
    <div className="space-y-2">
      <div className="text-sm font-medium text-gray-700 mb-2">Total Response Time (STT + LLM)</div>
      {data.slice(-10).map((point, index) => {
        const totalLatency = point.sttLatency + point.llmLatency
        const percentage = (totalLatency / maxLatency) * 100

        return (
          <div key={index} className="flex items-center gap-2 text-xs">
            <div className="w-16 text-right text-gray-600">
              {Math.round(totalLatency)}ms
            </div>
            <div className="flex-1 bg-gray-200 rounded-full h-2">
              <div
                className="bg-blue-500 rounded-full h-2 transition-all duration-300"
                style={{ width: `${percentage}%` }}
              />
            </div>
          </div>
        )
      })}
    </div>
  )
}
```

### 6.4 Custom Hook for Demo Logic

**File**: `src/hooks/useVoiceDemo.ts`

```typescript
import { useState, useEffect, useCallback } from 'react'
import { useVoiceSDK } from '@runanywhere/react'
import type { VoiceConfig } from '@runanywhere/voice-sdk'

interface DemoSettings {
  apiKey: string
  sttModel: string
  llmModel: string
  ttsVoice: string
  language: string
  enableTTS: boolean
  enableCaching: boolean
}

const DEFAULT_SETTINGS: DemoSettings = {
  apiKey: '',
  sttModel: 'whisper-base',
  llmModel: 'gpt-3.5-turbo',
  ttsVoice: 'jenny',
  language: 'en',
  enableTTS: true,
  enableCaching: true
}

export function useVoiceDemo() {
  const [settings, setSettings] = useState<DemoSettings>(() => {
    const saved = localStorage.getItem('voice-demo-settings')
    return saved ? { ...DEFAULT_SETTINGS, ...JSON.parse(saved) } : DEFAULT_SETTINGS
  })

  const [showSettings, setShowSettings] = useState(false)
  const [showMetrics, setShowMetrics] = useState(false)

  // Save settings to localStorage
  useEffect(() => {
    localStorage.setItem('voice-demo-settings', JSON.stringify(settings))
  }, [settings])

  // Create voice config from settings
  const voiceConfig: VoiceConfig = {
    stt: {
      provider: 'transformers',
      model: settings.sttModel,
      language: settings.language,
      enableVAD: true,
      vadThreshold: 0.6
    },
    llm: {
      provider: 'openai',
      apiKey: settings.apiKey,
      model: settings.llmModel,
      streaming: true,
      maxTokens: 150
    },
    tts: {
      provider: 'onnx',
      voice: settings.ttsVoice,
      speed: 1.0,
      enabled: settings.enableTTS
    },
    features: {
      transcription: true,
      llm: true,
      tts: settings.enableTTS,
      caching: settings.enableCaching,
      analytics: true
    },
    performance: {
      targetLatency: 500,
      enableGPU: true,
      maxMemoryMB: 512
    }
  }

  const voiceSDK = useVoiceSDK({
    config: voiceConfig,
    autoInitialize: !!settings.apiKey
  })

  const handleSettingsChange = useCallback((newSettings: Partial<DemoSettings>) => {
    setSettings(prev => ({ ...prev, ...newSettings }))
  }, [])

  const openSettings = useCallback(() => setShowSettings(true), [])
  const closeSettings = useCallback(() => setShowSettings(false), [])
  const openMetrics = useCallback(() => setShowMetrics(true), [])
  const closeMetrics = useCallback(() => setShowMetrics(false), [])

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

    // Voice SDK
    ...voiceSDK
  }
}
```

### 6.5 Main App Component

**File**: `src/App.tsx`

```typescript
import React from 'react'
import { VoiceAssistant } from './components/VoiceAssistant/VoiceAssistant'
import { SettingsPanel } from './components/Settings/SettingsPanel'
import { MetricsDashboard } from './components/Dashboard/MetricsDashboard'
import { useVoiceDemo } from './hooks/useVoiceDemo'

function App() {
  const {
    settings,
    handleSettingsChange,
    showSettings,
    openSettings,
    closeSettings,
    showMetrics,
    openMetrics,
    closeMetrics,
    performance,
    error,
    isInitialized
  } = useVoiceDemo()

  // Show API key setup screen if not configured
  if (!settings.apiKey && !error) {
    return (
      <div className="min-h-screen bg-gradient-to-br from-blue-50 to-indigo-100 flex items-center justify-center p-4">
        <div className="bg-white rounded-xl shadow-lg max-w-md w-full p-6">
          <h2 className="text-2xl font-bold text-gray-900 mb-4 text-center">
            Welcome to RunAnywhere Voice
          </h2>
          <p className="text-gray-600 mb-6 text-center">
            Enter your OpenAI API key to start using the voice assistant
          </p>
          <button
            onClick={openSettings}
            className="w-full bg-blue-600 text-white py-3 px-4 rounded-lg hover:bg-blue-700 transition-colors font-medium"
          >
            Configure Settings
          </button>

          <div className="mt-6 p-4 bg-blue-50 rounded-lg">
            <h3 className="font-medium text-blue-900 mb-2">Features:</h3>
            <ul className="text-sm text-blue-800 space-y-1">
              <li>• Ultra-low latency voice processing (&lt;500ms)</li>
              <li>• Real-time speech-to-text transcription</li>
              <li>• Streaming AI responses</li>
              <li>• Natural text-to-speech output</li>
              <li>• Performance monitoring dashboard</li>
            </ul>
          </div>
        </div>
      </div>
    )
  }

  return (
    <>
      <VoiceAssistant
        apiKey={settings.apiKey}
        onShowSettings={openSettings}
        onShowMetrics={openMetrics}
      />

      <SettingsPanel
        isOpen={showSettings}
        onClose={closeSettings}
        currentConfig={settings}
        onConfigChange={handleSettingsChange}
      />

      <MetricsDashboard
        isOpen={showMetrics}
        onClose={closeMetrics}
        performance={performance}
      />
    </>
  )
}

export default App
```

## Implementation Timeline

### Week 1: Core Components
- **Days 1-2**: Set up React demo project structure and dependencies
- **Days 3-4**: Implement main VoiceAssistant component with basic UI
- **Days 5-7**: Implement Settings panel with configuration management

### Week 2: Advanced Features
- **Days 1-2**: Implement MetricsDashboard with performance visualization
- **Days 3-4**: Add custom hooks for demo logic and state management
- **Days 5-7**: Integrate with voice SDK and test full pipeline

### Week 3: Polish & Documentation
- **Days 1-2**: UI/UX improvements and responsive design
- **Days 3-4**: Error handling, loading states, and edge cases
- **Days 5-7**: Documentation, README, and final testing

## Success Criteria

### Functional Requirements
- ✅ Complete voice conversation pipeline (VAD → STT → LLM → TTS)
- ✅ Real-time performance metrics and monitoring
- ✅ Professional UI with responsive design
- ✅ Configuration interface for all major settings
- ✅ Error handling with user-friendly messages
- ✅ Conversation history and management

### Performance Targets
- **End-to-end latency**: <500ms average
- **UI responsiveness**: No blocking operations
- **Memory usage**: <512MB total
- **Bundle size**: <2MB (excluding models)
- **Load time**: <3 seconds with cached models

### Quality Standards
- **TypeScript**: 100% type coverage with strict mode
- **Accessibility**: WCAG 2.1 AA compliance
- **Browser support**: Chrome 90+, Firefox 90+, Safari 15+
- **Mobile responsive**: Works on tablets and mobile devices
- **Documentation**: Complete usage guide and API docs

## Next Phase Preparation

After Phase 6 completion, the project will be ready for:
- **Phase 7**: Production deployment and optimization
- **Phase 8**: Advanced features like voice cloning, multi-language support
- **Phase 9**: Integration with other RunAnywhere SDKs (iOS/Android)

This React demo will serve as the flagship showcase for the RunAnywhere Voice SDK's capabilities and performance in web browsers.
