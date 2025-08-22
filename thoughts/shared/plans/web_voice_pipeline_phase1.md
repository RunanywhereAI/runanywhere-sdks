# Web Voice Pipeline - Phase 1 Implementation Guide

## Phase 1 Overview: Foundation & Core Infrastructure (Weeks 1-3)

This document provides a detailed, executable plan for Phase 1 of the web voice pipeline SDK. Phase 1 establishes the foundational architecture, core infrastructure, and basic voice pipeline with VAD integration.

## Goals for Phase 1

1. **Set up monorepo structure** with TypeScript, build tooling, and development environment
2. **Implement Foundation Layer** with core utilities, error handling, and logging
3. **Build Infrastructure Layer** with DI container, event system, and configuration
4. **Create basic Voice Pipeline** with VAD integration using @ricky0123/vad-web
5. **Establish testing framework** with initial unit and integration tests
6. **Create minimal demo app** to validate the pipeline

## Week 1: Project Setup & Foundation Layer

### Day 1-2: Monorepo Setup

#### 1. Initialize Project Structure

```bash
# Create project root
mkdir web-voice-sdk && cd web-voice-sdk

# Initialize PNPM workspace
pnpm init

# Create workspace configuration
cat > pnpm-workspace.yaml << 'EOF'
packages:
  - 'packages/*'
  - 'examples/*'
  - 'docs'
EOF

# Create package directories
mkdir -p packages/core packages/voice packages/web-audio packages/models
mkdir -p examples/vanilla examples/react
mkdir -p docs tools scripts
```

#### 2. Root Package Configuration

```json
// package.json
{
  "name": "@runanywhere/web-voice-sdk",
  "version": "0.1.0",
  "private": true,
  "type": "module",
  "scripts": {
    "dev": "pnpm -r --parallel dev",
    "build": "pnpm -r build",
    "test": "pnpm -r test",
    "lint": "eslint . --ext .ts,.tsx",
    "format": "prettier --write \"**/*.{ts,tsx,json,md}\"",
    "typecheck": "pnpm -r typecheck",
    "clean": "pnpm -r clean && rm -rf node_modules",
    "prepare": "husky install"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "@typescript-eslint/eslint-plugin": "^6.13.0",
    "@typescript-eslint/parser": "^6.13.0",
    "@vitest/ui": "^1.0.0",
    "eslint": "^8.54.0",
    "eslint-config-prettier": "^9.0.0",
    "husky": "^8.0.3",
    "lint-staged": "^15.1.0",
    "prettier": "^3.1.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "vitest": "^1.0.0"
  },
  "engines": {
    "node": ">=18.0.0",
    "pnpm": ">=8.0.0"
  }
}
```

#### 3. TypeScript Configuration

```json
// tsconfig.base.json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "ESNext",
    "lib": ["ES2022", "DOM", "DOM.Iterable"],
    "moduleResolution": "bundler",
    "resolveJsonModule": true,
    "allowJs": false,
    "strict": true,
    "noUnusedLocals": true,
    "noUnusedParameters": true,
    "noImplicitReturns": true,
    "noFallthroughCasesInSwitch": true,
    "noUncheckedIndexedAccess": true,
    "noImplicitOverride": true,
    "noPropertyAccessFromIndexSignature": true,
    "esModuleInterop": true,
    "forceConsistentCasingInFileNames": true,
    "skipLibCheck": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true,
    "composite": true,
    "incremental": true
  }
}
```

### Day 3-4: Core Package Foundation

#### 1. Core Package Setup

```bash
cd packages/core
pnpm init
```

```json
// packages/core/package.json
{
  "name": "@runanywhere/core",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.js",
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    }
  },
  "scripts": {
    "dev": "vite build --watch",
    "build": "tsc -b && vite build",
    "test": "vitest",
    "typecheck": "tsc -b",
    "clean": "rm -rf dist node_modules .turbo"
  },
  "dependencies": {
    "eventemitter3": "^5.0.1"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "vitest": "^1.0.0"
  }
}
```

#### 2. Core Types Implementation

```typescript
// packages/core/src/types/result.ts

/**
 * Result type for handling success and failure cases
 */
export type Result<T, E = Error> =
  | { success: true; value: T }
  | { success: false; error: E };

export const Result = {
  ok<T>(value: T): Result<T, never> {
    return { success: true, value };
  },

  err<E>(error: E): Result<never, E> {
    return { success: false, error };
  },

  isOk<T, E>(result: Result<T, E>): result is { success: true; value: T } {
    return result.success;
  },

  isErr<T, E>(result: Result<T, E>): result is { success: false; error: E } {
    return !result.success;
  },

  map<T, U, E>(
    result: Result<T, E>,
    fn: (value: T) => U
  ): Result<U, E> {
    if (Result.isOk(result)) {
      return Result.ok(fn(result.value));
    }
    return result;
  },

  mapErr<T, E, F>(
    result: Result<T, E>,
    fn: (error: E) => F
  ): Result<T, F> {
    if (Result.isErr(result)) {
      return Result.err(fn(result.error));
    }
    return result;
  },

  unwrap<T, E>(result: Result<T, E>): T {
    if (Result.isOk(result)) {
      return result.value;
    }
    throw result.error;
  },

  unwrapOr<T, E>(result: Result<T, E>, defaultValue: T): T {
    if (Result.isOk(result)) {
      return result.value;
    }
    return defaultValue;
  }
};
```

