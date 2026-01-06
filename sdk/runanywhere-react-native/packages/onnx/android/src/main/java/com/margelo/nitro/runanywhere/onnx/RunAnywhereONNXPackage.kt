package com.margelo.nitro.runanywhere.onnx

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider

/**
 * React Native package for RunAnywhere ONNX backend.
 * This class is required for React Native autolinking.
 */
class RunAnywhereONNXPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider { HashMap() }
    }

    companion object {
        init {
            // Load the native library which registers the HybridObject factory
            try {
                System.loadLibrary("runanywhere_onnx")
            } catch (e: UnsatisfiedLinkError) {
                // Native library may already be loaded or bundled differently
                android.util.Log.e("RunAnywhereONNXPackage", "Failed to load runanywhere_onnx: ${e.message}")
            }
        }
    }
}
