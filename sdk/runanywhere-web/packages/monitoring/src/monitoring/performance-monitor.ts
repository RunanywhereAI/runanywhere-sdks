// Performance monitoring for RunAnywhere Web Voice Pipeline

export interface Metric {
  name: string;
  value: number;
  unit: 'ms' | 'bytes' | 'count' | 'percent';
  timestamp: number;
  metadata?: Record<string, any>;
}

export interface TimingHandle {
  name: string;
  startTime: number;
  end(): number;
  endWithMetadata(metadata?: Record<string, any>): number;
}

export interface PerformanceReport {
  summary: {
    totalSamples: number;
    timeRange: {
      start: number;
      end: number;
    };
    averageLatency: {
      vad: number;
      stt: number;
      llm: number;
      tts: number;
      endToEnd: number;
    };
  };
  metrics: Metric[];
  recommendations: string[];
}

export interface PerformanceThresholds {
  vadLatency: number; // ms
  sttLatency: number; // ms
  llmLatency: number; // ms
  ttsLatency: number; // ms
  endToEndLatency: number; // ms
  memoryUsage: number; // bytes
  bundleSize: number; // bytes
}

export class PerformanceMonitor {
  private metrics = new Map<string, Metric[]>();
  private activeTimings = new Map<string, TimingHandle>();
  private thresholds: PerformanceThresholds;
  private maxMetricsPerType = 1000;
  private cleanupInterval: number | null = null;

  constructor(thresholds: Partial<PerformanceThresholds> = {}) {
    this.thresholds = {
      vadLatency: 50,
      sttLatency: 200,
      llmLatency: 1000,
      ttsLatency: 100,
      endToEndLatency: 2000,
      memoryUsage: 100 * 1024 * 1024, // 100MB
      bundleSize: 10 * 1024 * 1024, // 10MB
      ...thresholds
    };

    this.startCleanupInterval();
  }

  startTiming(operation: string, metadata?: Record<string, any>): TimingHandle {
    const startTime = performance.now();
    const handle: TimingHandle = {
      name: operation,
      startTime,
      end: () => {
        const duration = performance.now() - startTime;
        this.recordMetric(operation, duration, 'ms', metadata);
        this.activeTimings.delete(operation);
        return duration;
      },
      endWithMetadata: (additionalMetadata?: Record<string, any>) => {
        const duration = performance.now() - startTime;
        const combinedMetadata = { ...metadata, ...additionalMetadata };
        this.recordMetric(operation, duration, 'ms', combinedMetadata);
        this.activeTimings.delete(operation);
        return duration;
      }
    };

    this.activeTimings.set(operation, handle);
    return handle;
  }

  recordMetric(
    name: string,
    value: number,
    unit: Metric['unit'] = 'count',
    metadata?: Record<string, any>
  ): void {
    const metric: Metric = {
      name,
      value,
      unit,
      timestamp: Date.now(),
      ...(metadata && { metadata })
    };

    if (!this.metrics.has(name)) {
      this.metrics.set(name, []);
    }

    const metrics = this.metrics.get(name)!;
    metrics.push(metric);

    // Keep only recent metrics to prevent memory bloat
    if (metrics.length > this.maxMetricsPerType) {
      metrics.shift();
    }

    // Check thresholds and alert if exceeded
    this.checkThreshold(name, value);
  }

  recordMemoryUsage(): void {
    if ('memory' in performance) {
      const memory = (performance as any).memory;
      this.recordMetric('memory.used', memory.usedJSHeapSize, 'bytes');
      this.recordMetric('memory.total', memory.totalJSHeapSize, 'bytes');
      this.recordMetric('memory.limit', memory.jsHeapSizeLimit, 'bytes');
    }
  }

  recordNetworkMetric(url: string, duration: number, size?: number): void {
    this.recordMetric('network.request', duration, 'ms', { url });
    if (size) {
      this.recordMetric('network.size', size, 'bytes', { url });
    }
  }

  recordModelMetric(
    modelType: 'vad' | 'stt' | 'llm' | 'tts',
    operation: 'load' | 'inference',
    duration: number,
    metadata?: Record<string, any>
  ): void {
    this.recordMetric(
      `model.${modelType}.${operation}`,
      duration,
      'ms',
      metadata
    );
  }

  recordBundleSize(packageName: string, size: number): void {
    this.recordMetric(`bundle.${packageName}`, size, 'bytes');
  }

  recordUserInteraction(action: string, duration?: number): void {
    const metric: Record<string, any> = { action };
    if (duration !== undefined) {
      metric.duration = duration;
    }
    this.recordMetric('user.interaction', 1, 'count', metric);
  }

  getMetrics(name?: string): Metric[] {
    if (name) {
      return this.metrics.get(name) || [];
    }

    const allMetrics: Metric[] = [];
    for (const metrics of this.metrics.values()) {
      allMetrics.push(...metrics);
    }

    return allMetrics.sort((a, b) => b.timestamp - a.timestamp);
  }

