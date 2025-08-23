/**
 * Formatting utilities for the voice demo application
 */

/**
 * Format duration in milliseconds to human-readable string
 */
export function formatDuration(ms: number, options: { precise?: boolean; short?: boolean } = {}): string {
  if (ms < 1000) {
    return options.short ? `${Math.round(ms)}ms` : `${Math.round(ms)} milliseconds`
  }

  const seconds = ms / 1000
  if (seconds < 60) {
    const formatted = options.precise ? seconds.toFixed(1) : Math.round(seconds).toString()
    return options.short ? `${formatted}s` : `${formatted} seconds`
  }

  const minutes = Math.floor(seconds / 60)
  const remainingSeconds = Math.round(seconds % 60)

  if (options.short) {
    return `${minutes}:${remainingSeconds.toString().padStart(2, '0')}`
  }

  return `${minutes} minutes ${remainingSeconds} seconds`
}

/**
 * Format bytes to human-readable string
 */
export function formatBytes(bytes: number, decimals: number = 1): string {
  if (bytes === 0) return '0 Bytes'

  const k = 1024
  const dm = decimals < 0 ? 0 : decimals
  const sizes = ['Bytes', 'KB', 'MB', 'GB', 'TB']

  const i = Math.floor(Math.log(bytes) / Math.log(k))
  return parseFloat((bytes / Math.pow(k, i)).toFixed(dm)) + ' ' + sizes[i]
}

/**
 * Format percentage with appropriate precision
 */
export function formatPercentage(value: number, options: { precision?: number; showSign?: boolean } = {}): string {
  const precision = options.precision ?? 1
  const formatted = (value * 100).toFixed(precision)
  const sign = options.showSign && value > 0 ? '+' : ''
  return `${sign}${formatted}%`
}

/**
 * Format timestamp to relative time (e.g., "2 minutes ago")
 */
export function formatRelativeTime(timestamp: Date): string {
  const now = new Date()
  const diffMs = now.getTime() - timestamp.getTime()
  const diffSec = Math.floor(diffMs / 1000)
  const diffMin = Math.floor(diffSec / 60)
  const diffHour = Math.floor(diffMin / 60)
  const diffDay = Math.floor(diffHour / 24)

  if (diffSec < 60) return 'just now'
  if (diffMin < 60) return `${diffMin} minute${diffMin !== 1 ? 's' : ''} ago`
  if (diffHour < 24) return `${diffHour} hour${diffHour !== 1 ? 's' : ''} ago`
  if (diffDay < 7) return `${diffDay} day${diffDay !== 1 ? 's' : ''} ago`

  // For older dates, use standard format
  return timestamp.toLocaleDateString()
}

/**
 * Format timestamp to time string
 */
export function formatTime(timestamp: Date, options: { includeSeconds?: boolean; includeDate?: boolean } = {}): string {
  const timeOptions: Intl.DateTimeFormatOptions = {
    hour: '2-digit',
    minute: '2-digit',
    ...(options.includeSeconds && { second: '2-digit' })
  }

  if (options.includeDate) {
    return timestamp.toLocaleString(undefined, {
      ...timeOptions,
      year: 'numeric',
      month: 'short',
      day: 'numeric'
    })
  }

  return timestamp.toLocaleTimeString(undefined, timeOptions)
}

/**
 * Format large numbers with abbreviations (K, M, B)
 */
export function formatLargeNumber(num: number, precision: number = 1): string {
  if (num < 1000) return num.toString()

  const units = ['', 'K', 'M', 'B', 'T']
  const unitIndex = Math.floor(Math.log10(Math.abs(num)) / 3)
  const unitValue = Math.pow(1000, unitIndex)
  const formattedValue = (num / unitValue).toFixed(precision)

  return `${formattedValue}${units[unitIndex]}`
}

/**
 * Truncate text with ellipsis
 */
