/**
 * RunAnywhere React Native SDK - Event Bus
 *
 * Central event bus for SDK-wide event distribution.
 * Wraps NativeEventEmitter for cross-platform event handling.
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Public/Events/EventBus.swift
 */

import { NativeEventEmitter, NativeModules } from 'react-native';
import type {
  AnySDKEvent,
  ComponentInitializationEvent,
  SDKComponent,
  SDKConfigurationEvent,
  SDKDeviceEvent,
  SDKEventListener,
  SDKFrameworkEvent,
  SDKGenerationEvent,
  SDKInitializationEvent,
  SDKModelEvent,
  SDKNetworkEvent,
  SDKPerformanceEvent,
  SDKStorageEvent,
  SDKVoiceEvent,
  UnsubscribeFunction,
} from '../../types';

// Native module reference - accessed lazily in setup() to avoid
// accessing NativeModules before React Native is fully initialized (bridgeless mode)
function getRunAnywhereModule() {
  return NativeModules.RunAnywhereModule;
}

// Event name constants matching native modules
export const NativeEventNames = {
  // Initialization events
  SDK_INITIALIZATION: 'RunAnywhere_SDKInitialization',
  // Configuration events
  SDK_CONFIGURATION: 'RunAnywhere_SDKConfiguration',
  // Generation events
  SDK_GENERATION: 'RunAnywhere_SDKGeneration',
  // Model events
  SDK_MODEL: 'RunAnywhere_SDKModel',
  // Voice events
  SDK_VOICE: 'RunAnywhere_SDKVoice',
  // Performance events
  SDK_PERFORMANCE: 'RunAnywhere_SDKPerformance',
  // Network events
  SDK_NETWORK: 'RunAnywhere_SDKNetwork',
  // Storage events
  SDK_STORAGE: 'RunAnywhere_SDKStorage',
  // Framework events
  SDK_FRAMEWORK: 'RunAnywhere_SDKFramework',
  // Device events
  SDK_DEVICE: 'RunAnywhere_SDKDevice',
  // Component events
  SDK_COMPONENT: 'RunAnywhere_SDKComponent',
  // All events (catch-all)
  SDK_ALL_EVENTS: 'RunAnywhere_AllEvents',
} as const;

type NativeEventName = (typeof NativeEventNames)[keyof typeof NativeEventNames];

/**
 * Central event bus for SDK-wide event distribution
 * Thread-safe event bus using React Native's NativeEventEmitter
 */
class EventBusImpl {
  private emitter: NativeEventEmitter | null = null;
  private subscriptions: Map<string, Set<SDKEventListener<AnySDKEvent>>> =
    new Map();
  private nativeSubscriptions: Map<NativeEventName, { remove: () => void }> =
    new Map();
  private isSetup = false;

  /**
   * Setup the event bus with the native module
   * Called automatically when first subscription is made
   */
  private setup(): void {
    if (this.isSetup) return;

    // Only create NativeEventEmitter if native module exists
    // Access NativeModules lazily to avoid issues with bridgeless mode
    const RunAnywhereModule = getRunAnywhereModule();
    if (RunAnywhereModule) {
      this.emitter = new NativeEventEmitter(RunAnywhereModule);

      // Subscribe to all native event types
      this.setupNativeListener(NativeEventNames.SDK_INITIALIZATION);
      this.setupNativeListener(NativeEventNames.SDK_CONFIGURATION);
      this.setupNativeListener(NativeEventNames.SDK_GENERATION);
      this.setupNativeListener(NativeEventNames.SDK_MODEL);
      this.setupNativeListener(NativeEventNames.SDK_VOICE);
      this.setupNativeListener(NativeEventNames.SDK_PERFORMANCE);
      this.setupNativeListener(NativeEventNames.SDK_NETWORK);
      this.setupNativeListener(NativeEventNames.SDK_STORAGE);
      this.setupNativeListener(NativeEventNames.SDK_FRAMEWORK);
      this.setupNativeListener(NativeEventNames.SDK_DEVICE);
      this.setupNativeListener(NativeEventNames.SDK_COMPONENT);
    } else {
      console.warn(
        '[RunAnywhere] Native module not available. Events will only work in development mode.'
      );
    }

    this.isSetup = true;
  }

  /**
   * Setup a listener for a specific native event type
   */
  private setupNativeListener(eventName: NativeEventName): void {
    if (!this.emitter) return;

    const subscription = this.emitter.addListener(
      eventName,
      (event: AnySDKEvent) => {
        this.handleNativeEvent(eventName, event);
      }
    );

    this.nativeSubscriptions.set(eventName, subscription);
  }

