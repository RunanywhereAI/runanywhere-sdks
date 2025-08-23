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
    isInitialized,
    isActive,
    isListening,
    isProcessing,
    currentTranscript,
    currentResponse,
    audioLevel,
    conversationHistory,
    startConversation,
    stopConversation,
    clearConversation
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
        onShowSettings={openSettings}
        onShowMetrics={openMetrics}
        isInitialized={isInitialized}
        isActive={isActive}
        isListening={isListening}
        isProcessing={isProcessing}
        currentTranscript={currentTranscript}
        currentResponse={currentResponse}
        audioLevel={audioLevel}
        error={error}
        performance={performance}
        conversationHistory={conversationHistory}
        startConversation={startConversation}
        stopConversation={stopConversation}
        clearConversation={clearConversation}
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
