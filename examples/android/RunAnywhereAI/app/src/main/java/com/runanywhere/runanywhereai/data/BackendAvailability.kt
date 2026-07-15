package com.runanywhere.runanywhereai.data

import ai.runanywhere.proto.v1.InferenceFramework
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.npu.qhexrt.QHexRT
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.withContext
import kotlin.coroutines.cancellation.CancellationException

/**
 * Runtime view of which inference backends can actually serve a model on this
 * build + device, so the pickers can hide/disable rows whose backend is absent.
 *
 * ## Why this exists
 * The catalog is shared across every SDK build flavor, but a given APK only
 * packages a subset of native backends (e.g. an NPU-only slice ships QHexRT but
 * not the Sherpa speech JNI). A row whose backend is missing looks tappable and
 * then hard-fails at load with `-422 "No provider could handle the request"`.
 * Filtering on availability turns that silent failure into an honest
 * "unavailable" state.
 *
 * ## Signal sources (all best-effort — the SDK exposes no public
 * "list registered backends" query)
 * - **QHEXRT** — [QHexRT.probeNpu] is a real public device probe; a part outside
 *   the V75/V79/V81 support set (or an x86 emulator) reports
 *   `qhexrt_supported = false`. This is authoritative and correct for both the
 *   NPU-only and the full build.
 * - **LlamaCPP / ONNX / Sherpa** — no public runtime signal exists. The SDK
 *   modules register these at bootstrap and swallow failures (logging, never
 *   throwing to the app), so we cannot observe the outcome from the app module.
 *   [reportRegistration] lets bootstrap forward what it learned; until it does,
 *   these default to **available** so a full build never wrongly hides a working
 *   row. The limitation: on a build that fails to package one of these JNIs and
 *   does not call [reportRegistration], its rows stay visible and fail at load
 *   exactly as before — no worse than today, better once the hook is wired.
 */
object BackendAvailability {

    // Frameworks the app treats as "always present unless proven otherwise".
    // QHEXRT is deliberately excluded: it is proven via the native probe below.
    private val defaultAvailable = setOf(
        InferenceFramework.INFERENCE_FRAMEWORK_LLAMA_CPP,
        InferenceFramework.INFERENCE_FRAMEWORK_ONNX,
        InferenceFramework.INFERENCE_FRAMEWORK_SHERPA,
        // Platform built-ins are served by the OS, not a packaged backend.
        InferenceFramework.INFERENCE_FRAMEWORK_SYSTEM_TTS,
        InferenceFramework.INFERENCE_FRAMEWORK_BUILT_IN,
    )

    private val mutableState = MutableStateFlow(Snapshot())

    /** Latest availability snapshot; pickers collect this to re-filter live. */
    val snapshots: StateFlow<Snapshot> = mutableState

    /**
     * Whether [framework] can serve a model in this process right now.
     *
     * Unknown frameworks default to `true` so the pickers never over-hide when a
     * new backend enum lands before this map learns about it — the row then
     * surfaces its own load error, which is the pre-existing behavior.
     */
    fun isAvailable(framework: InferenceFramework): Boolean =
        mutableState.value.available[framework] ?: true

    /**
     * Probe the device-dependent backends (currently only QHexRT). Safe to call
     * repeatedly; runs on the caller's dispatcher and never throws.
     */
    suspend fun refresh() {
        // probeNpu loads the native library and calls into JNI; keep it off the
        // main thread (viewModelScope defaults to Main).
        val qhexrtSupported = withContext(Dispatchers.IO) {
            try {
                QHexRT.probeNpu().qhexrt_supported
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                RACLog.w("QHexRT probe failed; treating NPU backend as unavailable")
                false
            }
        }
        publish {
            it[InferenceFramework.INFERENCE_FRAMEWORK_QHEXRT] = qhexrtSupported
        }
    }

    /**
     * Bootstrap hook: forward the outcome of a native backend registration the
     * app module cannot otherwise observe. `ok = false` marks the backend's rows
     * unavailable; a later `ok = true` re-enables them.
     */
    fun reportRegistration(framework: InferenceFramework, ok: Boolean) {
        publish { it[framework] = ok }
    }

    private fun publish(mutate: (MutableMap<InferenceFramework, Boolean>) -> Unit) {
        val next = mutableState.value.available.toMutableMap()
        mutate(next)
        mutableState.value = Snapshot(next.toMap())
    }

    /** Immutable availability view keyed by framework. */
    data class Snapshot(
        val available: Map<InferenceFramework, Boolean> =
            defaultAvailable.associateWith { true },
    )
}
