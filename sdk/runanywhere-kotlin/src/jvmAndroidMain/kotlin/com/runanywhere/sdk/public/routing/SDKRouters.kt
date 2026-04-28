/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Public accessors for the SDK-wide built-in routers.
 *
 * Most apps don't need to construct their own [HybridRouter] — the SDK already
 * owns one per capability and registers loaded models / cloud backends with
 * it automatically. Use this object to inspect that router or to call it
 * directly with custom policies.
 */
package com.runanywhere.sdk.public.routing

import com.runanywhere.sdk.foundation.bridge.extensions.RouterRegistration

object SDKRouters {
    /** The SDK-wide STT router. Same instance the SDK uses internally. */
    fun stt(): HybridRouter = RouterRegistration.sttRouter()
}
