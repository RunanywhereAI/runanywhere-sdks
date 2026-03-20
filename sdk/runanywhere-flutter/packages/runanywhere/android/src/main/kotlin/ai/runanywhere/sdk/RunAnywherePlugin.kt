package ai.runanywhere.sdk

import android.os.Build
import io.flutter.embedding.engine.plugins.FlutterPlugin
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result

/**
 * RunAnywhere Flutter Plugin - Android Implementation
 *
 * This plugin provides the native bridge for the RunAnywhere SDK on Android.
 * The actual AI functionality is provided by RACommons native libraries (.so files).
 */
class RunAnywherePlugin : FlutterPlugin, MethodCallHandler {
    private lateinit var channel: MethodChannel

    companion object {
        private const val CHANNEL_NAME = "runanywhere"
        private const val SDK_VERSION = "0.15.8"
        private const val COMMONS_VERSION = "0.1.4"

        init {
            // Load RACommons native libraries
            try {
                System.loadLibrary("rac_commons")
            } catch (e: UnsatisfiedLinkError) {
                // Library may not be available in all configurations
                android.util.Log.w("RunAnywhere", "Failed to load rac_commons: ${e.message}")
            }
        }
    }

    override fun onAttachedToEngine(flutterPluginBinding: FlutterPlugin.FlutterPluginBinding) {
        channel = MethodChannel(flutterPluginBinding.binaryMessenger, CHANNEL_NAME)
        channel.setMethodCallHandler(this)
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        when (call.method) {
            "getPlatformVersion" -> {
                result.success("Android ${Build.VERSION.RELEASE}")
            }
            "getSDKVersion" -> {
                result.success(SDK_VERSION)
            }
            "getCommonsVersion" -> {
                result.success(COMMONS_VERSION)
            }
            else -> {
                result.notImplemented()
            }
        }
    }

    override fun onDetachedFromEngine(binding: FlutterPlugin.FlutterPluginBinding) {
        channel.setMethodCallHandler(null)
    }
}