```typescript
// packages/core/src/types/branded.ts

/**
 * Branded types for type safety
 */
export type Brand<K, T> = K & { __brand: T };

export type SessionId = Brand<string, 'SessionId'>;
export type ModelId = Brand<string, 'ModelId'>;
export type DeviceId = Brand<string, 'DeviceId'>;
export type UserId = Brand<string, 'UserId'>;

export const SessionId = (id: string): SessionId => id as SessionId;
export const ModelId = (id: string): ModelId => id as ModelId;
export const DeviceId = (id: string): DeviceId => id as DeviceId;
export const UserId = (id: string): UserId => id as UserId;
```

#### 3. Error System

```typescript
// packages/core/src/errors/base.ts

export abstract class BaseError extends Error {
  public readonly timestamp: Date;
  public readonly context?: Record<string, unknown>;

  constructor(
    message: string,
    public readonly code: string,
    context?: Record<string, unknown>
  ) {
    super(message);
    this.name = this.constructor.name;
    this.timestamp = new Date();
    this.context = context;
    Error.captureStackTrace(this, this.constructor);
  }

  toJSON() {
    return {
      name: this.name,
      code: this.code,
      message: this.message,
      timestamp: this.timestamp,
      context: this.context,
      stack: this.stack
    };
  }
}

export class SDKError extends BaseError {
  constructor(message: string, code: string, context?: Record<string, unknown>) {
    super(message, `SDK_${code}`, context);
  }
}

export class ConfigurationError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'CONFIGURATION_ERROR', context);
  }
}

export class InitializationError extends SDKError {
  constructor(message: string, context?: Record<string, unknown>) {
    super(message, 'INITIALIZATION_ERROR', context);
  }
}
```

#### 4. Logger Implementation

```typescript
// packages/core/src/utils/logger.ts

export enum LogLevel {
  DEBUG = 0,
  INFO = 1,
  WARN = 2,
  ERROR = 3,
  NONE = 4
}

export interface LogEntry {
  level: LogLevel;
  message: string;
  timestamp: Date;
  category?: string;
  context?: Record<string, unknown>;
}

export class Logger {
  private static instance: Logger;
  private level: LogLevel = LogLevel.INFO;
  private handlers: Array<(entry: LogEntry) => void> = [];

  private constructor() {
    // Default console handler
    this.addHandler((entry) => {
      const prefix = `[${entry.category || 'SDK'}] ${new Date().toISOString()}`;
      const contextStr = entry.context ? ` ${JSON.stringify(entry.context)}` : '';

      switch (entry.level) {
        case LogLevel.DEBUG:
          console.debug(`${prefix} DEBUG: ${entry.message}${contextStr}`);
          break;
        case LogLevel.INFO:
          console.info(`${prefix} INFO: ${entry.message}${contextStr}`);
          break;
        case LogLevel.WARN:
          console.warn(`${prefix} WARN: ${entry.message}${contextStr}`);
          break;
        case LogLevel.ERROR:
          console.error(`${prefix} ERROR: ${entry.message}${contextStr}`);
          break;
      }
    });
  }

  static getInstance(): Logger {
    if (!Logger.instance) {
      Logger.instance = new Logger();
    }
    return Logger.instance;
  }

  setLevel(level: LogLevel): void {
    this.level = level;
  }

  addHandler(handler: (entry: LogEntry) => void): void {
    this.handlers.push(handler);
  }

  private log(level: LogLevel, message: string, category?: string, context?: Record<string, unknown>): void {
    if (level < this.level) return;

    const entry: LogEntry = {
      level,
      message,
      timestamp: new Date(),
      category,
      context
    };

    this.handlers.forEach(handler => handler(entry));
  }

  debug(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.DEBUG, message, category, context);
  }

  info(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.INFO, message, category, context);
  }

  warn(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.WARN, message, category, context);
  }

  error(message: string, category?: string, context?: Record<string, unknown>): void {
    this.log(LogLevel.ERROR, message, category, context);
  }
}

export const logger = Logger.getInstance();
```

### Day 5: Infrastructure Layer - DI Container

