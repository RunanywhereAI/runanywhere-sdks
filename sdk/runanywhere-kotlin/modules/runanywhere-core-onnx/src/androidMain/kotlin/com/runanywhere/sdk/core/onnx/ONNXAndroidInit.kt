/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android-specific initialization for ONNX module.
 */

package com.runanywhere.sdk.core.onnx

import android.content.Context
import android.util.Log
import java.lang.ref.WeakReference

/**
 * Android-specific initialization for ONNX module.
 *
 * Usage:
 * ```kotlin
 * AndroidPlatformContext.initialize(this)
 * ONNXAndroid.initialize(this)
 * ONNX.register()
 * ```
 */
object ONNXAndroid {
    private const val TAG = "ONNXAndroid"

    @Volatile
    private var contextRef: WeakReference<Context>? = null

    @Volatile
    private var isInitialized = false

    /**
     * Initialize the ONNX Android module.
     *
     * @param context Application context
     */
    @JvmStatic
    fun initialize(context: Context) {
        if (isInitialized) {
            Log.d(TAG, "ONNXAndroid already initialized")
            return
        }

        Log.i(TAG, "Initializing ONNX Android module")

        contextRef = WeakReference(context.applicationContext)
        isInitialized = true
        Log.i(TAG, "ONNX Android module initialized")
    }

    @JvmStatic
    fun getContext(): Context? = contextRef?.get()

    @JvmStatic
    fun isInitialized(): Boolean = isInitialized
}
