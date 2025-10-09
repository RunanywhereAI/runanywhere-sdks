import { EventEmitter } from 'eventemitter3';
import { Result } from '../types/result';
import { InitializationError } from '../errors/base';
import { logger } from '../utils/logger';

/**
 * Modern service token using Symbols for type safety
 */
export const ServiceToken = (_name: string): symbol => Symbol.for(_name);

/**
 * Service lifecycle types
 */
export type ServiceLifecycle = 'singleton' | 'transient' | 'scoped';

/**
 * Service factory function
 */
export type ServiceFactory<T = any> = (container: DIContainer) => T | Promise<T>;

/**
 * Service registration options
 */
export interface ServiceOptions<T = any> {
  factory: ServiceFactory<T>;
  lifecycle?: ServiceLifecycle;
  eager?: boolean; // Initialize immediately
  healthCheck?: () => boolean | Promise<boolean>;
}

/**
 * Service health status
 */
export interface ServiceHealth {
  healthy: boolean;
  lastCheck: Date;
  message?: string;
}

/**
 * Modern DI Container using latest web patterns
 * - Symbol-based tokens for type safety
 * - Async initialization support
 * - Health monitoring
 * - Event-driven lifecycle
 */
export class DIContainer extends EventEmitter {
  private readonly services = new Map<symbol, ServiceOptions>();
  private readonly singletons = new Map<symbol, any>();
  private readonly health = new Map<symbol, ServiceHealth>();
  private readonly initializing = new WeakSet<ServiceOptions>();

  /**
   * Register a service with type-safe token
   */
  register<T>(token: symbol, options: ServiceOptions<T>): this {
    this.services.set(token, {
      lifecycle: 'singleton',
      eager: false,
      ...options
    });

    logger.debug(`Service registered: ${token.description}`, 'DIContainer');

    // Eager initialization if requested
    if (options.eager) {
      this.resolve(token).catch(error => {
        logger.error(`Failed to eager-load service: ${token.description}`, 'DIContainer', { error });
      });
    }

    return this;
  }

  /**
   * Register multiple services at once (fluent API)
   */
  registerAll(services: Array<[symbol, ServiceOptions]>): this {
    services.forEach(([token, options]) => this.register(token, options));
    return this;
  }

  /**
   * Resolve a service asynchronously
   */
  async resolve<T>(token: symbol): Promise<T> {
    const options = this.services.get(token);

    if (!options) {
      throw new InitializationError(`Service not found: ${token.description}`);
    }

    // Handle different lifecycles
    switch (options.lifecycle) {
      case 'singleton':
        return this.resolveSingleton<T>(token, options);
      case 'transient':
        return this.createInstance<T>(options);
      case 'scoped':
        // For scoped, we'd need a scope context - simplified for now
        return this.createInstance<T>(options);
      default:
        return this.resolveSingleton<T>(token, options);
    }
  }

  /**
   * Try to resolve a service, returning Result type
   */
  async tryResolve<T>(token: symbol): Promise<Result<T, Error>> {
    try {
      const service = await this.resolve<T>(token);
      return Result.ok(service);
    } catch (error) {
      return Result.err(error instanceof Error ? error : new Error(String(error)));
    }
  }

  /**
   * Check if a service is registered
   */
  has(token: symbol): boolean {
    return this.services.has(token);
  }

  /**
   * Resolve singleton service
   */
  private async resolveSingleton<T>(token: symbol, options: ServiceOptions): Promise<T> {
    // Return existing singleton
    if (this.singletons.has(token)) {
      return this.singletons.get(token) as T;
    }

    // Prevent circular dependencies
    if (this.initializing.has(options)) {
      throw new InitializationError(`Circular dependency detected: ${token.description}`);
    }

    this.initializing.add(options);

    try {
      const instance = await this.createInstance<T>(options);
      this.singletons.set(token, instance);

      // Update health status
      this.health.set(token, {
        healthy: true,
        lastCheck: new Date()
      });

      // Emit lifecycle event
      this.emit('service:initialized', { token, instance });

      logger.info(`Service initialized: ${token.description}`, 'DIContainer');

      return instance;
    } finally {
      this.initializing.delete(options);
    }
  }

  /**
   * Create a new service instance
   */
  private async createInstance<T>(options: ServiceOptions): Promise<T> {
    try {
      const instance = await options.factory(this);
      return instance as T;
    } catch (error) {
      const errorMessage = error instanceof Error ? error.message : String(error);
      throw new InitializationError(`Failed to create service: ${errorMessage}`);
    }
  }

  /**
   * Run health checks for all services
   */
  async checkHealth(): Promise<Map<symbol, ServiceHealth>> {
    const healthChecks: Array<Promise<[symbol, ServiceHealth]>> = [];

    for (const [token, options] of this.services) {
      if (options.healthCheck && this.singletons.has(token)) {
        healthChecks.push(
          this.runHealthCheck(token, options.healthCheck)
        );
      }
    }

    const results = await Promise.all(healthChecks);
    results.forEach(([token, health]) => {
      this.health.set(token, health);
    });

    return new Map(this.health);
  }

  /**
   * Run health check for a specific service
   */
  private async runHealthCheck(
    token: symbol,
    healthCheck: () => boolean | Promise<boolean>
  ): Promise<[symbol, ServiceHealth]> {
    try {
      const healthy = await healthCheck();
      return [token, {
        healthy,
        lastCheck: new Date()
      }];
    } catch (error) {
      return [token, {
        healthy: false,
        lastCheck: new Date(),
        message: error instanceof Error ? error.message : String(error)
      }];
    }
  }

  /**
   * Get current health status
   */
  getHealth(): Map<symbol, ServiceHealth> {
    return new Map(this.health);
  }

  /**
   * Clear all services and instances
   */
  clear(): void {
    // Clean up singletons
    this.singletons.clear();
    this.services.clear();
    this.health.clear();
    this.removeAllListeners();

    logger.info('Container cleared', 'DIContainer');
  }

  /**
   * Create a scoped container (useful for request-scoped services)
   */
  createScope(): DIContainer {
    const scoped = new DIContainer();

    // Copy service definitions but not instances
    for (const [token, options] of this.services) {
      scoped.services.set(token, options);
    }

    return scoped;
  }
}

/**
 * Global container instance
 */
export const container = new DIContainer();

/**
 * Service decorator for class-based services (optional, modern pattern)
 * Usage: @Service(MyServiceToken)
 */
export function Service(token: symbol, options?: Partial<ServiceOptions>) {
  return function (constructor: any) {
    container.register(token, {
      factory: (c) => new constructor(c),
      ...options
    });
  };
}