export function truncateText(text: string, maxLength: number, options: { suffix?: string; wordBoundary?: boolean } = {}): string {
  const suffix = options.suffix ?? '...'

  if (text.length <= maxLength) return text

  let truncated = text.substring(0, maxLength - suffix.length)

  if (options.wordBoundary) {
    const lastSpaceIndex = truncated.lastIndexOf(' ')
    if (lastSpaceIndex > 0 && lastSpaceIndex > maxLength * 0.5) {
      truncated = truncated.substring(0, lastSpaceIndex)
    }
  }

  return truncated + suffix
}

/**
 * Format API key for display (mask most characters)
 */
export function formatApiKey(apiKey: string): string {
  if (!apiKey) return ''
  if (apiKey.length <= 8) return '*'.repeat(apiKey.length)

  const start = apiKey.substring(0, 4)
  const end = apiKey.substring(apiKey.length - 4)
  const middle = '*'.repeat(Math.min(apiKey.length - 8, 20))

  return `${start}${middle}${end}`
}

/**
 * Format confidence score as percentage
 */
export function formatConfidence(confidence?: number): string {
  if (confidence === undefined) return 'N/A'
  return `${Math.round(confidence * 100)}%`
}

/**
 * Format language name with native script
 */
export function formatLanguageName(langCode: string, options: { native?: boolean; emoji?: boolean } = {}): string {
  const langMap: Record<string, { name: string; native: string; emoji?: string }> = {
    en: { name: 'English', native: 'English', emoji: '🇺🇸' },
    es: { name: 'Spanish', native: 'Español', emoji: '🇪🇸' },
    fr: { name: 'French', native: 'Français', emoji: '🇫🇷' },
    de: { name: 'German', native: 'Deutsch', emoji: '🇩🇪' },
    it: { name: 'Italian', native: 'Italiano', emoji: '🇮🇹' },
    pt: { name: 'Portuguese', native: 'Português', emoji: '🇵🇹' },
    ru: { name: 'Russian', native: 'Русский', emoji: '🇷🇺' },
    ja: { name: 'Japanese', native: '日本語', emoji: '🇯🇵' },
    ko: { name: 'Korean', native: '한국어', emoji: '🇰🇷' },
    zh: { name: 'Chinese', native: '中文', emoji: '🇨🇳' }
  }

  const lang = langMap[langCode] || { name: langCode.toUpperCase(), native: langCode.toUpperCase() }
  let formatted = options.native ? lang.native : lang.name

  if (options.emoji && lang.emoji) {
    formatted = `${lang.emoji} ${formatted}`
  }

  return formatted
}

/**
 * Format model name for display
 */
export function formatModelName(modelId: string): string {
  const modelNames: Record<string, string> = {
    'whisper-tiny': 'Whisper Tiny',
    'whisper-base': 'Whisper Base',
    'whisper-small': 'Whisper Small',
    'gpt-3.5-turbo': 'GPT-3.5 Turbo',
    'gpt-4': 'GPT-4',
    'gpt-4-turbo': 'GPT-4 Turbo',
    'jenny': 'Jenny (Female, US)',
    'ryan': 'Ryan (Male, US)',
    'sara': 'Sara (Female, UK)',
    'mark': 'Mark (Male, UK)'
  }

  return modelNames[modelId] || modelId
}

/**
 * Format error message for user display
 */
export function formatErrorMessage(error: unknown): string {
  if (!error) return 'Unknown error occurred'

  if (error instanceof Error) {
    // Clean up common error messages
    let message = error.message

    // Remove stack traces and technical details
    message = message.split('\n')[0] || message

    // Make API key errors more user-friendly
    if (message.includes('API key') || message.includes('401')) {
      return 'Invalid or missing API key. Please check your OpenAI API key in settings.'
    }

    // Make network errors more user-friendly
    if (message.includes('fetch') || message.includes('network')) {
      return 'Network error. Please check your internet connection and try again.'
    }

    return message
  }

  if (typeof error === 'string') {
    return error
  }

  return 'An unexpected error occurred'
}
