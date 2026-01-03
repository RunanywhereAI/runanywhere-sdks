/**
 * ServiceContainer.ts
 *
 * Simplified service container.
 * Most services are now in native commons.
 */

import { SDKLogger } from '../Logging/Logger/SDKLogger';

const logger = new SDKLogger('ServiceContainer');

/**
 * Minimal service container
 * Business logic is in native commons
 */
export class ServiceContainer {
  public static shared: ServiceContainer = new ServiceContainer();

  private _apiKey?: string;
  private _environment?: string;

  public constructor() {}

  /**
   * Store API configuration (used by native)
   */
  public setAPIConfig(apiKey: string, environment: string): void {
    this._apiKey = apiKey;
    this._environment = environment;
    logger.debug('API config stored');
  }

  public get apiKey(): string | undefined {
    return this._apiKey;
  }

  public get environment(): string | undefined {
    return this._environment;
  }

  /**
   * Reset (for testing)
   */
  public reset(): void {
    this._apiKey = undefined;
    this._environment = undefined;
    logger.debug('ServiceContainer reset');
  }
}
