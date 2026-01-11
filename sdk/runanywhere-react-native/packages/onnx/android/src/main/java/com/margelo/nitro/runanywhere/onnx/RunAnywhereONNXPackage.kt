package com.margelo.nitro.runanywhere.onnx

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.margelo.nitro.runanywhere.SDKLogger

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
        private val logger = SDKLogger("ONNX")

        init {
            // Load the native library which registers the HybridObject factory
            // The library name must match CMakeLists.txt PACKAGE_NAME: "runanywhereonnx"
            try {
                System.loadLibrary("runanywhereonnx")
            } catch (e: UnsatisfiedLinkError) {
                // Native library may already be loaded or bundled differently
                logger.error("Failed to load runanywhereonnx: ${e.message}")
            }
        }
    }
}
