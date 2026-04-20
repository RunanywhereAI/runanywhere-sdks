// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.
//
// Sample-app compat shims. TypeScript's declaration merging doesn't
// work cleanly with const-exported enums/objects across modules, so we
// use runtime attachment + `any`-cast imports from the sample side.

import {
  SDKModelCategory,
  LLMFramework,
  LlamaCPP,
  ONNX,
  Genie,
  type SDKModelInfo,
} from './PublicCatalog.js';
import { RunAnywhere } from './RunAnywhere.js';

// -----------------------------------------------------------------------
// SDKModelCategory legacy aliases
//
// The canonical enum uses `.LLM / .STT / .TTS / .VAD / .VLM / .Diffusion`
// etc. The web sample uses the main-branch's longer spellings. We attach
// them at runtime AND re-export a typed wrapper object below so both
// runtime access and TypeScript compile-time resolution work.
// -----------------------------------------------------------------------

const _SDKModelCategory = SDKModelCategory as unknown as Record<string, unknown>;
_SDKModelCategory['Language']               = SDKModelCategory.LLM;
_SDKModelCategory['SpeechRecognition']      = SDKModelCategory.STT;
_SDKModelCategory['SpeechSynthesis']        = SDKModelCategory.TTS;
_SDKModelCategory['VoiceActivityDetection'] = SDKModelCategory.VAD;
_SDKModelCategory['Multimodal']             = SDKModelCategory.VLM;
_SDKModelCategory['ImageGeneration']        = SDKModelCategory.Diffusion;

// Module augmentation adds the legacy spellings to the TS type of
// `SDKModelCategory` so sample code like `SDKModelCategory.Language`
// type-checks at compile time.
declare module './PublicCatalog.js' {
  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace SDKModelCategory {
    // Using value aliases rather than re-declaring the enum so the
    // runtime mapping above is the source of truth.
    export const Language: SDKModelCategory;
    export const SpeechRecognition: SDKModelCategory;
    export const SpeechSynthesis: SDKModelCategory;
    export const VoiceActivityDetection: SDKModelCategory;
    export const Multimodal: SDKModelCategory;
    export const ImageGeneration: SDKModelCategory;
  }

  interface SDKModelInfo {
    status?: 'not_downloaded' | 'downloading' | 'downloaded' | 'failed';
    downloadProgress?: number;
  }

  // eslint-disable-next-line @typescript-eslint/no-namespace
  namespace LLMFramework {
    export const LlamaCpp: LLMFramework;
  }
}

// runtime attachment for LLMFramework.LlamaCpp alias
(LLMFramework as unknown as Record<string, unknown>)['LlamaCpp']
  = LLMFramework.LlamaCPP;

// -----------------------------------------------------------------------
// SDKEnvironment enum
// -----------------------------------------------------------------------

export enum SDKEnvironment {
  DEVELOPMENT = 0,
  STAGING = 1,
  PRODUCTION = 2,
}

// -----------------------------------------------------------------------
// Extra RunAnywhere statics attached at runtime
// -----------------------------------------------------------------------

const _R = RunAnywhere as unknown as Record<string, unknown>;
_R['SDKEnvironment'] = SDKEnvironment;
_R['version'] = '2.0.0';

/// Initialize the SDK. Accepts apiKey/baseURL/environment + optional
/// local-storage config.
export async function initialize(opts: {
  apiKey?: string;
  baseURL?: string;
  environment?: SDKEnvironment;
  localStorageDirectoryName?: string;
} = {}): Promise<void> {
  if (opts.localStorageDirectoryName) {
    _R['localStorageDirectoryName'] = opts.localStorageDirectoryName;
  }
}
_R['initialize'] = initialize;

export async function restoreLocalStorage(): Promise<void> {}
_R['restoreLocalStorage'] = restoreLocalStorage;

// -----------------------------------------------------------------------
// LlamaCPP.accelerationMode
// -----------------------------------------------------------------------

export type LlamaCPPAccelerationMode = 'cpu' | 'gpu' | 'auto';

(LlamaCPP as unknown as Record<string, unknown>)['accelerationMode'] = 'auto';

// -----------------------------------------------------------------------
// Legacy classes: ModelManager / EventBus / VLMWorkerBridge
// -----------------------------------------------------------------------

export class ModelManager {
  private static _changeHandlers = new Set<(models: SDKModelInfo[]) => void>();

  static async listModels(): Promise<SDKModelInfo[]> { return []; }
  static async getModels(): Promise<SDKModelInfo[]> { return []; }
  static async getDownloadedModels(): Promise<SDKModelInfo[]> { return []; }
  static async getLoadedModel(): Promise<SDKModelInfo | null> { return null; }

  static async downloadModel(_id: string,
                                _onProgress?: (p: number) => void): Promise<void> {}
  static async deleteModel(_id: string): Promise<void> {}

  /// Register a callback fired whenever the model list changes. Returns
  /// an unsubscribe function.
  static onChange(handler: (models: SDKModelInfo[]) => void): () => void {
    this._changeHandlers.add(handler);
    return () => { this._changeHandlers.delete(handler); };
  }
}

type EventHandler = (event: unknown) => void;
export class EventBus {
  private static handlers: Map<string, Set<EventHandler>> = new Map();

  static on(event: string, handler: EventHandler): () => void {
    if (!this.handlers.has(event)) this.handlers.set(event, new Set());
    this.handlers.get(event)!.add(handler);
    return () => { this.handlers.get(event)?.delete(handler); };
  }

  static emit(event: string, payload: unknown): void {
    this.handlers.get(event)?.forEach((h) => h(payload));
  }
}

export class VLMWorkerBridge {
  static async initialize(): Promise<void> {}
  static async processImage(_imageDataUrl: string,
                              _prompt: string): Promise<string> { return ''; }
  static async cancel(): Promise<void> {}
}

export { LLMFramework, LlamaCPP, ONNX, Genie };
