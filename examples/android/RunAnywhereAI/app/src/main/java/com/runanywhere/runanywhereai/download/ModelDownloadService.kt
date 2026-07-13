package com.runanywhere.runanywhereai.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.ContentProvider
import android.content.ContentValues
import android.content.Context
import android.content.Intent
import android.content.pm.ServiceInfo
import android.database.Cursor
import android.net.Uri
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.extensions.downloadModelStream
import com.runanywhere.sdk.public.types.RAModelInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import kotlin.coroutines.cancellation.CancellationException

/**
 * Foreground service that owns a model download so it survives the screen
 * turning off.
 *
 * Without a started foreground service + wake lock, Doze suspends the collecting
 * coroutine the moment the screen sleeps mid-download, stalling multi-GB NPU
 * bundles indefinitely. This service:
 *  - runs `RunAnywhere.downloadModelStream(...)` in its **own** scope (not a
 *    ViewModel/Activity scope that dies with the UI),
 *  - holds a `PARTIAL_WAKE_LOCK` so the CPU keeps servicing the socket in Doze,
 *  - shows a progress notification (required for a foreground service), and
 *  - publishes progress on [state] so the picker mirrors it into its own row.
 *
 * Cancellation cancels the collecting job; the SDK's `downloadModel` `finally`
 * block then fires the native cancel with `delete_partial_bytes = false`, so
 * resume bytes are preserved for a later retry.
 */
class ModelDownloadService : Service() {

    // Service-owned scope: independent of any Activity/ViewModel lifecycle.
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val modelId = intent?.getStringExtra(EXTRA_MODEL_ID)
        val model = modelId?.let { pending.remove(it) }
        if (model == null) {
            // A startForegroundService() call obligates startForeground() within ~5s even when the
            // queued model was already consumed (a redelivered/duplicate intent). Satisfy the
            // contract with a minimal notification, then stop — otherwise Android raises
            // ForegroundServiceDidNotStartInTimeException (a hard crash).
            startForegroundGeneric()
            stopSelfSafely()
            return START_NOT_STICKY
        }

        // startForeground can be rejected on Android 12+ when the app is not in an
        // eligible state. Fail gracefully (mark the download failed) instead of
        // crashing; the picker then surfaces a normal error and the user can retry.
        if (!startAsForeground(model)) {
            _state.value = Download(model.id, status = Status.FAILED, error = "Could not start background download")
            stopSelfSafely()
            return START_NOT_STICKY
        }
        acquireWakeLock()

