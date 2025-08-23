import { useCallback } from 'react'
import {
  MicrophoneIcon,
  StopIcon,
  Cog6ToothIcon,
  ChartBarIcon
} from '@heroicons/react/24/outline'
import type { ConversationMessage, DemoPerformanceMetrics } from '../../types/demo.types'

interface VoiceAssistantProps {
  onShowSettings: () => void
  onShowMetrics: () => void
  // Voice state (would come from useVoiceDemo hook in real usage)
  isInitialized?: boolean
  isActive?: boolean
  isListening?: boolean
  isProcessing?: boolean
  currentTranscript?: string
  currentResponse?: string
  audioLevel?: number
  error?: Error | null
  performance?: DemoPerformanceMetrics | null
  conversationHistory?: ConversationMessage[]
  startConversation?: () => Promise<void>
  stopConversation?: () => Promise<void>
  clearConversation?: () => void
}

export function VoiceAssistant({
  onShowSettings,
  onShowMetrics,
  isInitialized = false,
  isActive = false,
  isListening = false,
  isProcessing = false,
  currentTranscript = '',
  currentResponse = '',
  audioLevel = 0,
  error = null,
  performance = null,
  conversationHistory = [],
  startConversation = async () => {},
  stopConversation = async () => {},
  clearConversation = () => {}
}: VoiceAssistantProps) {

  const handleToggleConversation = useCallback(async () => {
    if (isActive) {
      await stopConversation()
    } else {
      await startConversation()
    }
  }, [isActive, startConversation, stopConversation])

  const handleClearHistory = useCallback(() => {
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
                <Cog6ToothIcon className="h-5 w-5" />
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
                    <StopIcon className="h-8 w-8" />
                  ) : (
                    <MicrophoneIcon className="h-8 w-8" />
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

                {audioLevel > 0 && isListening && (
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
                    <div>Total: {Math.round(performance.totalDuration)}ms</div>
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
                  <MicrophoneIcon className="h-12 w-12 mx-auto mb-4 opacity-50" />
                  <p className="text-lg">No conversations yet</p>
                  <p className="text-sm mt-1">Click the microphone button to start talking</p>
                </div>
              ) : (
                <div className="space-y-4 max-h-96 overflow-y-auto">
                  {conversationHistory.map((message) => (
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
                          {message.duration && ` • ${Math.round(message.duration)}ms`}
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