```typescript
// packages/core/src/di/container.ts

import { EventEmitter } from 'eventemitter3';
import { Result } from '../types/result';
import { InitializationError } from '../errors/base';
import { logger } from '../utils/logger';

export interface ServiceDefinition {
  factory: () => unknown | Promise<unknown>;
  singleton: boolean;
  dependencies?: string[];
}

export interface ServiceHealth {
  healthy: boolean;
  lastCheck: Date;
  message?: string;
}

export class DIContainer extends EventEmitter {
  private services = new Map<string, ServiceDefinition>();
  private instances = new Map<string, unknown>();
  private health = new Map<string, ServiceHealth>();
  private initializing = new Set<string>();

  /**
   * Register a service
   */
  register<T>(
    name: string,
    factory: () => T | Promise<T>,
    options: { singleton?: boolean; dependencies?: string[] } = {}
  ): void {
    const { singleton = true, dependencies = [] } = options;

    // Check for circular dependencies
    if (this.hasCircularDependency(name, dependencies)) {
      throw new InitializationError(
        `Circular dependency detected for service: ${name}`
      );
    }

    this.services.set(name, {
      factory,
      singleton,
      dependencies
    });

    logger.debug(`Registered service: ${name}`, 'DIContainer', {
      singleton,
      dependencies
    });
  }

  /**
   * Get a service instance
   */
  async get<T>(name: string): Promise<Result<T, Error>> {
    try {
      // Check if already initializing (circular dependency at runtime)
      if (this.initializing.has(name)) {
        return Result.err(
          new InitializationError(`Circular dependency detected at runtime: ${name}`)
        );
      }

      // Return existing singleton instance
      if (this.instances.has(name)) {
        return Result.ok(this.instances.get(name) as T);
      }

      // Get service definition
      const definition = this.services.get(name);
      if (!definition) {
        return Result.err(
          new InitializationError(`Service not found: ${name}`)
        );
      }

      // Mark as initializing
      this.initializing.add(name);

      try {
        // Initialize dependencies first
        for (const dep of definition.dependencies || []) {
          const depResult = await this.get(dep);
          if (Result.isErr(depResult)) {
            return Result.err(depResult.error);
          }
        }

        // Create instance
        const instance = await definition.factory();

        // Store singleton
        if (definition.singleton) {
          this.instances.set(name, instance);
        }

        // Update health
        this.health.set(name, {
          healthy: true,
          lastCheck: new Date()
        });

        // Emit initialization event
        this.emit('service:initialized', { name, instance });

        logger.info(`Service initialized: ${name}`, 'DIContainer');

        return Result.ok(instance as T);
      } finally {
        this.initializing.delete(name);
      }
    } catch (error) {
      logger.error(`Failed to initialize service: ${name}`, 'DIContainer', {
        error: error instanceof Error ? error.message : String(error)
      });

      this.health.set(name, {
        healthy: false,
        lastCheck: new Date(),
        message: error instanceof Error ? error.message : String(error)
      });

      return Result.err(
        new InitializationError(
          `Failed to initialize service ${name}: ${error instanceof Error ? error.message : String(error)}`
        )
      );
    }
  }

  /**
   * Check for circular dependencies
   */
  private hasCircularDependency(
    name: string,
    dependencies: string[],
    visited = new Set<string>()
  ): boolean {
    if (visited.has(name)) {
      return true;
    }

    visited.add(name);

    for (const dep of dependencies) {
      const depDefinition = this.services.get(dep);
      if (depDefinition?.dependencies) {
        if (this.hasCircularDependency(dep, depDefinition.dependencies, new Set(visited))) {
          return true;
        }
      }
    }

    return false;
  }

  /**
   * Get health status of all services
   */
  getHealth(): Map<string, ServiceHealth> {
    return new Map(this.health);
  }

  /**
   * Clear all services and instances
   */
  clear(): void {
    this.instances.clear();
    this.services.clear();
    this.health.clear();
    this.initializing.clear();
    this.removeAllListeners();
    logger.info('Container cleared', 'DIContainer');
  }
}

export const container = new DIContainer();
```

## Week 2: Voice Pipeline Core & VAD Integration

### Day 1-2: Voice Package Setup

```bash
cd packages/voice
pnpm init
```

```json
// packages/voice/package.json
{
  "name": "@runanywhere/voice",
  "version": "0.1.0",
  "type": "module",
  "main": "./dist/index.js",
  "module": "./dist/index.js",
  "types": "./dist/index.d.ts",
  "exports": {
    ".": {
      "types": "./dist/index.d.ts",
      "import": "./dist/index.js"
    }
  },
  "scripts": {
    "dev": "vite build --watch",
    "build": "tsc -b && vite build",
    "test": "vitest",
    "typecheck": "tsc -b"
  },
  "dependencies": {
    "@runanywhere/core": "workspace:*",
    "@ricky0123/vad-web": "^0.0.13",
    "eventemitter3": "^5.0.1"
  },
  "devDependencies": {
    "@types/node": "^20.10.0",
    "typescript": "^5.3.0",
    "vite": "^5.0.0",
    "vitest": "^1.0.0"
  }
}
```

### Day 3-4: VAD Service Implementation

```typescript
// packages/voice/src/services/vad/types.ts

export interface VADConfig {
  /** Positive speech probability threshold */
  positiveSpeechThreshold: number;
  /** Negative speech probability threshold */
  negativeSpeechThreshold: number;
  /** Pre-activation buffer in ms */
  preSpeechPadFrames: number;
  /** Minimum speech frames */
  minSpeechFrames: number;
  /** Submission after silence in ms */
  submitUserSpeechOnPause: boolean;
  /** Frame samples (512, 1024, 1536) */
  frameSamples: 512 | 1024 | 1536;
}

export interface VADEvent {
  type: 'speech_start' | 'speech_end' | 'speech_segment';
  timestamp: number;
  data?: Float32Array;
  energy?: number;
}

export interface VADService {
  initialize(config: VADConfig): Promise<void>;
  start(): Promise<void>;
  stop(): void;
  process(audio: Float32Array): Promise<VADEvent | null>;
  onSpeechStart(callback: () => void): void;
  onSpeechEnd(callback: (audio: Float32Array) => void): void;
  destroy(): void;
}
```

