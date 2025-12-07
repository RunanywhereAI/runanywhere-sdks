package com.runanywhere.reactnative

import android.util.Log
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.bridge.ReactContextBaseJavaModule
import com.facebook.react.bridge.ReactMethod
import com.facebook.react.module.annotations.ReactModule
import com.facebook.react.turbomodule.core.CallInvokerHolderImpl
import com.facebook.react.turbomodule.core.interfaces.TurboModule

/**
 * RunAnywhere React Native Module with C++ TurboModule Support
 *
 * This Kotlin module:
 * 1. Loads the native library containing our C++ HostObject
 * 2. Installs the C++ module into the JSI runtime
 * 3. Registers with React Native's module system
 *
 * The actual business logic is implemented in:
 * - cpp/RunAnywhereModule.cpp (cross-platform C++ TurboModule)
 * - android/src/main/cpp/react-native-runanywhere.cpp (JNI bridge)
 */
@ReactModule(name = RunAnywhereModule.NAME)
class RunAnywhereModule(private val reactContext: ReactApplicationContext) :
    ReactContextBaseJavaModule(reactContext), TurboModule {

    companion object {
        const val NAME = "RunAnywhere"
        private const val TAG = "RunAnywhereModule"

        @Volatile
        private var isLibraryLoaded = false

        @Volatile
        private var isInstalled = false

        init {
            try {
                // Load dependencies in correct order
                Log.i(TAG, "Loading native libraries in dependency order...")

                // 1. Base dependencies
                System.loadLibrary("c++_shared")
                Log.d(TAG, "  Loaded: libc++_shared.so")

                // 2. OpenMP (required by LlamaCpp)
                try {
                    System.loadLibrary("omp")
                    Log.d(TAG, "  Loaded: libomp.so")
                } catch (e: UnsatisfiedLinkError) {
                    Log.w(TAG, "  libomp.so not found (may be bundled in LlamaCpp)")
                }

                // 3. LlamaCpp backend (works independently of ONNX)
                System.loadLibrary("runanywhere_llamacpp")
                Log.d(TAG, "  Loaded: librunanywhere_llamacpp.so")

                // 4. Our React Native native module (includes bridge stub)
                // NOTE: We use the stub implementation that doesn't require
                // the full bridge library (which has ONNX compatibility issues)
                System.loadLibrary("runanywhere-react-native")
                Log.d(TAG, "  Loaded: librunanywhere-react-native.so")

                isLibraryLoaded = true
                Log.i(TAG, "Native libraries loaded successfully (LlamaCpp only, ONNX support requires compatible binaries)")

                // NOTE: ONNX/STT/TTS support is currently disabled on Android due to
                // binary compatibility issues with the pre-built libraries.
                // When compatible binaries are available, uncomment the following:
                //
                // System.loadLibrary("onnxruntime")
                // System.loadLibrary("sherpa-onnx-cxx-api")
                // System.loadLibrary("sherpa-onnx-c-api")
                // System.loadLibrary("runanywhere_onnx")
                // System.loadLibrary("runanywhere_bridge")
            } catch (e: UnsatisfiedLinkError) {
                Log.e(TAG, "Failed to load native library: ${e.message}")
                isLibraryLoaded = false
            }
        }
    }

    // JNI native method declaration - must match the function in react-native-runanywhere.cpp
    private external fun nativeInstall(jsiPtr: Long)

    override fun getName(): String = NAME

    override fun initialize() {
        super.initialize()
        installNativeModule()
    }

    /**
     * Install the C++ HostObject into the JSI runtime.
     * This must be called after the JavaScript runtime is ready.
     */
    private fun installNativeModule() {
        if (!isLibraryLoaded) {
            Log.e(TAG, "Cannot install native module - library not loaded")
            return
        }

        if (isInstalled) {
            Log.d(TAG, "Native module already installed")
            return
        }

        try {
            // Get the JSI runtime pointer from React Native
            val jsContextHolder = reactContext.javaScriptContextHolder
            if (jsContextHolder == null) {
                Log.e(TAG, "JavaScript context holder is null")
                return
            }

            val jsContextPtr = jsContextHolder.get()
            if (jsContextPtr == 0L) {
                Log.e(TAG, "JavaScript context is not available (ptr = 0)")
                return
            }

            Log.i(TAG, "Installing native module with JSI runtime pointer: $jsContextPtr")
            nativeInstall(jsContextPtr)
            isInstalled = true
            Log.i(TAG, "Native module installed successfully")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to install native module: ${e.message}", e)
        }
    }

    /**
     * Manually trigger installation from JavaScript if auto-install didn't work.
     * This can be called via NativeModules.RunAnywhere.install()
     */
    @ReactMethod(isBlockingSynchronousMethod = true)
    fun install(): Boolean {
        installNativeModule()
        return isInstalled
    }

    override fun invalidate() {
        isInstalled = false
        super.invalidate()
    }
}
