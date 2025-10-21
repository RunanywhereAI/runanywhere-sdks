// Error tracking and recovery for RunAnywhere Web Voice Pipeline

export interface ErrorContext {
  component: 'VAD' | 'STT' | 'LLM' | 'TTS' | 'Pipeline' | 'Network' | 'Storage' | 'Other';
  operation?: string;
  metadata?: Record<string, any>;
  userId?: string;
  sessionId?: string;
  userAgent?: string;
  url?: string;
}

export interface ErrorReport {
  id: string;
  timestamp: number;
  error: {
    name: string;
    message: string;
    stack?: string;
  };
  context: ErrorContext;
  severity: 'low' | 'medium' | 'high' | 'critical';
  recovered: boolean;
  recoveryAction?: string;
  userImpact: 'none' | 'minor' | 'major' | 'blocking';
  fingerprint: string; // For deduplication
}

export interface RecoveryStrategy {
  component: ErrorContext['component'];
  errorType: string;
  action: (error: Error, context: ErrorContext) => Promise<boolean>;
  maxRetries?: number;
  backoffMs?: number;
}

export interface ErrorTrackerConfig {
  reportToServer: boolean;
  serverEndpoint?: string;
  maxReports: number;
  enableAutoRecovery: boolean;
  enableConsoleLogging: boolean;
  sessionId?: string;
}

export class ErrorTracker {
  private errors: ErrorReport[] = [];
  private config: ErrorTrackerConfig;
  private recoveryStrategies = new Map<string, RecoveryStrategy>();
  private retryCount = new Map<string, number>();
  private sessionId: string;

  constructor(config: Partial<ErrorTrackerConfig> = {}) {
    this.config = {
      reportToServer: false,
      maxReports: 100,
      enableAutoRecovery: true,
      enableConsoleLogging: true,
      ...config
    };

    this.sessionId = config.sessionId || this.generateSessionId();
    this.setupGlobalErrorHandling();
    this.registerDefaultRecoveryStrategies();
  }

  track(
    error: Error,
    context: ErrorContext,
    severity: ErrorReport['severity'] = 'medium',
    userImpact: ErrorReport['userImpact'] = 'minor'
  ): string {
    const errorId = crypto.randomUUID();
    const fingerprint = this.generateErrorFingerprint(error, context);

    const report: ErrorReport = {
      id: errorId,
      timestamp: Date.now(),
      error: {
        name: error.name,
        message: error.message,
        ...(error.stack && { stack: error.stack })
      },
      context: {
        ...context,
        sessionId: this.sessionId,
        ...(typeof navigator !== 'undefined' && navigator.userAgent && { userAgent: navigator.userAgent }),
        ...(typeof window !== 'undefined' && window.location.href && { url: window.location.href })
      },
      severity,
      recovered: false,
      userImpact,
      fingerprint
    };

    this.errors.push(report);

    // Keep only recent errors
    if (this.errors.length > this.config.maxReports) {
      this.errors.shift();
    }

    if (this.config.enableConsoleLogging) {
      console.error(`[ErrorTracker] ${severity.toUpperCase()}: ${error.message}`, {
        errorId,
        context,
        error
      });
    }

    // Attempt recovery if enabled
    if (this.config.enableAutoRecovery) {
      this.attemptRecovery(error, context, errorId);
    }

    // Report to server if configured
    if (this.config.reportToServer && this.config.serverEndpoint) {
      this.sendErrorReport(report);
    }

    return errorId;
  }

  registerRecoveryStrategy(strategy: RecoveryStrategy): void {
    const key = `${strategy.component}-${strategy.errorType}`;
    this.recoveryStrategies.set(key, strategy);
  }

  private async attemptRecovery(error: Error, context: ErrorContext, errorId: string): Promise<void> {
    const strategiesForComponent = Array.from(this.recoveryStrategies.values())
      .filter(s => s.component === context.component);

    for (const strategy of strategiesForComponent) {
      const retryKey = `${errorId}-${strategy.component}-${strategy.errorType}`;
      const currentRetries = this.retryCount.get(retryKey) || 0;
      const maxRetries = strategy.maxRetries || 3;

      if (currentRetries >= maxRetries) {
        continue;
      }

      try {
        if (strategy.backoffMs) {
          await new Promise(resolve => setTimeout(resolve, strategy.backoffMs! * (currentRetries + 1)));
        }

        const recovered = await strategy.action(error, context);

        if (recovered) {
          this.markRecovered(errorId, `${strategy.component} recovery successful`);
          this.retryCount.delete(retryKey);
          return;
        }

        this.retryCount.set(retryKey, currentRetries + 1);
      } catch (recoveryError) {
        console.warn(`[ErrorTracker] Recovery failed for ${strategy.component}:`, recoveryError);
        this.retryCount.set(retryKey, currentRetries + 1);
      }
    }
  }

  private markRecovered(errorId: string, recoveryAction: string): void {
    const errorReport = this.errors.find(e => e.id === errorId);
    if (errorReport) {
      errorReport.recovered = true;
      errorReport.recoveryAction = recoveryAction;

      if (this.config.enableConsoleLogging) {
        console.info(`[ErrorTracker] Recovered from error ${errorId}: ${recoveryAction}`);
      }
    }
  }

