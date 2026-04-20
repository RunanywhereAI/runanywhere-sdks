// SPDX-License-Identifier: Apache-2.0
// Copyright (c) 2026 RunAnywhere AI, Inc.

export enum ModelFormat {
  Unknown        = 0,
  GGUF           = 1,
  ONNX           = 2,
  CoreML         = 3,
  MLXSafetensors = 4,
  ExecuTorchPTE  = 5,
  WhisperKit     = 6,
  OpenVINOIR     = 7,
}

export enum Environment {
  Development = 0,
  Staging     = 1,
  Production  = 2,
}

export enum LogLevel {
  Trace = 0, Debug = 1, Info = 2, Warn = 3, Error = 4, Fatal = 5,
}

export enum LLMTokenKind { Answer = 1, Thought = 2, ToolCall = 3 }

export interface LLMToken {
  text: string;
  kind: LLMTokenKind;
  isFinal: boolean;
}

export interface TranscriptChunk {
  text: string;
  isPartial: boolean;
  confidence: number;
  audioStartUs: number;
  audioEndUs: number;
}

export interface VADEvent {
  kind: 'unknown' | 'voice_start' | 'voice_end' | 'barge_in' | 'silence';
  frameOffsetUs: number;
  energy: number;
}

export interface AuthData {
  accessToken: string;
  refreshToken?: string;
  expiresAt?: number;
  userId?: string;
  organizationId?: string;
  deviceId?: string;
}

export class RunAnywhereError extends Error {
  static readonly BACKEND_UNAVAILABLE = -6;
  static readonly CANCELLED           = -1;
  constructor(public code: number, message: string) {
    super(`[${code}] ${message}`);
    this.name = 'RunAnywhereError';
  }
}
