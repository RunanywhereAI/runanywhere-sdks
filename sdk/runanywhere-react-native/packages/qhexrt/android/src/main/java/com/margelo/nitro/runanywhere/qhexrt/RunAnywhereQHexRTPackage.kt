package com.margelo.nitro.runanywhere.qhexrt

import android.content.Context
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.margelo.nitro.runanywhere.SDKLogger

/**
 * React Native package for the RunAnywhere QHexRT (Qualcomm Hexagon NPU) backend.
 * This class is required for React Native autolinking.
 */
class RunAnywhereQHexRTPackage(context: Context) : BaseReactPackage() {
    init {
        if (nativeLibraryLoaded) {
            runCatching {
                val skelDirectory = QHexRTSkelInstaller.install(context.applicationContext)
                nativeSetSkelDirectory(skelDirectory)
            }.onFailure { error ->
                log.error("Failed to install QHexRT DSP skels: ${error.message}")
            }
        }
    }

    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider { HashMap() }
    }

    companion object {
        private val log = SDKLogger("NPU.QHexRT")

        private val nativeLibraryLoaded =
            // Load the native library which registers the HybridObject factory.
            try {
                System.loadLibrary("runanywhereqhexrt")
                true
            } catch (e: UnsatisfiedLinkError) {
                // Native library may already be loaded or bundled differently.
                log.error("Failed to load runanywhereqhexrt: ${e.message}")
                false
            }

        @JvmStatic
        private external fun nativeSetSkelDirectory(path: String?)
    }
}
