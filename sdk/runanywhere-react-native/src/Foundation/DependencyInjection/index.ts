/**
 * DependencyInjection module exports
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Foundation/DependencyInjection/
 */

// Service Registry - factory pattern for service creation
export {
  ServiceRegistry,
  type ServiceRegistration,
  createServiceRegistration,
  type STTServiceFactory,
  type LLMServiceFactory,
  type TTSServiceFactory,
  type VADServiceFactory,
  type VADService,
  type SpeakerDiarizationServiceFactory,
  ProviderNotFoundError,
} from './ServiceRegistry';

// Service Container - lazy initialization of services
export { ServiceContainer } from './ServiceContainer';

// Adapter Registry - framework adapters
export { AdapterRegistry } from './AdapterRegistry';

// Re-export AuthenticationProvider from Data/Network for convenience
export type { AuthenticationProvider } from '../../Data/Network';
