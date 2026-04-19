/**
 * ServiceContainer.ts
 *
 * Service container for managing SDK services.
 * Simplified to work with native HTTP transport.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/DI/
 */

import { SDKLogger } from '../Logging/Logger/SDKLogger';
import {
  HTTPService,
  SDKEnvironment,
} from '../../services/Network';

const logger = new SDKLogger('ServiceContainer');

/**
 * Service container for SDK dependency management
 * Manages network configuration and service lifecycle
 */
export class ServiceContainer {
  public static shared: ServiceContainer = new ServiceContainer();

  private _apiKey?: string;
  private _baseURL?: string;
  private _environment: SDKEnvironment = SDKEnvironment.Development;
  private _isInitialized: boolean = false;

  public constructor() {}

  // ==========================================================================
  // API Configuration
  // ==========================================================================

  /**
   * Store API configuration
   *
   * @param apiKey API key for authentication
   * @param environment SDK environment
   * @param baseURL Optional base URL for production/staging
   */
  public setAPIConfig(
    apiKey: string,
    environment: SDKEnvironment | string,
    baseURL?: string
  ): void {
    this._apiKey = apiKey;
    this._baseURL = baseURL;

    // Convert string to enum if needed
    if (typeof environment === 'string') {
      this._environment = this.parseEnvironment(environment);
    } else {
      this._environment = environment;
    }

    logger.debug(`API config stored: env=${this.environmentString}`);
  }

  // ==========================================================================
  // Service Access
  // ==========================================================================

  /**
   * Get the HTTP service instance
   * Note: HTTP is primarily handled by native layer
   */
  public get httpService(): HTTPService {
    return HTTPService.shared;
  }

  // ==========================================================================
  // Getters
  // ==========================================================================

  public get apiKey(): string | undefined {
    return this._apiKey;
  }

  public get baseURL(): string | undefined {
    return this._baseURL;
  }

  public get environment(): SDKEnvironment {
    return this._environment;
  }

  public get environmentString(): string {
    switch (this._environment) {
      case SDKEnvironment.Development:
        return 'development';
      case SDKEnvironment.Staging:
        return 'staging';
      case SDKEnvironment.Production:
        return 'production';
      default:
        return 'unknown';
    }
  }

  public get isInitialized(): boolean {
    return this._isInitialized;
  }

  // ==========================================================================
  // Initialization
  // ==========================================================================

  /**
   * Mark services as initialized
   */
  public markInitialized(): void {
    this._isInitialized = true;
    logger.debug('ServiceContainer marked as initialized');
  }

  /**
   * Reset all services (for testing or SDK destruction)
   */
  public reset(): void {
    this._apiKey = undefined;
    this._baseURL = undefined;
    this._environment = SDKEnvironment.Development;
    this._isInitialized = false;

    logger.debug('ServiceContainer reset');
  }

  // ==========================================================================
  // Private Helpers
  // ==========================================================================

  private parseEnvironment(env: string): SDKEnvironment {
    const normalized = env.toLowerCase();
    switch (normalized) {
      case 'development':
      case 'dev':
      case '0':
        return SDKEnvironment.Development;
      case 'staging':
      case 'stage':
      case '1':
        return SDKEnvironment.Staging;
      case 'production':
      case 'prod':
      case '2':
        return SDKEnvironment.Production;
      default:
        logger.warning(`Unknown environment '${env}', defaulting to Development`);
        return SDKEnvironment.Development;
    }
  }
}
