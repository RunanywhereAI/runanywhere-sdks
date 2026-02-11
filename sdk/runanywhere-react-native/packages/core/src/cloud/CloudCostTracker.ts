/**
 * CloudCostTracker.ts
 *
 * Tracks cumulative cloud API costs across requests.
 * Mirrors Swift CloudCostTracker.swift exactly.
 */

// ============================================================================
// Cloud Cost Summary
// ============================================================================

export interface CloudCostSummary {
  totalCostUSD: number;
  totalInputTokens: number;
  totalOutputTokens: number;
  totalRequests: number;
  requestsByProvider: Record<string, number>;
  costByProvider: Record<string, number>;
}

// ============================================================================
// Cloud Cost Tracker
// ============================================================================

/**
 * Tracks cumulative cloud API costs for budget monitoring.
 *
 * Usage:
 * ```typescript
 * const costs = CloudCostTracker.shared.summary;
 * console.log(`Total cloud cost: $${costs.totalCostUSD}`);
 * ```
 */
export class CloudCostTracker {
  static readonly shared = new CloudCostTracker();

  private _totalCostUSD = 0;
  private _totalInputTokens = 0;
  private _totalOutputTokens = 0;
  private _totalRequests = 0;
  private _requestsByProvider: Record<string, number> = {};
  private _costByProvider: Record<string, number> = {};

  private constructor() {}

  // ============================================================================
  // Recording
  // ============================================================================

  /** Record a cloud request cost */
  recordRequest(
    providerId: string,
    inputTokens: number,
    outputTokens: number,
    costUSD: number,
  ): void {
    this._totalCostUSD += costUSD;
    this._totalInputTokens += inputTokens;
    this._totalOutputTokens += outputTokens;
    this._totalRequests += 1;
    this._requestsByProvider[providerId] =
      (this._requestsByProvider[providerId] ?? 0) + 1;
    this._costByProvider[providerId] =
      (this._costByProvider[providerId] ?? 0) + costUSD;
  }

  // ============================================================================
  // Querying
  // ============================================================================

  /** Get cost summary */
  get summary(): CloudCostSummary {
    return {
      totalCostUSD: this._totalCostUSD,
      totalInputTokens: this._totalInputTokens,
      totalOutputTokens: this._totalOutputTokens,
      totalRequests: this._totalRequests,
      requestsByProvider: { ...this._requestsByProvider },
      costByProvider: { ...this._costByProvider },
    };
  }

  /** Reset all tracked costs */
  reset(): void {
    this._totalCostUSD = 0;
    this._totalInputTokens = 0;
    this._totalOutputTokens = 0;
    this._totalRequests = 0;
    this._requestsByProvider = {};
    this._costByProvider = {};
  }

  /** Check if adding a cost would exceed a budget */
  wouldExceedBudget(costUSD: number, budgetUSD: number): boolean {
    if (budgetUSD <= 0) return false;
    return this._totalCostUSD + costUSD > budgetUSD;
  }
}
