export interface MetricStats {
  count: number;
  min: number;
  max: number;
  mean: number;
  median: number;
  p95: number;
  p99: number;
}

export class PerformanceMonitor {
  private metrics = new Map<string, number[]>();
  private marks = new Map<string, number>();

  mark(name: string): void {
    this.marks.set(name, performance.now());
  }

  measure(name: string, startMark: string, endMark?: string): number {
    const start = this.marks.get(startMark);
    if (!start) {
      throw new Error(`Start mark '${startMark}' not found`);
    }

    const end = endMark ? this.marks.get(endMark) : performance.now();
    if (endMark && !end) {
      throw new Error(`End mark '${endMark}' not found`);
    }

    const duration = (end || performance.now()) - start;

    // Store metric
    if (!this.metrics.has(name)) {
      this.metrics.set(name, []);
    }
    this.metrics.get(name)!.push(duration);

    // Keep only last 100 measurements
    const measurements = this.metrics.get(name)!;
    if (measurements.length > 100) {
      measurements.shift();
    }

    return duration;
  }

  getMetrics(name: string): MetricStats | null {
    const measurements = this.metrics.get(name);
    if (!measurements || measurements.length === 0) {
      return null;
    }

    const sorted = [...measurements].sort((a, b) => a - b);
    const count = sorted.length;
    const sum = sorted.reduce((a, b) => a + b, 0);

    return {
      count,
      min: sorted[0]!,
      max: sorted[count - 1]!,
      mean: sum / count,
      median: sorted[Math.floor(count / 2)]!,
      p95: sorted[Math.floor(count * 0.95)]!,
      p99: sorted[Math.floor(count * 0.99)]!
    };
  }

  getAllMetrics(): Map<string, MetricStats> {
    const allStats = new Map<string, MetricStats>();

    for (const [name] of this.metrics) {
      const stats = this.getMetrics(name);
      if (stats) {
        allStats.set(name, stats);
      }
    }

    return allStats;
  }

  clear(): void {
    this.metrics.clear();
    this.marks.clear();
  }

  clearMetric(name: string): void {
    this.metrics.delete(name);
  }

  clearMark(name: string): void {
    this.marks.delete(name);
  }
}