```typescript
// packages/voice/src/services/vad/vad-service.ts

import { MicVAD, utils } from '@ricky0123/vad-web';
import { EventEmitter } from 'eventemitter3';
import { logger } from '@runanywhere/core';
import type { VADConfig, VADEvent, VADService } from './types';

export class WebVADService extends EventEmitter implements VADService {
  private vad: MicVAD | null = null;
  private config: VADConfig;
  private isRunning = false;

  constructor() {
    super();
    this.config = this.getDefaultConfig();
  }

  private getDefaultConfig(): VADConfig {
    return {
      positiveSpeechThreshold: 0.9,
      negativeSpeechThreshold: 0.75,
      preSpeechPadFrames: 10,
      minSpeechFrames: 5,
      submitUserSpeechOnPause: true,
      frameSamples: 1536
    };
  }

  async initialize(config: Partial<VADConfig> = {}): Promise<void> {
    this.config = { ...this.getDefaultConfig(), ...config };

    logger.info('Initializing VAD service', 'VAD', { config: this.config });

    try {
      // Load VAD model
      this.vad = await MicVAD.new({
        positiveSpeechThreshold: this.config.positiveSpeechThreshold,
        negativeSpeechThreshold: this.config.negativeSpeechThreshold,
        preSpeechPadFrames: this.config.preSpeechPadFrames,
        minSpeechFrames: this.config.minSpeechFrames,
        submitUserSpeechOnPause: this.config.submitUserSpeechOnPause,
        frameSamples: this.config.frameSamples,

        onSpeechStart: () => {
          logger.debug('Speech started', 'VAD');
          this.emit('speech_start');
        },

        onSpeechEnd: (audio: Float32Array) => {
          logger.debug('Speech ended', 'VAD', {
            duration: audio.length / 16000
          });
          this.emit('speech_end', audio);
        },

        onVADMisfire: () => {
          logger.warn('VAD misfire detected', 'VAD');
        }
      });

      logger.info('VAD service initialized', 'VAD');
    } catch (error) {
      logger.error('Failed to initialize VAD', 'VAD', { error });
      throw error;
    }
  }

  async start(): Promise<void> {
    if (!this.vad) {
      throw new Error('VAD not initialized');
    }

    if (this.isRunning) {
      logger.warn('VAD already running', 'VAD');
      return;
    }

    logger.info('Starting VAD', 'VAD');
    await this.vad.start();
    this.isRunning = true;
  }

  stop(): void {
    if (!this.vad || !this.isRunning) {
      return;
    }

    logger.info('Stopping VAD', 'VAD');
    this.vad.pause();
    this.isRunning = false;
  }

  async process(audio: Float32Array): Promise<VADEvent | null> {
    // This is for manual processing mode
    // The MicVAD handles this automatically when using microphone
    const energy = this.calculateEnergy(audio);

    return {
      type: 'speech_segment',
      timestamp: Date.now(),
      data: audio,
      energy
    };
  }

  private calculateEnergy(audio: Float32Array): number {
    let sum = 0;
    for (let i = 0; i < audio.length; i++) {
      sum += audio[i]! * audio[i]!;
    }
    return Math.sqrt(sum / audio.length);
  }

  onSpeechStart(callback: () => void): void {
    this.on('speech_start', callback);
  }

  onSpeechEnd(callback: (audio: Float32Array) => void): void {
    this.on('speech_end', callback);
  }

  destroy(): void {
    this.stop();
    if (this.vad) {
      this.vad.destroy();
      this.vad = null;
    }
    this.removeAllListeners();
    logger.info('VAD service destroyed', 'VAD');
  }
}
```

### Day 5: Basic Pipeline Manager

```typescript
// packages/voice/src/pipeline/types.ts

export interface PipelineConfig {
  vad?: {
    enabled: boolean;
    config?: Partial<VADConfig>;
  };
  stt?: {
    enabled: boolean;
    modelId?: string;
  };
  tts?: {
    enabled: boolean;
    modelId?: string;
  };
}

export type PipelineEvent =
  | { type: 'initialized' }
  | { type: 'started' }
  | { type: 'stopped' }
  | { type: 'error'; error: Error }
  | { type: 'vad_speech_start' }
  | { type: 'vad_speech_end'; audio: Float32Array }
  | { type: 'processing_start' }
  | { type: 'processing_complete' };
```

