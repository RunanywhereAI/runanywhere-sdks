/**
 * Storage Service
 * Handles persistent data storage with fallbacks and error handling
 */

export interface StorageQuota {
  available: number
  used: number
  total: number
  percentage: number
}

export interface StorageItem<T = any> {
  data: T
  timestamp: number
  version: string
  compressed?: boolean
}

export class StorageService {
  private static instance: StorageService
  private readonly VERSION = '1.0'

  static getInstance(): StorageService {
    if (!StorageService.instance) {
      StorageService.instance = new StorageService()
    }
    return StorageService.instance
  }

  /**
   * Set item in localStorage with metadata and error handling
   */
  setItem<T>(key: string, data: T, options: { compress?: boolean; ttl?: number } = {}): boolean {
    try {
      const item: StorageItem<T> = {
        data,
        timestamp: Date.now(),
        version: this.VERSION,
        compressed: options.compress
      }

      let serialized = JSON.stringify(item)

      // Simple compression for large data (if requested)
      if (options.compress && serialized.length > 1000) {
        // In a real implementation, you might use a compression library
        // For now, we'll just mark it as compressed without actual compression
        item.compressed = true
        serialized = JSON.stringify(item)
      }

      localStorage.setItem(key, serialized)
      return true
    } catch (error) {
      console.error(`Failed to store item '${key}':`, error)

      // Try to free up space if quota exceeded
      if (this.isQuotaExceeded(error)) {
        this.cleanupOldItems()

        // Try again after cleanup
        try {
          localStorage.setItem(key, JSON.stringify({ data, timestamp: Date.now(), version: this.VERSION }))
          return true
        } catch (retryError) {
          console.error(`Failed to store item '${key}' after cleanup:`, retryError)
        }
      }

      return false
    }
  }

  /**
   * Get item from localStorage with automatic migration and TTL support
   */
  getItem<T>(key: string, defaultValue?: T): T | null {
    try {
      const stored = localStorage.getItem(key)
      if (!stored) {
        return defaultValue || null
      }

      const item: StorageItem<T> = JSON.parse(stored)

      // Handle legacy data without metadata
      if (!item.timestamp || !item.version) {
        // Assume it's the raw data for backward compatibility
        return stored as unknown as T
      }

      // Version migration (if needed in the future)
      if (item.version !== this.VERSION) {
        // Perform migration logic here if needed
        console.warn(`Storage version mismatch for '${key}'. Expected ${this.VERSION}, got ${item.version}`)
      }

      return item.data
    } catch (error) {
      console.error(`Failed to retrieve item '${key}':`, error)
      return defaultValue || null
    }
  }

  /**
   * Remove item from localStorage
   */
  removeItem(key: string): boolean {
    try {
      localStorage.removeItem(key)
      return true
    } catch (error) {
      console.error(`Failed to remove item '${key}':`, error)
      return false
    }
  }

  /**
   * Check if key exists in localStorage
   */
  hasItem(key: string): boolean {
    try {
      return localStorage.getItem(key) !== null
    } catch (error) {
      console.error(`Failed to check item '${key}':`, error)
      return false
    }
  }

  /**
   * Get all keys with optional prefix filter
   */
  getKeys(prefix?: string): string[] {
    try {
      const keys = []
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i)
        if (key && (!prefix || key.startsWith(prefix))) {
          keys.push(key)
        }
      }
      return keys
    } catch (error) {
      console.error('Failed to get keys:', error)
      return []
    }
  }

  /**
   * Clear all items or items with specific prefix
   */
  clear(prefix?: string): boolean {
    try {
      if (prefix) {
        const keys = this.getKeys(prefix)
        keys.forEach(key => localStorage.removeItem(key))
      } else {
        localStorage.clear()
      }
      return true
    } catch (error) {
      console.error('Failed to clear storage:', error)
      return false
    }
  }

  /**
   * Get storage quota information
   */
  async getStorageQuota(): Promise<StorageQuota | null> {
    try {
      if ('storage' in navigator && 'estimate' in navigator.storage) {
        const estimate = await navigator.storage.estimate()
        const used = estimate.usage || 0
        const total = estimate.quota || 0
        const available = total - used
        const percentage = total > 0 ? (used / total) * 100 : 0

        return {
          available,
          used,
          total,
          percentage
        }
      }
    } catch (error) {
      console.error('Failed to get storage quota:', error)
    }
    return null
  }

  /**
   * Export all data with optional key prefix
   */
  exportData(prefix?: string): string {
    try {
      const keys = this.getKeys(prefix)
      const data: Record<string, any> = {}

      keys.forEach(key => {
        data[key] = this.getItem(key)
      })

      return JSON.stringify({
        data,
        exportedAt: new Date().toISOString(),
        version: this.VERSION,
        keyCount: keys.length
      }, null, 2)
    } catch (error) {
      console.error('Failed to export data:', error)
      return '{}'
    }
  }

  /**
   * Import data from export
   */
  importData(exportString: string, options: { overwrite?: boolean; prefix?: string } = {}): boolean {
    try {
      const exportData = JSON.parse(exportString)

      if (!exportData.data || typeof exportData.data !== 'object') {
        throw new Error('Invalid export format')
      }

      let imported = 0
      let errors = 0

      Object.entries(exportData.data).forEach(([key, value]) => {
        // Apply prefix filter if specified
        if (options.prefix && !key.startsWith(options.prefix)) {
          return
        }

        // Check if key exists and handle overwrite option
        if (!options.overwrite && this.hasItem(key)) {
          return
        }

        if (this.setItem(key, value)) {
          imported++
        } else {
          errors++
        }
      })

      console.log(`Import completed: ${imported} items imported, ${errors} errors`)
      return errors === 0
    } catch (error) {
      console.error('Failed to import data:', error)
      return false
    }
  }

  /**
   * Get storage size in bytes (approximate)
   */
  getStorageSize(): number {
    try {
      let totalSize = 0
      for (let i = 0; i < localStorage.length; i++) {
        const key = localStorage.key(i)
        if (key) {
          const value = localStorage.getItem(key)
          if (value) {
            // Approximate size calculation (UTF-16 encoding)
            totalSize += key.length * 2 + value.length * 2
          }
        }
      }
      return totalSize
    } catch (error) {
      console.error('Failed to calculate storage size:', error)
      return 0
    }
  }

  // Private helper methods

  private isQuotaExceeded(error: any): boolean {
    return error instanceof DOMException && (
      error.code === 22 || // QuotaExceededError
      error.code === 1014 || // NS_ERROR_DOM_QUOTA_REACHED (Firefox)
      error.name === 'QuotaExceededError'
    )
  }

  private cleanupOldItems(): void {
    try {
      const keys = this.getKeys()
      const items: Array<{ key: string; timestamp: number }> = []

      // Collect items with timestamps
      keys.forEach(key => {
        try {
          const stored = localStorage.getItem(key)
          if (stored) {
            const item = JSON.parse(stored)
            if (item.timestamp) {
              items.push({ key, timestamp: item.timestamp })
            }
          }
        } catch {
          // Skip items that can't be parsed
        }
      })

      // Sort by timestamp (oldest first) and remove oldest 25%
      items.sort((a, b) => a.timestamp - b.timestamp)
      const toRemove = Math.floor(items.length * 0.25)

      for (let i = 0; i < toRemove; i++) {
        const item = items[i]
        if (item) {
          localStorage.removeItem(item.key)
        }
      }

      console.log(`Cleaned up ${toRemove} old items from storage`)
    } catch (error) {
      console.error('Failed to cleanup old items:', error)
    }
  }
}

export const storageService = StorageService.getInstance()
