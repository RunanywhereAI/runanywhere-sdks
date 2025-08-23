/**
 * Metrics Collection and Analysis Service
 * Tracks performance metrics and provides analytics
 */

import type { DemoPerformanceMetrics, PerformanceStatus } from '../types/demo.types'
import { PERFORMANCE_THRESHOLDS } from '../types/demo.types'

export interface MetricsHistory {
  timestamp: Date
  metrics: DemoPerformanceMetrics
  sessionId: string
  userId?: string
}

export interface MetricsAnalysis {
  average: DemoPerformanceMetrics
  median: DemoPerformanceMetrics
  percentile95: DemoPerformanceMetrics
  trends: {
    vadLatency: 'improving' | 'stable' | 'degrading'
    sttLatency: 'improving' | 'stable' | 'degrading'
    llmLatency: 'improving' | 'stable' | 'degrading'
    ttsLatency: 'improving' | 'stable' | 'degrading'
    totalDuration: 'improving' | 'stable' | 'degrading'
  }
  totalInteractions: number
}

export class MetricsService {
  private static instance: MetricsService
  private readonly STORAGE_KEY = 'voice-demo-metrics-history'
  private readonly MAX_HISTORY_SIZE = 1000
  private sessionId: string
  private history: MetricsHistory[] = []

  constructor() {
    this.sessionId = this.generateSessionId()
    this.loadHistory()
  }

  static getInstance(): MetricsService {
    if (!MetricsService.instance) {
      MetricsService.instance = new MetricsService()
    }
    return MetricsService.instance
  }

  /**
   * Record a new performance measurement
   */
  recordMetrics(metrics: DemoPerformanceMetrics, userId?: string): void {
    const record: MetricsHistory = {
      timestamp: new Date(),
      metrics,
      sessionId: this.sessionId,
      userId
    }

    this.history.push(record)

    // Limit history size
    if (this.history.length > this.MAX_HISTORY_SIZE) {
      this.history = this.history.slice(-this.MAX_HISTORY_SIZE)
    }

    this.saveHistory()
  }

  /**
   * Get performance status for a metric value
   */
  getPerformanceStatus(
    metricType: keyof typeof PERFORMANCE_THRESHOLDS,
    value: number
  ): PerformanceStatus {
    const thresholds = PERFORMANCE_THRESHOLDS[metricType]
    if (value <= thresholds.good) return 'good'
    if (value <= thresholds.warning) return 'warning'
    return 'error'
  }

  /**
   * Get recent metrics (last N interactions)
   */
  getRecentMetrics(count: number = 20): MetricsHistory[] {
    return this.history.slice(-count)
  }

  /**
   * Get metrics for current session
   */
  getSessionMetrics(): MetricsHistory[] {
    return this.history.filter(h => h.sessionId === this.sessionId)
  }

  /**
   * Calculate comprehensive analytics
   */
  calculateAnalysis(history: MetricsHistory[] = this.history): MetricsAnalysis {
    if (history.length === 0) {
      throw new Error('No metrics data available for analysis')
    }

    const metrics = history.map(h => h.metrics)

    const average = this.calculateAverage(metrics)
    const median = this.calculateMedian(metrics)
    const percentile95 = this.calculatePercentile(metrics, 95)

    return {
      average,
      median,
      percentile95,
      trends: this.calculateTrends(history),
      totalInteractions: history.length
    }
  }

  /**
   * Export metrics data for analysis
   */
  exportMetrics(): string {
    const exportData = {
      history: this.history,
      analysis: this.calculateAnalysis(),
      exportedAt: new Date().toISOString(),
      sessionId: this.sessionId,
      version: '1.0'
    }
    return JSON.stringify(exportData, null, 2)
  }

  /**
   * Clear all metrics history
   */
  clearHistory(): void {
    this.history = []
    this.saveHistory()
  }

  /**
   * Get system performance recommendations
   */
  getRecommendations(): string[] {
    const recommendations: string[] = []
    const recent = this.getRecentMetrics(10)

    if (recent.length === 0) return recommendations

    const analysis = this.calculateAnalysis(recent)
    const avg = analysis.average

    if (avg.sttLatency > PERFORMANCE_THRESHOLDS.sttLatency.warning) {
      recommendations.push('Consider switching to Whisper Tiny model for faster transcription')
    }

    if (avg.llmLatency > PERFORMANCE_THRESHOLDS.llmLatency.warning) {
      recommendations.push('Try using GPT-3.5 Turbo for faster responses')
    }

    if (avg.memoryUsage > PERFORMANCE_THRESHOLDS.memoryUsage.warning) {
      recommendations.push('Close other browser tabs to free up memory')
      recommendations.push('Disable model caching if memory is limited')
    }

    if (avg.totalDuration > PERFORMANCE_THRESHOLDS.totalDuration.warning) {
      recommendations.push('Check internet connection for better performance')
    }

    if (recommendations.length === 0) {
      recommendations.push('Performance looks good! No optimizations needed.')
    }

    return recommendations
  }

