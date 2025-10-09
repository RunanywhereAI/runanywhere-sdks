/**
 * Adapter exports
 * Core package only exports the base adapter and interfaces
 * Concrete implementations are in their own packages
 */

// Base Adapter
export { BaseAdapter } from './base.adapter';

// Registry for dynamic adapter registration
export { ServiceRegistry } from '../registry/service-registry';

// Import AdapterType enum
export { AdapterType } from '../interfaces';
