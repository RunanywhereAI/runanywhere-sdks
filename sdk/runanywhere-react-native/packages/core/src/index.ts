/**
 * @runanywhere/core - React Native public SDK facade.
 *
 * Swift is the source of truth for this surface. Generated DTOs/enums come
 * directly from `@runanywhere/proto-ts/*`; this root exports only the
 * RunAnywhere facade and the small RN call-site types/errors that do not have
 * a standalone generated package entry.
 *
 * Provider/internal plumbing lives at `@runanywhere/core/internal`.
 *
 * @packageDocumentation
 */

export { RunAnywhere } from './Public/RunAnywhere';

export { SDKEnvironment } from '@runanywhere/proto-ts/model_types';
export type { SDKInitOptions } from './types/models';

export {
  ErrorCode,
  ErrorCategory,
  SDKException,
  isSDKException,
  asSDKException,
} from './Foundation/Errors';
export type { ErrorContext } from './Foundation/Errors';

export { EventBus } from './Public/Events/EventBus';
export type {
  EventBusCancellable,
  SDKEventHandler,
} from './Public/Events/EventBus';

export type {
  PluginInfo,
  PluginLoaderCapability,
} from './Public/Extensions/RunAnywhere+PluginLoader';

export type { ToolExecutor } from './Public/Extensions/LLM/RunAnywhere+ToolCalling';
