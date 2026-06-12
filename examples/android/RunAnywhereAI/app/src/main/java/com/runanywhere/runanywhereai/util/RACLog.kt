package com.runanywhere.runanywhereai.util

import android.util.Log
import com.runanywhere.runanywhereai.BuildConfig

// Zero-dependency logger. Auto-tags from the calling class; debug/info/verbose are silenced
// in release. Route release warnings/errors by setting [errorReporter]. Never log user
// content (prompts, messages) or secrets — debug logs leak via bug reports and screen shares.
object RACLog {

    // Debug/info/verbose only emit when true (off in release builds).
    var enabled: Boolean = BuildConfig.DEBUG

    // Optional sink for w/e — wire to crash reporting at startup. Invoked in every build.
    var errorReporter: ((priority: Int, tag: String, message: String, throwable: Throwable?) -> Unit)? = null

    fun v(message: String, throwable: Throwable? = null) = log(Log.VERBOSE, message, throwable)
    fun d(message: String, throwable: Throwable? = null) = log(Log.DEBUG, message, throwable)
    fun i(message: String, throwable: Throwable? = null) = log(Log.INFO, message, throwable)
    fun w(message: String, throwable: Throwable? = null) = log(Log.WARN, message, throwable)
    fun e(message: String, throwable: Throwable? = null) = log(Log.ERROR, message, throwable)

    private fun log(priority: Int, message: String, throwable: Throwable?) {
        val report = priority >= Log.WARN && errorReporter != null
        if (!enabled && !report) return // nothing to do — skip the tag lookup entirely

        val tag = callerTag()
        if (enabled) {
            if (throwable != null) {
                Log.println(priority, tag, message + '\n' + Log.getStackTraceString(throwable))
            } else {
                Log.println(priority, tag, message)
            }
        }
        if (report) errorReporter?.invoke(priority, tag, message, throwable)
    }

    // Walk past RACLog's own frames to the caller and use its simple class name as the tag.
    private fun callerTag(): String {
        val self = RACLog::class.java.name
        val caller = Throwable().stackTrace.firstOrNull { it.className != self }
        return caller?.className?.substringAfterLast('.')?.substringBefore('$') ?: "RACLog"
    }
}