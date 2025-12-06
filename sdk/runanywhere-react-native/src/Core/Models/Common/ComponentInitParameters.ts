/**
 * ComponentInitParameters.ts
 *
 * Base protocol for all component initialization parameters
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Models/ComponentInitializationParameters.swift
 */

import type { SDKComponent } from './SDKComponent';

/**
 * Base protocol for all component initialization parameters
 */
export interface ComponentInitParameters {
  /**
   * The component type this configuration is for
   */
  readonly componentType: SDKComponent;

  /**
   * Model ID if required by the component
   */
  readonly modelId?: string | null;

  /**
   * Validate the parameters
   * @throws Error if validation fails
   */
  validate(): void;
}

/**
 * Empty component parameters for components that don't need specific parameters
 */
export class EmptyComponentParameters implements ComponentInitParameters {
  public readonly componentType: SDKComponent;
  public readonly modelId?: string | null = null;

  constructor(componentType: SDKComponent) {
    this.componentType = componentType;
  }

  public validate(): void {
    // No validation needed for empty parameters
  }
}

