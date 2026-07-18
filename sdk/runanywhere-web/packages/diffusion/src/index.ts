/**
 * @runanywhere/web-diffusion
 *
 * Registration shell for the future WebGPU/WASM diffusion engine. Importing
 * this package never claims image-generation support: that becomes available
 * only once a real diffusion module is loaded and registered.
 */

export { Diffusion } from './Diffusion.js';
export type {
  DiffusionAvailability,
  DiffusionRegisterOptions,
} from './Diffusion.js';
export type { BackendRegistrationState } from '@runanywhere/web/backend';
