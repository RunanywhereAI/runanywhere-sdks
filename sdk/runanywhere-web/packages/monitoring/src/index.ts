// RunAnywhere Web Monitoring Package
// Provides performance monitoring and error tracking

// Performance Monitor exports
export { PerformanceMonitor } from './monitoring/performance-monitor';
export type {
  Metric,
  TimingHandle,
  PerformanceReport,
  PerformanceThresholds
} from './monitoring/performance-monitor';

// Error Tracker exports
export { ErrorTracker } from './errors/error-tracker';
export type {
  ErrorContext,
  ErrorReport,
  RecoveryStrategy,
  ErrorTrackerConfig
} from './errors/error-tracker';

// Import types for use in utility functions
import type { PerformanceThresholds } from './monitoring/performance-monitor';
import type { ErrorContext, ErrorTrackerConfig } from './errors/error-tracker';
import { PerformanceMonitor } from './monitoring/performance-monitor';
import { ErrorTracker } from './errors/error-tracker';

// Utility functions for common monitoring patterns
export function createMonitoringStack(config: {
  performanceThresholds?: Partial<PerformanceThresholds>;
  errorTracking?: Partial<ErrorTrackerConfig>;
} = {}) {
  const performanceMonitor = new PerformanceMonitor(config.performanceThresholds);
  const errorTracker = new ErrorTracker(config.errorTracking);

  return {
    performanceMonitor,
    errorTracker,
    destroy: () => {
      performanceMonitor.destroy();
      errorTracker.destroy();
    }
  };
}

// Helper for timing operations with automatic error tracking
export function withMonitoring<T>(
  operation: () => Promise<T>,
  operationName: string,
  component: ErrorContext['component'],
  performanceMonitor: PerformanceMonitor,
  errorTracker: ErrorTracker
): Promise<T> {
  const timing = performanceMonitor.startTiming(operationName);

  return operation()
    .then(result => {
      timing.end();
      return result;
    })
    .catch(error => {
      timing.end();
      errorTracker.track(error, { component, operation: operationName });
      throw error;
    });
}
