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

typealias ComponentInitializationEvent = ai.runanywhere.proto.v1.ComponentInitializationEvent
typealias ComponentLifecycleEvent = ai.runanywhere.proto.v1.ComponentLifecycleEvent
typealias FailureEvent = ai.runanywhere.proto.v1.FailureEvent
typealias GenerationEvent = ai.runanywhere.proto.v1.GenerationEvent
typealias ModelEvent = ai.runanywhere.proto.v1.ModelEvent
typealias ModelRegistryEvent = ai.runanywhere.proto.v1.ModelRegistryEvent
typealias DownloadEvent = ai.runanywhere.proto.v1.DownloadEvent
typealias StorageLifecycleEvent = ai.runanywhere.proto.v1.StorageLifecycleEvent
typealias NetworkEvent = ai.runanywhere.proto.v1.NetworkEvent
typealias PerformanceEvent = ai.runanywhere.proto.v1.PerformanceEvent
typealias VoiceEvent = ai.runanywhere.proto.v1.VoiceEvent
