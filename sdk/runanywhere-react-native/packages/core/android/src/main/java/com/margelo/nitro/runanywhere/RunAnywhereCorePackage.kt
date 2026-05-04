package com.margelo.nitro.runanywhere

import android.util.Log
import com.facebook.react.BaseReactPackage
import com.facebook.react.bridge.NativeModule
import com.facebook.react.bridge.ReactApplicationContext
import com.facebook.react.module.model.ReactModuleInfoProvider
import com.runanywhere.sdk.native.bridge.RunAnywhereBridge

class RunAnywhereCorePackage : BaseReactPackage() {
    override fun getModule(name: String, reactContext: ReactApplicationContext): NativeModule? {
        // Initialize secure storage with application context
        SecureStorageManager.initialize(reactContext.applicationContext)
        return null
    }

    override fun getReactModuleInfoProvider(): ReactModuleInfoProvider {
        return ReactModuleInfoProvider { HashMap() }
    }

    companion object {
        private const val TAG = "RunAnywhereCorePackage"

        init {
            System.loadLibrary("runanywherecore")
            Log.i(TAG, "Loaded native library: runanywherecore")

            // Install the OkHttp-backed platform HTTP transport (v2 close-out
            // Phase H6). Routes rac_http_request_* through OkHttp so Android
            // consumers get the system CA trust store, HTTP/2, proxies, and
            // NetworkSecurityConfig for free instead of libcurl.
            //
            // Idempotent; the C++ adapter guards on its own initialized flag.
            // Runs BEFORE any Nitro bridge has a chance to fire HTTP.
            try {
                val rc = RunAnywhereBridge.racHttpTransportRegisterOkHttp()
                if (rc == 0) {
                    Log.i(TAG, "OkHttp HTTP transport registered")
                } else {
                    Log.w(TAG, "OkHttp HTTP transport registration returned rc=$rc")
                }
            } catch (t: Throwable) {
                // Link errors here indicate the bundled librac_commons.so
                // predates the rac_http_transport_register symbol (commons
                // versions below 0.2.0). Falls back to libcurl.
                Log.w(TAG, "OkHttp HTTP transport unavailable: ${t.message}")
            }
        }
    }
}
