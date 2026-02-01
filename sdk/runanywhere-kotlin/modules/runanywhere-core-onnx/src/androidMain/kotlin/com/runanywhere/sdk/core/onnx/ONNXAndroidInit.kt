/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 *
 * Android-specific initialization for ONNX module.
 * Registers the Kokoro TTS provider for NPU-accelerated TTS.
 */

package com.runanywhere.sdk.core.onnx

import android.content.Context
import android.util.Log
import com.runanywhere.sdk.core.onnx.tts.KokoroTTSProviderImpl
import com.runanywhere.sdk.foundation.bridge.extensions.KokoroTTSRegistry
import java.lang.ref.WeakReference

/**
 * Android-specific initialization for ONNX module.
 * 
 * Call [initialize] before [ONNX.register] to enable Kokoro TTS with NPU acceleration.
 * 
 * Usage:
 * ```kotlin
 * // In Application.onCreate() or similar:
 * AndroidPlatformContext.initialize(this)  // SDK context
 * ONNXAndroid.initialize(this)             // ONNX module context
 * ONNX.register()                          // Register backends (includes Kokoro)
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
     * Must be called before [ONNX.register] to enable Kokoro TTS provider.
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
        
        // Store context for later use
        contextRef = WeakReference(context.applicationContext)
        
        // Register Kokoro TTS provider DIRECTLY (not via callback)
        // This ensures registration happens immediately
        registerKokoroProvider()
        
        isInitialized = true
        Log.i(TAG, "ONNX Android module initialized, hasProvider=${KokoroTTSRegistry.hasProvider}")
    }
    
    /**
     * Register the Kokoro TTS provider.
     * Called directly during initialization.
     */
    private fun registerKokoroProvider() {
        Log.i(TAG, "registerKokoroProvider() called")
        
        val context = contextRef?.get()
        if (context == null) {
            Log.e(TAG, "Cannot register Kokoro provider: context not available")
            return
        }
        
        Log.i(TAG, "Context available: ${context.javaClass.simpleName}")
        
        try {
            Log.i(TAG, "Registering Kokoro TTS provider for NPU acceleration")
            KokoroTTSProviderImpl.register(context)
            Log.i(TAG, "Kokoro TTS provider registered successfully")
            Log.i(TAG, "KokoroTTSRegistry.hasProvider = ${KokoroTTSRegistry.hasProvider}")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to register Kokoro TTS provider: ${e.message}", e)
            e.printStackTrace()
        }
    }
    
    /**
     * Get the stored context (for lazy provider creation).
     */
    @JvmStatic
    fun getContext(): Context? = contextRef?.get()
    
    /**
     * Check if the module is initialized.
     */
    @JvmStatic
    fun isInitialized(): Boolean = isInitialized
}
