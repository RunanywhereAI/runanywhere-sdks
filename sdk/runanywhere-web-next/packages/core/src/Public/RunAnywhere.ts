import { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
import { EventBus } from '../Foundation/EventBus';
import { Logging, SDKLogger } from '../Foundation/SDKLogger';
import { installSDKEventTransport } from '../Adapters/SDKEventStreamAdapter';
import { registerHost, unregisterHost } from '../runtime/HostRegistry';
import { WasmWorkerHost } from '../runtime/WasmWorkerHost';

const logger = new SDKLogger('RunAnywhere');

export interface InitializeConfig {
  apiKey?: string;
  environment?: SDKEnvironment;
  baseUrl?: string;
  commonsWasmUrl?: string;
}

export class RunAnywhereSDK {
  private _initialized = false;
  private _environment: SDKEnvironment = SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
  private commonsHost: WasmWorkerHost | null = null;

  get isInitialized(): boolean {
    return this._initialized;
  }

  get environment(): SDKEnvironment {
    return this._environment;
  }

  async initialize(config: InitializeConfig = {}): Promise<void> {
    if (this._initialized) return;

    this._environment = config.environment ?? SDKEnvironment.SDK_ENVIRONMENT_DEVELOPMENT;
    Logging.applyEnvironmentConfiguration(this._environment);

    const wasmJsUrl = config.commonsWasmUrl ?? new URL('../../wasm/racommons.js', import.meta.url).href;
    const host = new WasmWorkerHost(
      () => new Worker(new URL('../worker.js', import.meta.url), { type: 'module' }),
      { moduleId: 'commons', wasmJsUrl },
    );
    await host.ensureReady();
    this.commonsHost = host;
    registerHost(['commons'], host);

    installSDKEventTransport();
    EventBus.shared.start();

    this._initialized = true;
    logger.info('RunAnywhere initialized');
  }

  async shutdown(): Promise<void> {
    EventBus.shared.stop();
    if (this.commonsHost) {
      unregisterHost(this.commonsHost);
      this.commonsHost.shutdown();
      this.commonsHost = null;
    }
    this._initialized = false;
  }

  ensureInitialized(): void {
    if (!this._initialized) {
      throw new Error('RunAnywhere is not initialized. Call RunAnywhere.initialize() first.');
    }
  }
}

export const RunAnywhere = new RunAnywhereSDK();