  /**
   * Handle an event from native
   */
  private handleNativeEvent(
    eventName: NativeEventName,
    event: AnySDKEvent
  ): void {
    // Get subscribers for this event type
    const typeSubscribers = this.subscriptions.get(eventName);
    if (typeSubscribers) {
      typeSubscribers.forEach((listener) => {
        try {
          listener(event);
        } catch (error) {
          console.error('[RunAnywhere] Error in event listener:', error);
        }
      });
    }

    // Also notify "all events" subscribers
    const allSubscribers = this.subscriptions.get(
      NativeEventNames.SDK_ALL_EVENTS
    );
    if (allSubscribers) {
      allSubscribers.forEach((listener) => {
        try {
          listener(event);
        } catch (error) {
          console.error('[RunAnywhere] Error in event listener:', error);
        }
      });
    }
  }

  /**
   * Subscribe to events of a specific type
   */
  private subscribe<T extends AnySDKEvent>(
    eventName: NativeEventName,
    listener: SDKEventListener<T>
  ): UnsubscribeFunction {
    this.setup();

    if (!this.subscriptions.has(eventName)) {
      this.subscriptions.set(eventName, new Set());
    }

    const subscribers = this.subscriptions.get(eventName)!;
    subscribers.add(listener as SDKEventListener<AnySDKEvent>);

    // Return unsubscribe function
    return () => {
      subscribers.delete(listener as SDKEventListener<AnySDKEvent>);
    };
  }

  // ============================================================================
  // Public Subscription Methods
  // ============================================================================

  /**
   * Subscribe to all SDK events
   */
  onAllEvents(handler: SDKEventListener<AnySDKEvent>): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_ALL_EVENTS, handler);
  }

  /**
   * Subscribe to initialization events
   */
  onInitialization(
    handler: SDKEventListener<SDKInitializationEvent>
  ): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_INITIALIZATION, handler);
  }

  /**
   * Subscribe to configuration events
   */
  onConfiguration(
    handler: SDKEventListener<SDKConfigurationEvent>
  ): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_CONFIGURATION, handler);
  }

  /**
   * Subscribe to generation events
   */
  onGeneration(
    handler: SDKEventListener<SDKGenerationEvent>
  ): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_GENERATION, handler);
  }

  /**
   * Subscribe to model events
   */
  onModel(handler: SDKEventListener<SDKModelEvent>): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_MODEL, handler);
  }

  /**
   * Subscribe to voice events
   */
  onVoice(handler: SDKEventListener<SDKVoiceEvent>): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_VOICE, handler);
  }

  /**
   * Subscribe to performance events
   */
  onPerformance(
    handler: SDKEventListener<SDKPerformanceEvent>
  ): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_PERFORMANCE, handler);
  }

  /**
   * Subscribe to network events
   */
  onNetwork(handler: SDKEventListener<SDKNetworkEvent>): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_NETWORK, handler);
  }

  /**
   * Subscribe to storage events
   */
  onStorage(handler: SDKEventListener<SDKStorageEvent>): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_STORAGE, handler);
  }

  /**
   * Subscribe to framework events
   */
  onFramework(
    handler: SDKEventListener<SDKFrameworkEvent>
  ): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_FRAMEWORK, handler);
  }

  /**
   * Subscribe to device events
   */
  onDevice(handler: SDKEventListener<SDKDeviceEvent>): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_DEVICE, handler);
  }

  /**
   * Subscribe to component initialization events
   */
  onComponentInitialization(
    handler: SDKEventListener<ComponentInitializationEvent>
  ): UnsubscribeFunction {
    return this.subscribe(NativeEventNames.SDK_COMPONENT, handler);
  }

  /**
   * Subscribe to specific component events
   */
  onComponent(
    component: SDKComponent,
    handler: SDKEventListener<ComponentInitializationEvent>
  ): UnsubscribeFunction {
    return this.onComponentInitialization((event) => {
      // Filter by component if event has component property
      if ('component' in event && event.component === component) {
        handler(event);
      }
    });
  }

  // ============================================================================
  // Generic Event Subscription
  // ============================================================================

  /**
   * Generic typed event subscription
   * Example: events.on('generation', handler)
   */
  on<T extends AnySDKEvent>(
    eventType:
      | 'initialization'
      | 'configuration'
      | 'generation'
      | 'model'
      | 'voice'
      | 'performance'
      | 'network'
      | 'storage'
      | 'framework'
      | 'device'
      | 'component'
      | 'all',
    handler: SDKEventListener<T>
  ): UnsubscribeFunction {
    const eventNameMap: Record<string, NativeEventName> = {
      initialization: NativeEventNames.SDK_INITIALIZATION,
      configuration: NativeEventNames.SDK_CONFIGURATION,
      generation: NativeEventNames.SDK_GENERATION,
      model: NativeEventNames.SDK_MODEL,
      voice: NativeEventNames.SDK_VOICE,
      performance: NativeEventNames.SDK_PERFORMANCE,
      network: NativeEventNames.SDK_NETWORK,
      storage: NativeEventNames.SDK_STORAGE,
      framework: NativeEventNames.SDK_FRAMEWORK,
      device: NativeEventNames.SDK_DEVICE,
      component: NativeEventNames.SDK_COMPONENT,
      all: NativeEventNames.SDK_ALL_EVENTS,
    };

    const eventName = eventNameMap[eventType];
    if (!eventName) {
      console.warn(`[RunAnywhere] Unknown event type: ${eventType}`);
      return () => {};
    }

    return this.subscribe(eventName, handler);
  }

  // ============================================================================
  // Publishing (for internal/testing use)
  // ============================================================================

  /**
   * Publish an event locally (for testing or JS-only events)
   * Note: In production, events come from native modules
   */
  publish(eventType: string, event: AnySDKEvent): void {
    const eventName = `RunAnywhere_SDK${eventType}` as NativeEventName;
    this.handleNativeEvent(eventName, event);
  }

  /**
   * Emit a model event
   * Helper method for components to emit model-related events
   */
  emitModel(event: SDKModelEvent): void {
    this.handleNativeEvent(NativeEventNames.SDK_MODEL, event);
  }

  /**
   * Emit a voice event
   * Helper method for components to emit voice-related events
   */
  emitVoice(event: SDKVoiceEvent): void {
    this.handleNativeEvent(NativeEventNames.SDK_VOICE, event);
  }

  /**
   * Emit a component initialization event
   * Helper method for components to emit initialization-related events
   */
  emitComponentInitialization(event: ComponentInitializationEvent): void {
    this.handleNativeEvent(NativeEventNames.SDK_COMPONENT, event);
  }

  // ============================================================================
  // Cleanup
  // ============================================================================

  /**
   * Remove all subscriptions
   */
  removeAllListeners(): void {
    this.subscriptions.clear();

    // Remove native subscriptions
    this.nativeSubscriptions.forEach((subscription) => {
      subscription.remove();
    });
    this.nativeSubscriptions.clear();

    this.isSetup = false;
  }
}