```typescript
// packages/voice/src/pipeline/pipeline-manager.ts

import { EventEmitter } from 'eventemitter3';
import { logger } from '@runanywhere/core';
import { WebVADService } from '../services/vad/vad-service';
import type { PipelineConfig, PipelineEvent } from './types';

export class VoicePipelineManager extends EventEmitter {
  private config: PipelineConfig;
  private vadService: WebVADService | null = null;
  private isInitialized = false;
  private isRunning = false;

  constructor(config: PipelineConfig = {}) {
    super();
    this.config = {
      vad: { enabled: true, ...config.vad },
      stt: { enabled: false, ...config.stt },
      tts: { enabled: false, ...config.tts }
    };
  }

  async initialize(): Promise<void> {
    if (this.isInitialized) {
      logger.warn('Pipeline already initialized', 'Pipeline');
      return;
    }

    logger.info('Initializing voice pipeline', 'Pipeline', {
      config: this.config
    });

    try {
      // Initialize VAD if enabled
      if (this.config.vad?.enabled) {
        this.vadService = new WebVADService();
        await this.vadService.initialize(this.config.vad.config);

        // Set up VAD event handlers
        this.vadService.onSpeechStart(() => {
          this.emit('event', { type: 'vad_speech_start' } as PipelineEvent);
        });

        this.vadService.onSpeechEnd((audio) => {
          this.emit('event', {
            type: 'vad_speech_end',
            audio
          } as PipelineEvent);

          // Process audio through pipeline
          this.processAudio(audio);
        });
      }

      // TODO: Initialize STT service in Phase 2
      // TODO: Initialize TTS service in Phase 2

      this.isInitialized = true;
      this.emit('event', { type: 'initialized' } as PipelineEvent);

      logger.info('Voice pipeline initialized', 'Pipeline');
    } catch (error) {
      logger.error('Failed to initialize pipeline', 'Pipeline', { error });
      this.emit('event', {
        type: 'error',
        error: error as Error
      } as PipelineEvent);
      throw error;
    }
  }

  async start(): Promise<void> {
    if (!this.isInitialized) {
      throw new Error('Pipeline not initialized');
    }

    if (this.isRunning) {
      logger.warn('Pipeline already running', 'Pipeline');
      return;
    }

    logger.info('Starting voice pipeline', 'Pipeline');

    try {
      if (this.vadService) {
        await this.vadService.start();
      }

      this.isRunning = true;
      this.emit('event', { type: 'started' } as PipelineEvent);

      logger.info('Voice pipeline started', 'Pipeline');
    } catch (error) {
      logger.error('Failed to start pipeline', 'Pipeline', { error });
      this.emit('event', {
        type: 'error',
        error: error as Error
      } as PipelineEvent);
      throw error;
    }
  }

  stop(): void {
    if (!this.isRunning) {
      return;
    }

    logger.info('Stopping voice pipeline', 'Pipeline');

    if (this.vadService) {
      this.vadService.stop();
    }

    this.isRunning = false;
    this.emit('event', { type: 'stopped' } as PipelineEvent);

    logger.info('Voice pipeline stopped', 'Pipeline');
  }

  private async processAudio(audio: Float32Array): Promise<void> {
    this.emit('event', { type: 'processing_start' } as PipelineEvent);

    // TODO: Process through STT in Phase 2
    // TODO: Process through TTS in Phase 2

    // For now, just log the audio info
    logger.info('Processing audio', 'Pipeline', {
      duration: audio.length / 16000,
      samples: audio.length
    });

    this.emit('event', { type: 'processing_complete' } as PipelineEvent);
  }

  destroy(): void {
    this.stop();

    if (this.vadService) {
      this.vadService.destroy();
      this.vadService = null;
    }

    this.removeAllListeners();
    this.isInitialized = false;

    logger.info('Voice pipeline destroyed', 'Pipeline');
  }

  isHealthy(): boolean {
    return this.isInitialized && !this.hasError();
  }

  private hasError(): boolean {
    // Check component health
    return false; // Will be expanded in later phases
  }
}
```

## Week 3: Testing & Demo Application

### Day 1-2: Testing Setup

```typescript
// packages/voice/src/__tests__/vad-service.test.ts

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { WebVADService } from '../services/vad/vad-service';

describe('WebVADService', () => {
  let service: WebVADService;

  beforeEach(() => {
    service = new WebVADService();
  });

  afterEach(() => {
    service.destroy();
  });

  it('should initialize with default config', async () => {
    await service.initialize();
    expect(service).toBeDefined();
  });

  it('should emit speech_start event', async () => {
    const speechStartSpy = vi.fn();
    service.onSpeechStart(speechStartSpy);

    await service.initialize();

    // Simulate speech start
    service.emit('speech_start');

    expect(speechStartSpy).toHaveBeenCalled();
  });

  it('should emit speech_end event with audio', async () => {
    const speechEndSpy = vi.fn();
    service.onSpeechEnd(speechEndSpy);

    await service.initialize();

    // Simulate speech end
    const mockAudio = new Float32Array(16000); // 1 second of audio
    service.emit('speech_end', mockAudio);

    expect(speechEndSpy).toHaveBeenCalledWith(mockAudio);
  });

  it('should calculate energy correctly', async () => {
    await service.initialize();

    // Create test audio with known energy
    const audio = new Float32Array([0.5, -0.5, 0.5, -0.5]);
    const event = await service.process(audio);

    expect(event).toBeDefined();
    expect(event?.energy).toBeCloseTo(0.5);
  });
});
```

