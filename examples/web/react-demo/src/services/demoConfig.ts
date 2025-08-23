/**
 * Demo Configuration Service
 * Manages application configuration and provides default settings
 */

import type { DemoSettings } from '../types/demo.types'
import { DEFAULT_DEMO_SETTINGS } from '../types/demo.types'

export class DemoConfigService {
  private static instance: DemoConfigService
  private readonly STORAGE_KEY = 'voice-demo-settings'

  static getInstance(): DemoConfigService {
    if (!DemoConfigService.instance) {
      DemoConfigService.instance = new DemoConfigService()
    }
    return DemoConfigService.instance
  }

  /**
   * Load settings from localStorage with fallback to defaults
   */
  loadSettings(): DemoSettings {
    try {
      const stored = localStorage.getItem(this.STORAGE_KEY)
      if (stored) {
        const parsed = JSON.parse(stored) as Partial<DemoSettings>
        return { ...DEFAULT_DEMO_SETTINGS, ...parsed }
      }
    } catch (error) {
      console.warn('Failed to load demo settings from localStorage:', error)
    }
    return { ...DEFAULT_DEMO_SETTINGS }
  }

  /**
   * Save settings to localStorage
   */
  saveSettings(settings: DemoSettings): boolean {
    try {
      localStorage.setItem(this.STORAGE_KEY, JSON.stringify(settings))
      return true
    } catch (error) {
      console.error('Failed to save demo settings to localStorage:', error)
      return false
    }
  }

  /**
   * Reset settings to defaults
   */
  resetToDefaults(): DemoSettings {
    const defaults = { ...DEFAULT_DEMO_SETTINGS }
    this.saveSettings(defaults)
    return defaults
  }

  /**
   * Validate settings and return any issues
   */
  validateSettings(settings: DemoSettings): string[] {
    const issues: string[] = []

    if (!settings.apiKey.trim()) {
      issues.push('OpenAI API key is required')
    } else if (!settings.apiKey.startsWith('sk-')) {
      issues.push('OpenAI API key should start with "sk-"')
    }

    if (settings.apiKey.length > 0 && settings.apiKey.length < 50) {
      issues.push('API key appears to be incomplete')
    }

    return issues
  }

  /**
   * Get recommended settings based on device capabilities
   */
  getRecommendedSettings(): Partial<DemoSettings> {
    const recommendations: Partial<DemoSettings> = {}

    // Recommend model based on available memory
    const deviceMemory = (navigator as any).deviceMemory
    if (deviceMemory) {
      if (deviceMemory <= 4) {
        recommendations.sttModel = 'whisper-tiny'
        recommendations.enableCaching = false
      } else if (deviceMemory <= 8) {
        recommendations.sttModel = 'whisper-base'
        recommendations.enableCaching = true
      } else {
        recommendations.sttModel = 'whisper-small'
        recommendations.enableCaching = true
      }
    }

    // Recommend TTS based on connection
    const connection = (navigator as any).connection
    if (connection && connection.effectiveType === 'slow-2g') {
      recommendations.enableTTS = false
    }

    return recommendations
  }

  /**
   * Export settings for backup
   */
  exportSettings(settings: DemoSettings): string {
    const exportData = {
      settings: settings,
      exportedAt: new Date().toISOString(),
      version: '1.0'
    }
    return JSON.stringify(exportData, null, 2)
  }

  /**
   * Import settings from backup
   */
  importSettings(data: string): DemoSettings | null {
    try {
      const parsed = JSON.parse(data)
      if (parsed.settings && typeof parsed.settings === 'object') {
        const imported = { ...DEFAULT_DEMO_SETTINGS, ...parsed.settings }
        const issues = this.validateSettings(imported)
        if (issues.length === 0) {
          return imported
        }
      }
    } catch (error) {
      console.error('Failed to import settings:', error)
    }
    return null
  }
}

export const demoConfig = DemoConfigService.getInstance()
