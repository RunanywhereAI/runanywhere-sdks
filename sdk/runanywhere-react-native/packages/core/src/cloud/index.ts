/**
 * Cloud module - Cloud provider infrastructure and routing engine.
 *
 * Re-exports all cloud types, providers, and routing functionality.
 */

// Types
export {
  RoutingMode,
  CloudExecutionTarget,
  HandoffReason,
  DEFAULT_ROUTING_POLICY,
  LOCAL_ONLY_POLICY,
  CLOUD_ONLY_POLICY,
  hybridAutoPolicy,
  hybridManualPolicy,
} from './CloudTypes';
export type {
  CloudRoutingPolicy,
  RoutingDecision,
  CloudGenerationOptions,
  CloudGenerationResult,
  RoutedGenerationResult,
  RoutedStreamingResult,
} from './CloudTypes';

// Provider interface
export type { CloudProvider } from './CloudProvider';

// OpenAI-compatible provider
export { OpenAICompatibleProvider, CloudProviderError, CloudProviderErrorType } from './OpenAICompatibleProvider';
export type { OpenAICompatibleProviderConfig } from './OpenAICompatibleProvider';

// Provider manager
export { CloudProviderManager } from './CloudProviderManager';

// Routing engine
export { RoutingEngine } from './RoutingEngine';

// Cost tracking
export { CloudCostTracker } from './CloudCostTracker';
export type { CloudCostSummary } from './CloudCostTracker';

// Provider failover chain
export { ProviderFailoverChain } from './ProviderFailoverChain';
export type { ProviderHealthStatus } from './ProviderFailoverChain';

// Routing telemetry
export type {
  RoutingEvent,
  CloudCostEvent,
  ProviderFailoverEvent,
  LatencyTimeoutEvent,
  CloudTelemetryEvent,
} from './RoutingTelemetry';