```typescript
// packages/voice/src/__tests__/pipeline-manager.test.ts

import { describe, it, expect, beforeEach, afterEach, vi } from 'vitest';
import { VoicePipelineManager } from '../pipeline/pipeline-manager';

describe('VoicePipelineManager', () => {
  let pipeline: VoicePipelineManager;

  beforeEach(() => {
    pipeline = new VoicePipelineManager({
      vad: { enabled: true }
    });
  });

  afterEach(() => {
    pipeline.destroy();
  });

  it('should initialize successfully', async () => {
    const initSpy = vi.fn();
    pipeline.on('event', initSpy);

    await pipeline.initialize();

    expect(initSpy).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'initialized' })
    );
  });

  it('should start and stop pipeline', async () => {
    await pipeline.initialize();

    const eventSpy = vi.fn();
    pipeline.on('event', eventSpy);

    await pipeline.start();
    expect(eventSpy).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'started' })
    );

    pipeline.stop();
    expect(eventSpy).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'stopped' })
    );
  });

  it('should process audio on speech end', async () => {
    await pipeline.initialize();
    await pipeline.start();

    const processSpy = vi.fn();
    pipeline.on('event', (event) => {
      if (event.type === 'processing_start' ||
          event.type === 'processing_complete') {
        processSpy(event);
      }
    });

    // Simulate VAD speech end
    const mockAudio = new Float32Array(16000);
    pipeline.emit('event', {
      type: 'vad_speech_end',
      audio: mockAudio
    });

    // Wait for async processing
    await new Promise(resolve => setTimeout(resolve, 10));

    expect(processSpy).toHaveBeenCalledTimes(2);
    expect(processSpy).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'processing_start' })
    );
    expect(processSpy).toHaveBeenCalledWith(
      expect.objectContaining({ type: 'processing_complete' })
    );
  });
});
```

### Day 3-4: Minimal Demo Application

```html
<!-- examples/vanilla/index.html -->
<!DOCTYPE html>
<html lang="en">
<head>
  <meta charset="UTF-8">
  <meta name="viewport" content="width=device-width, initial-scale=1.0">
  <title>Voice Pipeline Demo - Phase 1</title>
  <style>
    body {
      font-family: system-ui, -apple-system, sans-serif;
      max-width: 800px;
      margin: 0 auto;
      padding: 2rem;
      background: #f5f5f5;
    }

    .container {
      background: white;
      border-radius: 8px;
      padding: 2rem;
      box-shadow: 0 2px 8px rgba(0,0,0,0.1);
    }

    h1 {
      color: #333;
      margin-bottom: 1.5rem;
    }

    .controls {
      display: flex;
      gap: 1rem;
      margin-bottom: 2rem;
    }

    button {
      padding: 0.75rem 1.5rem;
      border: none;
      border-radius: 4px;
      font-size: 1rem;
      cursor: pointer;
      transition: all 0.2s;
    }

    button:disabled {
      opacity: 0.5;
      cursor: not-allowed;
    }

    .btn-primary {
      background: #007bff;
      color: white;
    }

    .btn-primary:hover:not(:disabled) {
      background: #0056b3;
    }

    .btn-danger {
      background: #dc3545;
      color: white;
    }

    .btn-danger:hover:not(:disabled) {
      background: #c82333;
    }

    .status {
      padding: 1rem;
      border-radius: 4px;
      margin-bottom: 1rem;
    }

    .status.idle {
      background: #e9ecef;
      color: #495057;
    }

    .status.listening {
      background: #d4edda;
      color: #155724;
      animation: pulse 2s infinite;
    }

    .status.speaking {
      background: #cfe2ff;
      color: #084298;
    }

    .status.error {
      background: #f8d7da;
      color: #721c24;
    }

    @keyframes pulse {
      0%, 100% { opacity: 1; }
      50% { opacity: 0.7; }
    }

    .events {
      max-height: 300px;
      overflow-y: auto;
      border: 1px solid #dee2e6;
      border-radius: 4px;
      padding: 1rem;
      font-family: monospace;
      font-size: 0.875rem;
    }

    .event {
      padding: 0.25rem 0;
      border-bottom: 1px solid #f0f0f0;
    }

    .event:last-child {
      border-bottom: none;
    }

    .event-time {
      color: #6c757d;
      margin-right: 0.5rem;
    }

    .event-type {
      font-weight: bold;
      margin-right: 0.5rem;
    }

    .metrics {
      display: grid;
      grid-template-columns: repeat(auto-fit, minmax(150px, 1fr));
      gap: 1rem;
      margin-top: 1rem;
    }

    .metric {
      text-align: center;
      padding: 1rem;
      background: #f8f9fa;
      border-radius: 4px;
    }

    .metric-value {
      font-size: 1.5rem;
      font-weight: bold;
      color: #007bff;
    }

    .metric-label {
      font-size: 0.875rem;
      color: #6c757d;
      margin-top: 0.25rem;
    }
  </style>
</head>
<body>
  <div class="container">
    <h1>🎤 Voice Pipeline Demo - Phase 1</h1>

    <div id="status" class="status idle">
      Status: <span id="statusText">Idle</span>
    </div>

    <div class="controls">
      <button id="initBtn" class="btn-primary">Initialize</button>
      <button id="startBtn" class="btn-primary" disabled>Start Listening</button>
      <button id="stopBtn" class="btn-danger" disabled>Stop</button>
    </div>

    <div class="metrics">
      <div class="metric">
        <div class="metric-value" id="speechCount">0</div>
        <div class="metric-label">Speech Segments</div>
      </div>
      <div class="metric">
        <div class="metric-value" id="totalDuration">0s</div>
        <div class="metric-label">Total Duration</div>
      </div>
      <div class="metric">
        <div class="metric-value" id="avgEnergy">0</div>
        <div class="metric-label">Avg Energy</div>
      </div>
    </div>

    <h3>Events</h3>
    <div id="events" class="events"></div>
  </div>

  <script type="module" src="./app.js"></script>
</body>
</html>
```

