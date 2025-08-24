import { useState } from 'react'
import { XMarkIcon } from '@heroicons/react/24/outline'
import type { DemoSettings } from '../../types/demo.types'
import { SUPPORTED_STT_MODELS, SUPPORTED_VOICES, SUPPORTED_LANGUAGES } from '../../types/demo.types'

interface SettingsPanelProps {
  isOpen: boolean
  onClose: () => void
  currentConfig: DemoSettings
  onConfigChange: (config: Partial<DemoSettings>) => void
}

export function SettingsPanel({ isOpen, onClose, currentConfig, onConfigChange }: SettingsPanelProps) {
  console.log('SettingsPanel render:', { isOpen });

  const [localSettings, setLocalSettings] = useState<DemoSettings>(currentConfig)
  const [hasChanges, setHasChanges] = useState(false)

  const updateSetting = <K extends keyof DemoSettings>(key: K, value: DemoSettings[K]) => {
    setLocalSettings(prev => ({ ...prev, [key]: value }))
    setHasChanges(true)
  }

  const handleSave = () => {
    onConfigChange(localSettings)
    setHasChanges(false)
    onClose()
  }

  const handleCancel = () => {
    setLocalSettings(currentConfig)
    setHasChanges(false)
    onClose()
  }

  if (!isOpen) {
    console.log('SettingsPanel: Not rendering because isOpen is false');
    return null;
  }

  console.log('SettingsPanel: Rendering modal...');

  return (
    <div className="fixed inset-0 bg-black bg-opacity-50 z-50 flex items-center justify-center p-4">
      <div className="bg-white rounded-xl shadow-2xl max-w-2xl w-full max-h-[90vh] overflow-y-auto">
        <div className="flex items-center justify-between p-6 border-b">
          <h2 className="text-xl font-semibold text-gray-900">Settings</h2>
          <button
            onClick={handleCancel}
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
                  OpenAI API Key *
                </label>
                <input
                  type="password"
                  value={localSettings.apiKey}
                  onChange={(e) => updateSetting('apiKey', e.target.value)}
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
                  value={localSettings.sttModel}
                  onChange={(e) => updateSetting('sttModel', e.target.value as DemoSettings['sttModel'])}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  {Object.entries(SUPPORTED_STT_MODELS).map(([key, model]) => (
                    <option key={key} value={key}>
                      {model.name} ({model.size})
                    </option>
                  ))}
                </select>
                <p className="text-xs text-gray-500 mt-1">
                  {SUPPORTED_STT_MODELS[localSettings.sttModel].description}
                </p>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  Language
                </label>
                <select
                  value={localSettings.language}
                  onChange={(e) => updateSetting('language', e.target.value as DemoSettings['language'])}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500"
                >
                  {Object.entries(SUPPORTED_LANGUAGES).map(([key, lang]) => (
                    <option key={key} value={key}>
                      {lang.name} ({lang.nativeName})
                    </option>
                  ))}
                </select>
              </div>

              <div>
                <label className="block text-sm font-medium text-gray-700 mb-2">
                  LLM Model
                </label>
                <select
                  value={localSettings.llmModel}
                  onChange={(e) => updateSetting('llmModel', e.target.value as DemoSettings['llmModel'])}
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
                  value={localSettings.ttsVoice}
                  onChange={(e) => updateSetting('ttsVoice', e.target.value as DemoSettings['ttsVoice'])}
                  disabled={!localSettings.enableTTS}
                  className="w-full px-3 py-2 border border-gray-300 rounded-lg focus:ring-2 focus:ring-blue-500 disabled:opacity-50"
                >
                  {Object.entries(SUPPORTED_VOICES).map(([key, voice]) => (
                    <option key={key} value={key}>
                      {voice.name} ({voice.gender}, {voice.accent})
                    </option>
                  ))}
                </select>
                <p className="text-xs text-gray-500 mt-1">
                  {SUPPORTED_VOICES[localSettings.ttsVoice].description}
                </p>
              </div>
            </div>
          </section>

          {/* Features */}
          <section>
            <h3 className="text-lg font-medium text-gray-900 mb-4">Features</h3>
            <div className="space-y-4">
              <ToggleSwitch
                label="Text-to-Speech"
                description="Enable AI voice responses"
                checked={localSettings.enableTTS}
                onChange={(checked) => updateSetting('enableTTS', checked)}
              />

              <ToggleSwitch
                label="Model Caching"
                description="Cache models for faster loading"
                checked={localSettings.enableCaching}
                onChange={(checked) => updateSetting('enableCaching', checked)}
              />

            </div>
          </section>

          {/* Performance Info */}
          <section>
            <h3 className="text-lg font-medium text-gray-900 mb-4">Performance Estimates</h3>
            <div className="bg-gray-50 rounded-lg p-4">
              <div className="grid grid-cols-1 md:grid-cols-2 gap-4 text-sm">
                <div>
                  <span className="font-medium text-gray-700">Memory Usage:</span>
                  <span className="ml-2 text-gray-600">
                    {SUPPORTED_STT_MODELS[localSettings.sttModel].memoryUsage}
                  </span>
                </div>
                <div>
                  <span className="font-medium text-gray-700">Processing Speed:</span>
                  <span className="ml-2 text-gray-600 capitalize">
                    {SUPPORTED_STT_MODELS[localSettings.sttModel].speed}
                  </span>
                </div>
                <div>
                  <span className="font-medium text-gray-700">Voice Quality:</span>
                  <span className="ml-2 text-gray-600">
                    {SUPPORTED_VOICES[localSettings.ttsVoice].sampleRate / 1000}kHz
                  </span>
                </div>
                <div>
                  <span className="font-medium text-gray-700">Model Size:</span>
                  <span className="ml-2 text-gray-600">
                    {SUPPORTED_STT_MODELS[localSettings.sttModel].size}
                  </span>
                </div>
              </div>
            </div>
          </section>
        </div>

        {/* Footer */}
        <div className="flex justify-end gap-3 p-6 border-t bg-gray-50">
          <button
            onClick={handleCancel}
            className="px-4 py-2 border border-gray-300 text-gray-700 rounded-lg hover:bg-gray-100 transition-colors"
          >
            Cancel
          </button>
          <button
            onClick={handleSave}
            disabled={!localSettings.apiKey}
            className={`px-4 py-2 rounded-lg transition-colors ${
              hasChanges && localSettings.apiKey
                ? 'bg-blue-600 text-white hover:bg-blue-700'
                : 'bg-gray-300 text-gray-500 cursor-not-allowed'
            }`}
          >
            Save Changes
          </button>
        </div>
      </div>
    </div>
  )
}

interface ToggleSwitchProps {
  label: string
  description: string
  checked: boolean
  onChange: (checked: boolean) => void
}

function ToggleSwitch({ label, description, checked, onChange }: ToggleSwitchProps) {
  return (
    <div className="flex items-center justify-between">
      <div>
        <div className="font-medium text-gray-900">{label}</div>
        <div className="text-sm text-gray-600">{description}</div>
      </div>
      <button
        onClick={() => onChange(!checked)}
        className={`relative inline-flex h-6 w-11 items-center rounded-full transition-colors ${
          checked ? 'bg-blue-600' : 'bg-gray-200'
        }`}
      >
        <span
          className={`inline-block h-4 w-4 transform rounded-full bg-white transition-transform ${
            checked ? 'translate-x-6' : 'translate-x-1'
          }`}
        />
      </button>
    </div>
  )
}
