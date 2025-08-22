/**
 * Branded types for type safety
 */
export type Brand<K, T> = K & { __brand: T };

export type SessionId = Brand<string, 'SessionId'>;
export type ModelId = Brand<string, 'ModelId'>;
export type DeviceId = Brand<string, 'DeviceId'>;
export type UserId = Brand<string, 'UserId'>;
export type PipelineId = Brand<string, 'PipelineId'>;
export type RequestId = Brand<string, 'RequestId'>;

export const SessionId = (id: string): SessionId => id as SessionId;
export const ModelId = (id: string): ModelId => id as ModelId;
export const DeviceId = (id: string): DeviceId => id as DeviceId;
export const UserId = (id: string): UserId => id as UserId;
export const PipelineId = (id: string): PipelineId => id as PipelineId;
export const RequestId = (id: string): RequestId => id as RequestId;