```javascript
// examples/vanilla/app.js

import { VoicePipelineManager } from '@runanywhere/voice';
import { logger, LogLevel } from '@runanywhere/core';

// Configure logger for demo
logger.setLevel(LogLevel.DEBUG);

// UI Elements
const initBtn = document.getElementById('initBtn');
const startBtn = document.getElementById('startBtn');
const stopBtn = document.getElementById('stopBtn');
const statusEl = document.getElementById('status');
const statusTextEl = document.getElementById('statusText');
const eventsEl = document.getElementById('events');
const speechCountEl = document.getElementById('speechCount');
const totalDurationEl = document.getElementById('totalDuration');
const avgEnergyEl = document.getElementById('avgEnergy');

// State
let pipeline = null;
let speechCount = 0;
let totalDuration = 0;
let energySum = 0;
let energyCount = 0;

// Update UI status
function updateStatus(status, className = 'idle') {
  statusTextEl.textContent = status;
  statusEl.className = `status ${className}`;
}

// Add event to log
function addEvent(type, details = '') {
  const time = new Date().toLocaleTimeString();
  const eventDiv = document.createElement('div');
  eventDiv.className = 'event';
  eventDiv.innerHTML = `
    <span class="event-time">${time}</span>
    <span class="event-type">${type}</span>
    ${details ? `<span>${details}</span>` : ''}
  `;
  eventsEl.insertBefore(eventDiv, eventsEl.firstChild);

  // Keep only last 50 events
  while (eventsEl.children.length > 50) {
    eventsEl.removeChild(eventsEl.lastChild);
  }
}

// Update metrics
function updateMetrics(duration = 0, energy = 0) {
  if (duration > 0) {
    speechCount++;
    totalDuration += duration;
    speechCountEl.textContent = speechCount;
    totalDurationEl.textContent = `${totalDuration.toFixed(1)}s`;
  }

  if (energy > 0) {
    energySum += energy;
    energyCount++;
    const avgEnergy = energySum / energyCount;
    avgEnergyEl.textContent = avgEnergy.toFixed(3);
  }
}

// Initialize pipeline
initBtn.addEventListener('click', async () => {
  try {
    initBtn.disabled = true;
    updateStatus('Initializing...', 'idle');
    addEvent('INIT', 'Starting initialization');

    // Create pipeline with VAD enabled
    pipeline = new VoicePipelineManager({
      vad: {
        enabled: true,
        config: {
          positiveSpeechThreshold: 0.9,
          negativeSpeechThreshold: 0.75,
          minSpeechFrames: 5,
          frameSamples: 1536
        }
      }
    });

    // Set up event handlers
    pipeline.on('event', (event) => {
      console.log('Pipeline event:', event);

      switch (event.type) {
        case 'initialized':
          updateStatus('Ready', 'idle');
          addEvent('READY', 'Pipeline initialized');
          startBtn.disabled = false;
          break;

        case 'started':
          updateStatus('Listening...', 'listening');
          addEvent('STARTED', 'Pipeline started');
          startBtn.disabled = true;
          stopBtn.disabled = false;
          break;

        case 'stopped':
          updateStatus('Stopped', 'idle');
          addEvent('STOPPED', 'Pipeline stopped');
          startBtn.disabled = false;
          stopBtn.disabled = true;
          break;

        case 'vad_speech_start':
          updateStatus('Speaking...', 'speaking');
          addEvent('SPEECH_START', 'Voice activity detected');
          break;

        case 'vad_speech_end':
          updateStatus('Listening...', 'listening');
          const duration = event.audio.length / 16000;
          addEvent('SPEECH_END', `Duration: ${duration.toFixed(2)}s`);
          updateMetrics(duration);
          break;

        case 'processing_start':
          addEvent('PROCESSING', 'Processing audio');
          break;

        case 'processing_complete':
          addEvent('COMPLETE', 'Processing complete');
          break;

        case 'error':
          updateStatus(`Error: ${event.error.message}`, 'error');
          addEvent('ERROR', event.error.message);
          break;
      }
    });

    // Initialize the pipeline
    await pipeline.initialize();

  } catch (error) {
    console.error('Initialization error:', error);
    updateStatus(`Error: ${error.message}`, 'error');
    addEvent('ERROR', error.message);
    initBtn.disabled = false;
  }
});

// Start listening
startBtn.addEventListener('click', async () => {
  try {
    await pipeline.start();
  } catch (error) {
    console.error('Start error:', error);
    updateStatus(`Error: ${error.message}`, 'error');
    addEvent('ERROR', error.message);
  }
});

// Stop listening
stopBtn.addEventListener('click', () => {
  pipeline.stop();
});

// Clean up on page unload
window.addEventListener('beforeunload', () => {
  if (pipeline) {
    pipeline.destroy();
  }
});

// Log welcome message
addEvent('WELCOME', 'Voice Pipeline Demo - Phase 1');
addEvent('INFO', 'Click Initialize to begin');
```