// Singleton instance
let instance: EventBusImpl | null = null;

/**
 * Get the singleton instance of EventBus
 */
function getInstance(): EventBusImpl {
  if (!instance) {
    instance = new EventBusImpl();
  }
  return instance;
}

// Create singleton wrapper with all methods exposed at top level
const singletonWrapper = {
  getInstance,
  // Proxy all methods from getInstance() for backward compatibility
  get onAllEvents() {
    return getInstance().onAllEvents.bind(getInstance());
  },
  get onInitialization() {
    return getInstance().onInitialization.bind(getInstance());
  },
  get onConfiguration() {
    return getInstance().onConfiguration.bind(getInstance());
  },
  get onGeneration() {
    return getInstance().onGeneration.bind(getInstance());
  },
  get onModel() {
    return getInstance().onModel.bind(getInstance());
  },
  get onVoice() {
    return getInstance().onVoice.bind(getInstance());
  },
  get onPerformance() {
    return getInstance().onPerformance.bind(getInstance());
  },
  get onNetwork() {
    return getInstance().onNetwork.bind(getInstance());
  },
  get onStorage() {
    return getInstance().onStorage.bind(getInstance());
  },
  get onFramework() {
    return getInstance().onFramework.bind(getInstance());
  },
  get onDevice() {
    return getInstance().onDevice.bind(getInstance());
  },
  get onComponentInitialization() {
    return getInstance().onComponentInitialization.bind(getInstance());
  },
  get onComponent() {
    return getInstance().onComponent.bind(getInstance());
  },
  get on() {
    return getInstance().on.bind(getInstance());
  },
  get publish() {
    return getInstance().publish.bind(getInstance());
  },
  get emitModel() {
    return getInstance().emitModel.bind(getInstance());
  },
  get emitVoice() {
    return getInstance().emitVoice.bind(getInstance());
  },
  get emitComponentInitialization() {
    return getInstance().emitComponentInitialization.bind(getInstance());
  },
  get removeAllListeners() {
    return getInstance().removeAllListeners.bind(getInstance());
  },
};

// Export singleton wrapper
export const EventBus = singletonWrapper;

// Export type for the EventBus
export type { EventBusImpl };
