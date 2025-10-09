import { Result } from '../types/result'
import { logger } from '../utils/logger'
import {
  AdapterType,
  AdapterConstructor,
  AdapterInfo,
  VADAdapter,
  STTAdapter,
  LLMAdapter,
  TTSAdapter
} from '../interfaces'

type AdapterMap = {
  [AdapterType.VAD]: VADAdapter
  [AdapterType.STT]: STTAdapter
  [AdapterType.LLM]: LLMAdapter
  [AdapterType.TTS]: TTSAdapter
}

export class ServiceRegistry {
  private static instance: ServiceRegistry
  private adapters = new Map<AdapterType, Map<string, AdapterConstructor>>()
  private instances = new Map<string, any>()

  private constructor() {}

  static getInstance(): ServiceRegistry {
    if (!ServiceRegistry.instance) {
      ServiceRegistry.instance = new ServiceRegistry()
    }
    return ServiceRegistry.instance
  }

  register<T extends AdapterType>(
    type: T,
    id: string,
    adapter: AdapterConstructor<AdapterMap[T]>
  ): void {
    if (!this.adapters.has(type)) {
      this.adapters.set(type, new Map())
    }

    const typeAdapters = this.adapters.get(type)!
    if (typeAdapters.has(id)) {
      logger.warn(`Adapter ${type}:${id} already registered, overwriting`, 'ServiceRegistry')
    }

    typeAdapters.set(id, adapter)
    logger.info(`Registered adapter ${type}:${id}`, 'ServiceRegistry', {
      name: adapter.metadata.name,
      version: adapter.metadata.version
    })
  }

  async create<T extends AdapterType>(
    type: T,
    id: string,
    config?: any
  ): Promise<Result<AdapterMap[T], Error>> {
    const instanceKey = `${type}:${id}`

    // Return existing instance if already created
    if (this.instances.has(instanceKey)) {
      return Result.ok(this.instances.get(instanceKey))
    }

    const AdapterClass = this.adapters.get(type)?.get(id)
    if (!AdapterClass) {
      return Result.err(new Error(`Adapter ${type}:${id} not registered`))
    }

    try {
      logger.debug(`Creating adapter instance ${type}:${id}`, 'ServiceRegistry')

      const instance = new AdapterClass(config) as AdapterMap[T]
      const initResult = await instance.initialize(config)

      if (!initResult.success) {
        return Result.err(initResult.error)
      }

      this.instances.set(instanceKey, instance)

      logger.info(`Created adapter instance ${type}:${id}`, 'ServiceRegistry')
      return Result.ok(instance)

    } catch (error) {
      const err = error instanceof Error ? error : new Error(String(error))
      logger.error(`Failed to create adapter ${type}:${id}: ${err.message}`, 'ServiceRegistry')
      return Result.err(err)
    }
  }

  getInstance<T extends AdapterType>(
    type: T,
    id: string
  ): AdapterMap[T] | null {
    const instanceKey = `${type}:${id}`
    return this.instances.get(instanceKey) || null
  }

  getAvailable(type: AdapterType): AdapterInfo[] {
    const adapters = this.adapters.get(type)
    if (!adapters) return []

    return Array.from(adapters.entries()).map(([id, AdapterClass]) => ({
      id,
      name: AdapterClass.metadata.name,
      version: AdapterClass.metadata.version,
      description: AdapterClass.metadata.description
    }))
  }

  isRegistered(type: AdapterType, id: string): boolean {
    return this.adapters.get(type)?.has(id) || false
  }

  unregister(type: AdapterType, id: string): boolean {
    const typeAdapters = this.adapters.get(type)
    if (!typeAdapters) return false

    const removed = typeAdapters.delete(id)
    if (removed) {
      // Also destroy any existing instance
      const instanceKey = `${type}:${id}`
      const instance = this.instances.get(instanceKey)
      if (instance && typeof instance.destroy === 'function') {
        instance.destroy()
      }
      this.instances.delete(instanceKey)

      logger.info(`Unregistered adapter ${type}:${id}`, 'ServiceRegistry')
    }

    return removed
  }

  destroyAll(): void {
    // Destroy all instances
    for (const [key, instance] of this.instances.entries()) {
      if (typeof instance.destroy === 'function') {
        try {
          instance.destroy()
          logger.debug(`Destroyed instance ${key}`, 'ServiceRegistry')
        } catch (error) {
          logger.error(`Error destroying instance ${key}: ${error}`, 'ServiceRegistry')
        }
      }
    }

    this.instances.clear()
    this.adapters.clear()

    logger.info('All adapters destroyed and registry cleared', 'ServiceRegistry')
  }

  reset(): void {
    this.destroyAll()
    ServiceRegistry.instance = new ServiceRegistry()
  }
}