### Day 5: Build Configuration & Scripts

```javascript
// vite.config.js (root)
import { defineConfig } from 'vite';
import path from 'path';

export default defineConfig({
  build: {
    lib: {
      entry: path.resolve(__dirname, 'packages/core/src/index.ts'),
      formats: ['es'],
      fileName: 'index'
    },
    rollupOptions: {
      external: ['eventemitter3']
    }
  },
  test: {
    globals: true,
    environment: 'jsdom',
    setupFiles: './test/setup.ts'
  }
});
```

```typescript
// test/setup.ts
import { expect, afterEach } from 'vitest';
import { cleanup } from '@testing-library/dom';

afterEach(() => {
  cleanup();
});

// Mock Web Audio API
global.AudioContext = class AudioContext {
  createGain() {
    return {
      gain: { value: 1 },
      connect: () => {},
      disconnect: () => {}
    };
  }

  createAnalyser() {
    return {
      fftSize: 2048,
      connect: () => {},
      disconnect: () => {}
    };
  }
};

// Mock MediaDevices
global.navigator.mediaDevices = {
  getUserMedia: async () => {
    return new MediaStream();
  }
};
```

## Deliverables Checklist

### ✅ Phase 1 Completion Criteria

- [ ] **Project Setup**
  - [ ] Monorepo structure with PNPM workspaces
  - [ ] TypeScript configuration with strict mode
  - [ ] Build tooling with Vite
  - [ ] Linting and formatting setup
  - [ ] Git hooks with Husky

- [ ] **Core Package**
  - [ ] Result type implementation
  - [ ] Branded types for type safety
  - [ ] Error system with custom error classes
  - [ ] Logger with configurable levels
  - [ ] DI Container with health monitoring

- [ ] **Voice Package**
  - [ ] VAD service using @ricky0123/vad-web
  - [ ] Basic pipeline manager
  - [ ] Event system for pipeline events
  - [ ] Health monitoring

- [ ] **Testing**
  - [ ] Unit tests for core utilities
  - [ ] Integration tests for VAD service
  - [ ] Pipeline manager tests
  - [ ] Test coverage > 80%

- [ ] **Demo Application**
  - [ ] Vanilla JavaScript demo
  - [ ] Real-time VAD visualization
  - [ ] Event logging
  - [ ] Metrics display

## Next Steps (Phase 2 Preview)

After completing Phase 1, Phase 2 will focus on:

1. **STT Integration** with Transformers.js
2. **Model Management** for downloading and caching models
3. **Web Workers** for background processing
4. **Audio Processing** utilities
5. **React Integration** package

## Running the Phase 1 Implementation

```bash
# Clone or create the repository
git clone <your-repo-url> web-voice-sdk
cd web-voice-sdk

# Install dependencies
pnpm install

# Build all packages
pnpm build

# Run tests
pnpm test

# Start demo application
cd examples/vanilla
pnpm dev

# Open http://localhost:5173 in your browser
```

## Common Issues and Solutions

### Issue: VAD Model Loading Fails
**Solution**: Ensure you're serving the app over HTTPS or localhost. VAD requires secure context for microphone access.

### Issue: TypeScript Errors in Strict Mode
**Solution**: Use the Result type for error handling and ensure all array accesses use optional chaining or guards.

### Issue: Build Fails with Module Resolution
**Solution**: Ensure all packages have proper exports field in package.json and use workspace protocol for internal dependencies.

## Summary

Phase 1 establishes the foundation for the web voice pipeline SDK with:

1. **Robust Architecture**: Clean separation of concerns with Foundation and Infrastructure layers
2. **Type Safety**: Strict TypeScript with Result types and branded types
3. **VAD Integration**: Working voice activity detection using @ricky0123/vad-web
4. **Testing Foundation**: Comprehensive test setup with Vitest
5. **Demo Application**: Functional demo showing VAD in action

This phase provides a solid foundation to build upon in subsequent phases, with clear patterns for adding STT, TTS, and LLM capabilities.
