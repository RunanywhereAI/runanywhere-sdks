package com.margelo.nitro.runanywhere.llama

import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.margelo.nitro.runanywhere.SDKLogger

/**
 * React Native package for RunAnywhere LlamaCPP backend.
 * This class is required for React Native autolinking.
 */
class RunAnywhereLlamaPackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider { HashMap() }
    }

    companion object {
        private val log = SDKLogger("LLM.LlamaCpp")

        init {
            // Load the native library which registers the HybridObject factory
            try {
                System.loadLibrary("runanywherellama")
            } catch (e: UnsatisfiedLinkError) {
                // Native library may already be loaded or bundled differently
                log.error("Failed to load runanywherellama: ${e.message}")
            }
        }
    }
}
