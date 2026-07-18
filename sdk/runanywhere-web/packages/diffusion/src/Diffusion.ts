import {
  SDKLogger,
  setDiffusionAvailabilityProvider,
  type BackendRegistrationState,
} from '@runanywhere/web/backend';

const logger = new SDKLogger('Diffusion');

export interface DiffusionRegisterOptions {
  /** Preferred engine when a Web diffusion module is shipped. */
  acceleration?: 'auto' | 'webgpu' | 'cpu';
  /** Reserved URL for the future Emscripten/WebGPU loader. */
  wasmUrl?: string;
}

export interface DiffusionAvailability {
  available: false;
  reason: string;
  acceleration?: 'auto' | 'webgpu' | 'cpu';
}

let registrationState: BackendRegistrationState = 'unregistered';
let requestedAcceleration: DiffusionRegisterOptions['acceleration'];

const ENGINE_NOT_SHIPPED =
  'Web diffusion is not available: no WebGPU/WASM diffusion engine has been shipped.';

/**
 * Honest registration shell for the future Web diffusion backend.
 *
 * This intentionally does not call `registerWasmModule(['diffusion'], ...)`:
 * registering a capability without a real WASM module would make core adapters
 * advertise an engine that does not exist. The installed public-facade provider
 * reports the same unavailable state until a real loader replaces it.
 */
export const Diffusion = {
  get moduleId(): string {
    return 'diffusion';
  },

  get isRegistered(): boolean {
    return registrationState === 'registered';
  },

  get registrationState(): BackendRegistrationState {
    return registrationState;
  },

  availability(): DiffusionAvailability {
    return {
      available: false,
      reason: ENGINE_NOT_SHIPPED,
      ...(requestedAcceleration ? { acceleration: requestedAcceleration } : {}),
    };
  },

  async register(options: DiffusionRegisterOptions = {}): Promise<void> {
    requestedAcceleration = options.acceleration ?? 'auto';
    registrationState = 'registering';

    // The provider lets RunAnywhere.diffusion.availability() describe the
    // package's registered shell, without treating this shell as a capability.
    setDiffusionAvailabilityProvider(() => Diffusion.availability());
    registrationState = 'registered';
    logger.info(
      `Diffusion registration shell installed (${requestedAcceleration}); ${ENGINE_NOT_SHIPPED}`,
    );
  },

  unregister(): void {
    setDiffusionAvailabilityProvider(null);
    requestedAcceleration = undefined;
    registrationState = 'unregistered';
  },
};