  getMetricStats(name: string): {
    count: number;
    average: number;
    min: number;
    max: number;
    median: number;
    p95: number;
    recent: number; // Most recent value
  } | null {
    const metrics = this.metrics.get(name);
    if (!metrics || metrics.length === 0) {
      return null;
    }

    const values = metrics.map(m => m.value).sort((a, b) => a - b);
    const count = values.length;
    const sum = values.reduce((acc, val) => acc + val, 0);
    const average = sum / count;
    const min = values[0];
    const max = values[count - 1];
    const median = count % 2 === 0
      ? (values[count / 2 - 1] + values[count / 2]) / 2
      : values[Math.floor(count / 2)];
    const p95Index = Math.floor(count * 0.95);
    const p95 = values[p95Index];
    const recent = metrics[metrics.length - 1].value;

    return {
      count,
      average,
      min,
      max,
      median,
      p95,
      recent
    };
  }

  getAverageLatency(operation: string): number {
    const stats = this.getMetricStats(operation);
    return stats?.average || 0;
  }

  generateReport(timeRange?: { start: number; end: number }): PerformanceReport {
    const now = Date.now();
    const range = timeRange || {
      start: now - (60 * 60 * 1000), // Last hour
      end: now
    };

    // Filter metrics by time range
    const filteredMetrics: Metric[] = [];
    for (const metrics of this.metrics.values()) {
      filteredMetrics.push(
        ...metrics.filter(m => m.timestamp >= range.start && m.timestamp <= range.end)
      );
    }

    // Calculate summary statistics
    const summary = {
      totalSamples: filteredMetrics.length,
      timeRange: range,
      averageLatency: {
        vad: this.getAverageLatency('vad'),
        stt: this.getAverageLatency('stt') || this.getAverageLatency('transcription'),
        llm: this.getAverageLatency('llm') || this.getAverageLatency('llm.inference'),
        tts: this.getAverageLatency('tts') || this.getAverageLatency('tts.synthesis'),
        endToEnd: this.getAverageLatency('pipeline.endToEnd')
      }
    };

    // Generate recommendations
    const recommendations = this.generateRecommendations(summary);

    return {
      summary,
      metrics: filteredMetrics,
      recommendations
    };
  }

  private generateRecommendations(summary: PerformanceReport['summary']): string[] {
    const recommendations: string[] = [];

    // Latency recommendations
    if (summary.averageLatency.vad > this.thresholds.vadLatency) {
      recommendations.push(`VAD latency (${summary.averageLatency.vad}ms) exceeds threshold. Consider using a smaller VAD model or implementing caching.`);
    }

    if (summary.averageLatency.stt > this.thresholds.sttLatency) {
      recommendations.push(`STT latency (${summary.averageLatency.stt}ms) exceeds threshold. Consider using Web Workers or a faster model variant.`);
    }

    if (summary.averageLatency.llm > this.thresholds.llmLatency) {
      recommendations.push(`LLM latency (${summary.averageLatency.llm}ms) exceeds threshold. Consider response caching, smaller models, or streaming responses.`);
    }

    if (summary.averageLatency.tts > this.thresholds.ttsLatency) {
      recommendations.push(`TTS latency (${summary.averageLatency.tts}ms) exceeds threshold. Consider audio caching or faster synthesis models.`);
    }

    if (summary.averageLatency.endToEnd > this.thresholds.endToEndLatency) {
      recommendations.push(`End-to-end latency (${summary.averageLatency.endToEnd}ms) exceeds threshold. Consider pipeline optimization and parallel processing.`);
    }

    // Memory recommendations
    const memoryStats = this.getMetricStats('memory.used');
    if (memoryStats && memoryStats.average > this.thresholds.memoryUsage) {
      recommendations.push(`Memory usage (${Math.round(memoryStats.average / (1024 * 1024))}MB) exceeds threshold. Consider model caching optimization.`);
    }

    return recommendations;
  }

  private checkThreshold(metricName: string, value: number): void {
    const thresholdKey = metricName as keyof PerformanceThresholds;
    const threshold = this.thresholds[thresholdKey];

    if (threshold && value > threshold) {
      console.warn(`[PerformanceMonitor] ${metricName} (${value}) exceeds threshold (${threshold})`);
    }
  }

  clearMetrics(name?: string): void {
    if (name) {
      this.metrics.delete(name);
    } else {
      this.metrics.clear();
    }
  }

  updateThresholds(newThresholds: Partial<PerformanceThresholds>): void {
    this.thresholds = { ...this.thresholds, ...newThresholds };
  }

  private startCleanupInterval(): void {
    // Clean up old metrics every 10 minutes
    this.cleanupInterval = setInterval(() => {
      const cutoff = Date.now() - (24 * 60 * 60 * 1000); // 24 hours ago

      for (const [name, metrics] of this.metrics.entries()) {
        const filtered = metrics.filter(m => m.timestamp > cutoff);
        if (filtered.length !== metrics.length) {
          this.metrics.set(name, filtered);
        }
      }
    }, 10 * 60 * 1000) as any;
  }

  destroy(): void {
    if (this.cleanupInterval) {
      clearInterval(this.cleanupInterval);
      this.cleanupInterval = null;
    }

    this.metrics.clear();
    this.activeTimings.clear();
  }
}