  // Private helper methods

  private generateSessionId(): string {
    return `session_${Date.now()}_${Math.random().toString(36).substr(2, 9)}`
  }

  private loadHistory(): void {
    try {
      const stored = localStorage.getItem(this.STORAGE_KEY)
      if (stored) {
        const parsed = JSON.parse(stored)
        this.history = parsed.map((h: any) => ({
          ...h,
          timestamp: new Date(h.timestamp)
        }))
      }
    } catch (error) {
      console.warn('Failed to load metrics history:', error)
      this.history = []
    }
  }

  private saveHistory(): void {
    try {
      localStorage.setItem(this.STORAGE_KEY, JSON.stringify(this.history))
    } catch (error) {
      console.error('Failed to save metrics history:', error)
    }
  }

  private calculateAverage(metrics: DemoPerformanceMetrics[]): DemoPerformanceMetrics {
    const sum = metrics.reduce((acc, m) => ({
      vadLatency: acc.vadLatency + m.vadLatency,
      sttLatency: acc.sttLatency + m.sttLatency,
      llmLatency: acc.llmLatency + m.llmLatency,
      ttsLatency: acc.ttsLatency + m.ttsLatency,
      totalDuration: acc.totalDuration + m.totalDuration,
      memoryUsage: acc.memoryUsage + m.memoryUsage,
      modelLoadTime: acc.modelLoadTime + m.modelLoadTime
    }), {
      vadLatency: 0, sttLatency: 0, llmLatency: 0, ttsLatency: 0,
      totalDuration: 0, memoryUsage: 0, modelLoadTime: 0
    })

    const count = metrics.length
    return {
      vadLatency: sum.vadLatency / count,
      sttLatency: sum.sttLatency / count,
      llmLatency: sum.llmLatency / count,
      ttsLatency: sum.ttsLatency / count,
      totalDuration: sum.totalDuration / count,
      memoryUsage: sum.memoryUsage / count,
      modelLoadTime: sum.modelLoadTime / count
    }
  }

  private calculateMedian(metrics: DemoPerformanceMetrics[]): DemoPerformanceMetrics {
    if (metrics.length === 0) {
      return this.getDefaultMetrics()
    }

    const sorted = metrics.slice().sort((a, b) => a.totalDuration - b.totalDuration)
    const mid = Math.floor(sorted.length / 2)

    if (sorted.length % 2 === 0) {
      const left = sorted[mid - 1]
      const right = sorted[mid]
      if (left && right) {
        return this.calculateAverage([left, right])
      }
    }

    return sorted[mid] || this.getDefaultMetrics()
  }

  private calculatePercentile(metrics: DemoPerformanceMetrics[], percentile: number): DemoPerformanceMetrics {
    if (metrics.length === 0) {
      return this.getDefaultMetrics()
    }

    const sorted = metrics.slice().sort((a, b) => a.totalDuration - b.totalDuration)
    const index = Math.floor((percentile / 100) * (sorted.length - 1))

    return sorted[index] || this.getDefaultMetrics()
  }

  private getDefaultMetrics(): DemoPerformanceMetrics {
    return {
      vadLatency: 0,
      sttLatency: 0,
      llmLatency: 0,
      ttsLatency: 0,
      totalDuration: 0,
      memoryUsage: 0,
      modelLoadTime: 0
    }
  }

  private calculateTrends(history: MetricsHistory[]): MetricsAnalysis['trends'] {
    if (history.length < 5) {
      return {
        vadLatency: 'stable',
        sttLatency: 'stable',
        llmLatency: 'stable',
        ttsLatency: 'stable',
        totalDuration: 'stable'
      }
    }

    const recent = history.slice(-5).map(h => h.metrics)
    const older = history.slice(-10, -5).map(h => h.metrics)

    if (older.length === 0) {
      return {
        vadLatency: 'stable',
        sttLatency: 'stable',
        llmLatency: 'stable',
        ttsLatency: 'stable',
        totalDuration: 'stable'
      }
    }

    const recentAvg = this.calculateAverage(recent)
    const olderAvg = this.calculateAverage(older)

    const getTrend = (recent: number, older: number): 'improving' | 'stable' | 'degrading' => {
      const change = (recent - older) / older
      if (change < -0.1) return 'improving' // 10% improvement
      if (change > 0.1) return 'degrading'  // 10% degradation
      return 'stable'
    }

    return {
      vadLatency: getTrend(recentAvg.vadLatency, olderAvg.vadLatency),
      sttLatency: getTrend(recentAvg.sttLatency, olderAvg.sttLatency),
      llmLatency: getTrend(recentAvg.llmLatency, olderAvg.llmLatency),
      ttsLatency: getTrend(recentAvg.ttsLatency, olderAvg.ttsLatency),
      totalDuration: getTrend(recentAvg.totalDuration, olderAvg.totalDuration)
    }
  }
}

export const metricsService = MetricsService.getInstance()