  getErrors(options: {
    component?: ErrorContext['component'];
    severity?: ErrorReport['severity'];
    recovered?: boolean;
    limit?: number;
  } = {}): ErrorReport[] {
    let filtered = this.errors;

    if (options.component) {
      filtered = filtered.filter(e => e.context.component === options.component);
    }

    if (options.severity) {
      filtered = filtered.filter(e => e.severity === options.severity);
    }

    if (options.recovered !== undefined) {
      filtered = filtered.filter(e => e.recovered === options.recovered);
    }

    // Sort by timestamp (most recent first)
    filtered = filtered.sort((a, b) => b.timestamp - a.timestamp);

    if (options.limit) {
      filtered = filtered.slice(0, options.limit);
    }

    return filtered;
  }

  getErrorStats(): {
    total: number;
    recovered: number;
    byComponent: Record<string, number>;
    bySeverity: Record<string, number>;
    recentErrors: number; // Last hour
    errorRate: number; // Errors per minute over last hour
  } {
    const now = Date.now();
    const oneHourAgo = now - (60 * 60 * 1000);
    const recentErrors = this.errors.filter(e => e.timestamp > oneHourAgo);

    const byComponent: Record<string, number> = {};
    const bySeverity: Record<string, number> = {};

    for (const error of this.errors) {
      byComponent[error.context.component] = (byComponent[error.context.component] || 0) + 1;
      bySeverity[error.severity] = (bySeverity[error.severity] || 0) + 1;
    }

    return {
      total: this.errors.length,
      recovered: this.errors.filter(e => e.recovered).length,
      byComponent,
      bySeverity,
      recentErrors: recentErrors.length,
      errorRate: recentErrors.length / 60 // Errors per minute
    };
  }

  clearErrors(): void {
    this.errors = [];
    this.retryCount.clear();
  }

  private registerDefaultRecoveryStrategies(): void {
    // VAD Recovery
    this.registerRecoveryStrategy({
      component: 'VAD',
      errorType: 'ModelLoadError',
      action: async (error, context) => {
        console.info('[ErrorTracker] Attempting VAD model reload...');
        // Placeholder - actual implementation would reload VAD model
        return false; // Indicate recovery attempt failed
      },
      maxRetries: 2,
      backoffMs: 1000
    });

    // STT Recovery
    this.registerRecoveryStrategy({
      component: 'STT',
      errorType: 'TranscriptionError',
      action: async (error, context) => {
        console.info('[ErrorTracker] Attempting STT fallback...');
        // Placeholder - actual implementation would try alternative STT model
        return false;
      },
      maxRetries: 1
    });

    // LLM Recovery
    this.registerRecoveryStrategy({
      component: 'LLM',
      errorType: 'NetworkError',
      action: async (error, context) => {
        console.info('[ErrorTracker] Attempting LLM request retry...');
        // Placeholder - actual implementation would retry LLM request
        return false;
      },
      maxRetries: 3,
      backoffMs: 2000
    });

    // TTS Recovery
    this.registerRecoveryStrategy({
      component: 'TTS',
      errorType: 'SynthesisError',
      action: async (error, context) => {
        console.info('[ErrorTracker] Attempting TTS fallback...');
        // Placeholder - actual implementation would try Web Speech API fallback
        return false;
      },
      maxRetries: 1
    });

    // Network Recovery
    this.registerRecoveryStrategy({
      component: 'Network',
      errorType: 'ConnectionError',
      action: async (error, context) => {
        console.info('[ErrorTracker] Waiting for network recovery...');

        // Wait for network to come back online
        if (typeof navigator !== 'undefined' && 'onLine' in navigator) {
          return new Promise(resolve => {
            const checkOnline = () => {
              if (navigator.onLine) {
                resolve(true);
              } else {
                setTimeout(checkOnline, 1000);
              }
            };
            checkOnline();
          });
        }

        return false;
      },
      maxRetries: 5,
      backoffMs: 5000
    });
  }

  private setupGlobalErrorHandling(): void {
    if (typeof window !== 'undefined') {
      // Handle unhandled promise rejections
      window.addEventListener('unhandledrejection', (event) => {
        this.track(
          new Error(event.reason),
          { component: 'Other', operation: 'unhandledRejection' },
          'high',
          'major'
        );
      });

      // Handle global errors
      window.addEventListener('error', (event) => {
        this.track(
          event.error || new Error(event.message),
          { component: 'Other', operation: 'globalError' },
          'high',
          'major'
        );
      });
    }
  }

  private generateErrorFingerprint(error: Error, context: ErrorContext): string {
    // Create a hash-like fingerprint for error deduplication
    const key = `${error.name}-${error.message}-${context.component}-${context.operation}`;
    return btoa(key).substring(0, 16);
  }

  private generateSessionId(): string {
    return `session-${Date.now()}-${Math.random().toString(36).substr(2, 9)}`;
  }

  private async sendErrorReport(report: ErrorReport): Promise<void> {
    if (!this.config.serverEndpoint) return;

    try {
      await fetch(this.config.serverEndpoint, {
        method: 'POST',
        headers: {
          'Content-Type': 'application/json'
        },
        body: JSON.stringify(report)
      });
    } catch (error) {
      console.warn('[ErrorTracker] Failed to send error report:', error);
    }
  }

  destroy(): void {
    this.errors = [];
    this.retryCount.clear();
    this.recoveryStrategies.clear();
  }
}
