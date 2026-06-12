/**
 * Initialization Phase
 *
 * Mirrors the two-phase initialization pattern in
 * `sdk/runanywhere-swift/Sources/RunAnywhere/Public/RunAnywhere.swift`.
 *
 * Phase 1 (Core): native commons performs synchronous bootstrap; React Native
 * still awaits the async Nitro bridge to satisfy this phase.
 *
 * Phase 2 (Services): asynchronous startup of network/auth/device services.
 */

export enum InitializationPhase {
  NotInitialized = 'notInitialized',
  CoreInitialized = 'coreInitialized',
  ServicesInitializing = 'servicesInitializing',
  FullyInitialized = 'fullyInitialized',
  Failed = 'failed',
}
