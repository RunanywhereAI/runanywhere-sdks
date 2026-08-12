/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public event types are the generated Wire proto types. Local DTO event
 * classes were removed so Kotlin uses the same canonical SDKEvent envelope
 * as the stable C++ event stream.
 */

package com.runanywhere.sdk.public.events

typealias SDKEvent = ai.runanywhere.proto.v1.SDKEvent
typealias EventCategory = ai.runanywhere.proto.v1.EventCategory
typealias EventDestination = ai.runanywhere.proto.v1.EventDestination

// `ComponentInitializationEvent`/`FailureEvent`/`ModelRegistryEvent`/
// `DownloadEvent`/`StorageLifecycleEvent`/`PerformanceEvent` are deleted
// outright (idl/sdk_events.proto): `FailureEvent`'s fields moved onto the
// SDKEvent envelope itself (`error`, `component`, `operation_id`);
// `DownloadEvent`/`ModelRegistryEvent` were absorbed into `ModelEvent`
// outright ("+ model_registry, + download"); `ComponentInitializationEvent`
// is superseded by `InitializationEvent`; `StorageLifecycleEvent` by
// `StorageEvent`; `PerformanceEvent` has no replacement (nothing in commons
// emits it). Mirrors Swift's typed `RA*Event` usage in EventBus.swift/Events.swift.
typealias InitializationEvent = ai.runanywhere.proto.v1.InitializationEvent
typealias ConfigurationEvent = ai.runanywhere.proto.v1.ConfigurationEvent
typealias ComponentLifecycleEvent = ai.runanywhere.proto.v1.ComponentLifecycleEvent
typealias GenerationEvent = ai.runanywhere.proto.v1.GenerationEvent
typealias ModelEvent = ai.runanywhere.proto.v1.ModelEvent
typealias NetworkEvent = ai.runanywhere.proto.v1.NetworkEvent
typealias StorageEvent = ai.runanywhere.proto.v1.StorageEvent
typealias FrameworkEvent = ai.runanywhere.proto.v1.FrameworkEvent
typealias DeviceEvent = ai.runanywhere.proto.v1.DeviceEvent
typealias VoiceLifecycleEvent = ai.runanywhere.proto.v1.VoiceLifecycleEvent
typealias VoiceEvent = ai.runanywhere.proto.v1.VoiceEvent
typealias SessionEvent = ai.runanywhere.proto.v1.SessionEvent
typealias AuthEvent = ai.runanywhere.proto.v1.AuthEvent
typealias HardwareRoutingEvent = ai.runanywhere.proto.v1.HardwareRoutingEvent
typealias CapabilityOperationEvent = ai.runanywhere.proto.v1.CapabilityOperationEvent
typealias TelemetryEvent = ai.runanywhere.proto.v1.TelemetryEvent
typealias CancellationEvent = ai.runanywhere.proto.v1.CancellationEvent
