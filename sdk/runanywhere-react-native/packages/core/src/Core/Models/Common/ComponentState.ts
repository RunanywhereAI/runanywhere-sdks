/**
 * ComponentState.ts
 *
 * Lifecycle state of a component
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/ComponentTypes.swift
 */

/**
 * Lifecycle state of a component
 */
export enum ComponentState {
  NotInitialized = 'Not Initialized',
  Checking = 'Checking',
  DownloadRequired = 'Download Required',
  Downloading = 'Downloading',
  Downloaded = 'Downloaded',
  Initializing = 'Initializing',
  Ready = 'Ready',
  Failed = 'Failed',
  CleaningUp = 'CleaningUp', // Added for React Native cleanup state
}

/**
 * Whether the component is in a usable state
 */
export function isComponentReady(state: ComponentState): boolean {
  return state === ComponentState.Ready;
}

/**
 * Whether the component is in a transitional state
 */
export function isComponentTransitioning(state: ComponentState): boolean {
  return (
    state === ComponentState.Checking ||
    state === ComponentState.Downloading ||
    state === ComponentState.Initializing
  );
}
