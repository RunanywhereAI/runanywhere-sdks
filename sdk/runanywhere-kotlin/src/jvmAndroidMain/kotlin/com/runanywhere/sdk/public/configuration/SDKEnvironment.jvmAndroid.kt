/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * jvmAndroidMain actuals for SDKEnvironment helper / SDKInitParams.validate.
 * Delegates to the `racEnv*` JNI thunks declared on `RunAnywhereBridge`. Falls
 * back to conservative C++-equivalent defaults when the native binding is
 * unreachable (mirrors the existing fallback behaviour in
 * `CppBridgeEnvironment`).
 */

package com.runanywhere.sdk.public.configuration

import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeEnvironment

internal actual fun sdkEnvironmentRequiresAuthentication(env: SDKEnvironment): Boolean =
    CppBridgeEnvironment.requiresAuth(env)

internal actual fun sdkEnvironmentRequiresBackendURL(env: SDKEnvironment): Boolean =
    CppBridgeEnvironment.requiresBackendURL(env)

internal actual fun sdkInitParamsValidateApiKey(key: String, env: SDKEnvironment): Boolean =
    CppBridgeEnvironment.validateAPIKey(key = key, env = env)

internal actual fun sdkInitParamsValidateBaseUrl(url: String, env: SDKEnvironment): Boolean =
    CppBridgeEnvironment.validateBaseURL(url = url, env = env)

internal actual fun sdkInitParamsValidationErrorMessage(
    env: SDKEnvironment,
    key: String,
    url: String,
): String? = CppBridgeEnvironment.validationErrorMessage(env = env, key = key, url = url)