        // The picker enforces one active download at a time (the busy row hides
        // the download action), so we drive a single job + notification here.
        downloadJob = serviceScope.launch {
            runDownload(model)
        }
        return START_NOT_STICKY
    }

    private suspend fun runDownload(model: RAModelInfo) {
        _state.value = Download(model.id, progressPercent = 0, status = Status.RUNNING)
        try {
            RunAnywhere.downloadModelStream(model).collect { p ->
                val pct = if (p.total_bytes > 0) {
                    (p.bytes_downloaded * 100 / p.total_bytes).toInt()
                } else {
                    (p.stage_progress.coerceIn(0f, 1f) * 100).toInt()
                }
                _state.value = Download(model.id, progressPercent = pct, status = Status.RUNNING)
                updateNotification(model, pct)
            }
            _state.value = Download(model.id, progressPercent = 100, status = Status.COMPLETED)
        } catch (e: CancellationException) {
            // Cancellation is a user action (or teardown); the SDK preserves
            // resume bytes. Surface it as a terminal "cancelled" state.
            _state.value = Download(model.id, status = Status.CANCELLED)
            throw e
        } catch (e: Exception) {
            RACLog.e("foreground download failed: ${model.id}", e)
            _state.value = Download(model.id, status = Status.FAILED, error = e.message ?: "Download failed")
        } finally {
            stopSelfSafely()
        }
    }

    private fun startAsForeground(model: RAModelInfo): Boolean {
        ensureChannel(this)
        val notification = buildNotification(model, progressPercent = 0)
        return try {
            // dataSync FGS type matches a network model download. On Android 14+
            // the type must be declared in the manifest and passed here.
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, 0)
            }
            true
        } catch (e: Exception) {
            RACLog.w("startForeground rejected for ${model.id}: ${e.message}")
            false
        }
    }

    /** Minimal startForeground to discharge the FGS obligation when there is no work to do. */
    private fun startForegroundGeneric() {
        ensureChannel(this)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Preparing download")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()
        try {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.Q) {
                ServiceCompat.startForeground(
                    this,
                    NOTIFICATION_ID,
                    notification,
                    ServiceInfo.FOREGROUND_SERVICE_TYPE_DATA_SYNC,
                )
            } else {
                ServiceCompat.startForeground(this, NOTIFICATION_ID, notification, 0)
            }
        } catch (e: Exception) {
            RACLog.w("startForeground (generic) rejected: ${e.message}")
        }
    }

    private fun updateNotification(model: RAModelInfo, progressPercent: Int) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildNotification(model, progressPercent))
    }

    private fun buildNotification(model: RAModelInfo, progressPercent: Int): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Downloading ${model.name}")
            .setContentText("$progressPercent%")
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setOngoing(true)
            .setProgress(100, progressPercent.coerceIn(0, 100), progressPercent <= 0)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .build()

    private fun acquireWakeLock() {
        if (wakeLock?.isHeld == true) return
        val pm = getSystemService(PowerManager::class.java) ?: return
        wakeLock = pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).apply {
            setReferenceCounted(false)
            // Bound the hold so a wedged download can never pin the CPU forever.
            acquire(WAKE_LOCK_TIMEOUT_MS)
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun stopSelfSafely() {
        releaseWakeLock()
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        releaseWakeLock()
        serviceScope.cancel()
        super.onDestroy()
    }

    /** Terminal status of the active/last download for the observing picker. */
    enum class Status { RUNNING, COMPLETED, CANCELLED, FAILED }

    /** Snapshot the picker mirrors into its own row state. */
    data class Download(
        val modelId: String,
        val progressPercent: Int? = null,
        val status: Status,
        val error: String? = null,
    )

    companion object {
        private const val CHANNEL_ID = "model_downloads"
        private const val NOTIFICATION_ID = 4801
        private const val EXTRA_MODEL_ID = "model_id"
        private const val WAKE_LOCK_TAG = "RunAnywhere:ModelDownload"
        // Downloads of multi-GB bundles are slow but finite; cap the wake lock so
        // a stuck job self-releases rather than draining the battery.
        private const val WAKE_LOCK_TIMEOUT_MS = 60L * 60L * 1000L // 1 hour

        // Held in-process so the full RAModelInfo (a Wire proto) need not ride
        // through the Intent; the Intent only carries the id as the handoff key.
        private val pending = ConcurrentHashMap<String, RAModelInfo>()

        private val _state = MutableStateFlow<Download?>(null)

        /** Progress/terminal state of the foreground download, or null when idle. */
        val state: StateFlow<Download?> = _state

        @Volatile
        private var downloadJob: Job? = null

        // Captured application Context (see [ContextInitializer]) so the picker
        // ViewModel — which has no Context — can start this service.
        @Volatile
        private var appContext: Context? = null

        /**
         * Start (or replace) the foreground download for [model]. No-op if the
         * app Context was never captured (should not happen once the manifest
         * initializer runs) — the caller then falls back to an in-VM download.
         *
         * @return true when the service was asked to start.
         */
        fun start(model: RAModelInfo): Boolean {
            val ctx = appContext ?: return false
            pending[model.id] = model
            val intent = Intent(ctx, ModelDownloadService::class.java).apply {
                putExtra(EXTRA_MODEL_ID, model.id)
            }
            return try {
                ContextCompat.startForegroundService(ctx, intent)
                // Publish RUNNING synchronously so an observer that subscribes
                // before the service's IO coroutine runs never reads a stale
                // terminal snapshot from a prior download of the same model.
                _state.value = Download(model.id, progressPercent = 0, status = Status.RUNNING)
                true
            } catch (e: Exception) {
                // e.g. ForegroundServiceStartNotAllowedException from background.
                RACLog.w("foreground download service start rejected: ${model.id}", e)
                pending.remove(model.id)
                false
            }
        }

        /**
         * Cancel the in-flight download. Cancels the collecting job; the SDK's
         * `finally` fires the native cancel preserving resume bytes.
         */
        suspend fun cancel(modelId: String) {
            pending.remove(modelId)
            downloadJob?.let { job ->
                try {
                    job.cancelAndJoin()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    RACLog.w("download cancel join failed: $modelId", e)
                }
            }
        }

        /** Clear a terminal snapshot once the picker has consumed it. */
        fun clearIfTerminal(modelId: String) {
            val current = _state.value ?: return
            if (current.modelId == modelId && current.status != Status.RUNNING) {
                _state.value = null
            }
        }

        internal fun installContext(context: Context) {
            appContext = context.applicationContext
        }

        /**
         * Whether the app may post the download progress notification. A
         * `dataSync` foreground service still starts and runs when this is false
         * (Android just suppresses the notification), so this is only a hint for
         * the UI layer to request POST_NOTIFICATIONS on Android 13+ before a
         * download — the service itself degrades gracefully either way.
         */
        fun notificationsPermitted(context: Context): Boolean {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.TIRAMISU) return true
            return ContextCompat.checkSelfPermission(
                context,
                android.Manifest.permission.POST_NOTIFICATIONS,
            ) == android.content.pm.PackageManager.PERMISSION_GRANTED
        }

        private fun ensureChannel(context: Context) {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.O) return
            val manager = context.getSystemService(NotificationManager::class.java) ?: return
            if (manager.getNotificationChannel(CHANNEL_ID) != null) return
            manager.createNotificationChannel(
                NotificationChannel(
                    CHANNEL_ID,
                    "Model downloads",
                    NotificationManager.IMPORTANCE_LOW,
                ).apply {
                    description = "Progress for on-device model downloads"
                    setShowBadge(false)
                },
            )
        }
    }

    /**
     * Captures the application Context before [android.app.Application.onCreate]
     * via a zero-dependency [ContentProvider] (its `onCreate` fires first), so the
     * Context-less picker ViewModel can launch the download service without
     * threading a Context through every call site. Declared in the app manifest.
     *
     * Uses a plain ContentProvider rather than androidx.startup so no new compile
     * dependency is introduced. It performs no data operations.
     */
    class ContextInitializer : ContentProvider() {
        override fun onCreate(): Boolean {
            context?.let { ModelDownloadService.installContext(it) }
            return true
        }

        override fun query(
            uri: Uri,
            projection: Array<out String>?,
            selection: String?,
            selectionArgs: Array<out String>?,
            sortOrder: String?,
        ): Cursor? = null

        override fun getType(uri: Uri): String? = null

        override fun insert(uri: Uri, values: ContentValues?): Uri? = null

        override fun delete(uri: Uri, selection: String?, selectionArgs: Array<out String>?): Int = 0

        override fun update(
            uri: Uri,
            values: ContentValues?,
            selection: String?,
            selectionArgs: Array<out String>?,
        ): Int = 0
    }
}
