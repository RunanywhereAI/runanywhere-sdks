// Response Cache for storing and retrieving LLM responses and transcription results
import type { Result } from '@runanywhere/core';

export interface CachedResponse {
  id: string;
  prompt: string;
  response: string;
  timestamp: number;
  ttl: number;
  metadata?: {
    model?: string;
    tokens?: number;
    latency?: number;
    confidence?: number;
  };
}

export interface ResponseCacheConfig {
  maxItems: number;
  defaultTTL: number; // milliseconds
  enableHashing: boolean;
  enablePersistence: boolean;
  hashSalt: string;
}

export class ResponseCache {
  private cache = new Map<string, CachedResponse>();
  private config: ResponseCacheConfig;
  private cleanupInterval: number | null = null;

  constructor(config: Partial<ResponseCacheConfig> = {}) {
    this.config = {
      maxItems: 1000,
      defaultTTL: 60 * 60 * 1000, // 1 hour default
      enableHashing: true,
      enablePersistence: false, // Keep responses in memory only by default
      hashSalt: 'runanywhere-cache-salt',
      ...config
    };

    // Start cleanup interval
    this.startCleanupInterval();
  }

  async cacheResponse(
    prompt: string,
    response: string,
    ttl: number = this.config.defaultTTL,
    metadata?: CachedResponse['metadata']
  ): Promise<Result<void, Error>> {
    try {
      const key = await this.generateKey(prompt);

      const cachedResponse: CachedResponse = {
        id: crypto.randomUUID(),
        prompt,
        response,
        timestamp: Date.now(),
        ttl,
        ...(metadata && { metadata })
      };

      this.cache.set(key, cachedResponse);

      // Evict oldest entries if cache is too large
      await this.evictIfNecessary();

      return { success: true, value: undefined };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async getCachedResponse(prompt: string): Promise<Result<string | null, Error>> {
    try {
      const key = await this.generateKey(prompt);
      const cached = this.cache.get(key);

      if (!cached) {
        return { success: true, value: null };
      }

      // Check if expired
      const now = Date.now();
      if (now - cached.timestamp > cached.ttl) {
        this.cache.delete(key);
        return { success: true, value: null };
      }

      return { success: true, value: cached.response };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async getCachedResponseWithMetadata(prompt: string): Promise<Result<CachedResponse | null, Error>> {
    try {
      const key = await this.generateKey(prompt);
      const cached = this.cache.get(key);

      if (!cached) {
        return { success: true, value: null };
      }

      // Check if expired
      const now = Date.now();
      if (now - cached.timestamp > cached.ttl) {
        this.cache.delete(key);
        return { success: true, value: null };
      }

      return { success: true, value: cached };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async invalidateResponse(prompt: string): Promise<Result<void, Error>> {
    try {
      const key = await this.generateKey(prompt);
      this.cache.delete(key);
      return { success: true, value: undefined };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async invalidateExpired(): Promise<Result<number, Error>> {
    try {
      const now = Date.now();
      let removedCount = 0;

      for (const [key, cached] of this.cache.entries()) {
        if (now - cached.timestamp > cached.ttl) {
          this.cache.delete(key);
          removedCount++;
        }
      }

      return { success: true, value: removedCount };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  async clear(): Promise<Result<void, Error>> {
    try {
      this.cache.clear();
      return { success: true, value: undefined };
    } catch (error) {
      return {
        success: false,
        error: error instanceof Error ? error : new Error(String(error))
      };
    }
  }

  getCacheStats(): {
    size: number;
    maxSize: number;
    utilization: number;
    oldestEntry: number | null;
    newestEntry: number | null;
  } {
    const timestamps = Array.from(this.cache.values()).map(c => c.timestamp);

    return {
      size: this.cache.size,
      maxSize: this.config.maxItems,
      utilization: this.cache.size / this.config.maxItems,
      oldestEntry: timestamps.length > 0 ? Math.min(...timestamps) : null,
      newestEntry: timestamps.length > 0 ? Math.max(...timestamps) : null
    };
  }

  listResponses(): CachedResponse[] {
    return Array.from(this.cache.values()).sort((a, b) => b.timestamp - a.timestamp);
  }

  // Cache patterns for common use cases
  async cacheTranscription(
    audioHash: string,
    transcription: string,
    confidence: number,
    ttl: number = 24 * 60 * 60 * 1000 // 24 hours for transcriptions
  ): Promise<Result<void, Error>> {
    return this.cacheResponse(
      `transcription:${audioHash}`,
      transcription,
      ttl,
      { confidence, model: 'whisper' }
    );
  }

  async getCachedTranscription(audioHash: string): Promise<Result<string | null, Error>> {
    return this.getCachedResponse(`transcription:${audioHash}`);
  }

  async cacheLLMResponse(
    prompt: string,
    response: string,
    model: string,
    tokens: number,
    latency: number,
    ttl: number = this.config.defaultTTL
  ): Promise<Result<void, Error>> {
    return this.cacheResponse(prompt, response, ttl, {
      model,
      tokens,
      latency
    });
  }

  // Private helper methods
  private async generateKey(prompt: string): Promise<string> {
    if (!this.config.enableHashing) {
      return prompt;
    }

    // Create a simple hash of the prompt with salt
    const saltedPrompt = this.config.hashSalt + prompt;

    // Use Web Crypto API if available, fallback to simple hash
    if (typeof crypto !== 'undefined' && crypto.subtle) {
      const encoder = new TextEncoder();
      const data = encoder.encode(saltedPrompt);
      const hashBuffer = await crypto.subtle.digest('SHA-256', data);
      const hashArray = Array.from(new Uint8Array(hashBuffer));
      return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
    }

    // Fallback simple hash
    return this.simpleHash(saltedPrompt);
  }

  private simpleHash(str: string): string {
    let hash = 0;
    for (let i = 0; i < str.length; i++) {
      const char = str.charCodeAt(i);
      hash = ((hash << 5) - hash) + char;
      hash = hash & hash; // Convert to 32-bit integer
    }
    return Math.abs(hash).toString(16);
  }

  private async evictIfNecessary(): Promise<void> {
    if (this.cache.size <= this.config.maxItems) {
      return;
    }

    // Sort by timestamp (oldest first) and remove oldest entries
    const entries = Array.from(this.cache.entries()).sort((a, b) => {
      return a[1].timestamp - b[1].timestamp;
    });

    const toRemove = this.cache.size - this.config.maxItems;
    for (let i = 0; i < toRemove; i++) {
      const [key] = entries[i];
      this.cache.delete(key);
    }
  }

  private startCleanupInterval(): void {
    // Run cleanup every 5 minutes
    this.cleanupInterval = window.setInterval(() => {
      this.invalidateExpired();
    }, 5 * 60 * 1000);
  }

  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }

    this.cache.clear();
  }
}
