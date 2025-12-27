/**
 * TTSConfiguration.ts
 *
 * Core TTS configuration interface used by TTS services
 *
 * Reference: sdk/runanywhere-swift/Sources/RunAnywhere/Core/Models/Configuration/TTSConfiguration.swift
 */

import type { SDKComponent } from '../Common/SDKComponent';

export interface TTSConfiguration {
  componentType?: SDKComponent;
  modelId?: string | null;
  voice?: string;
  language?: string;
  speakingRate?: number;
  pitch?: number;
  volume?: number;
  audioFormat?: string;
  useNeuralVoice?: boolean;
  enableSSML?: boolean;
  validate?: () => void;
}
