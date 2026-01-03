/**
 * ServiceRegistry.ts
 *
 * Simplified service registry.
 * Service registration is now handled by native commons.
 */

import { SDKLogger } from '../Logging/Logger/SDKLogger';

const logger = new SDKLogger('ServiceRegistry');

/**
 * Minimal service registry
 * Service registration is handled by native commons
 */
export class ServiceRegistry {
  private static _instance: ServiceRegistry | null = null;
  private initialized = false;

  static get shared(): ServiceRegistry {
    if (!ServiceRegistry._instance) {
      ServiceRegistry._instance = new ServiceRegistry();
    }
    return ServiceRegistry._instance;
  }

  /**
   * Initialize (signals native to register services)
   */
  async initialize(): Promise<void> {
    if (this.initialized) return;

    logger.debug('Service registry initialized - services in native');
    this.initialized = true;
  }

  /**
   * Check if initialized
   */
  isInitialized(): boolean {
    return this.initialized;
  }

  /**
   * Reset (for testing)
   */
  reset(): void {
    this.initialized = false;
    ServiceRegistry._instance = null;
  }
}
