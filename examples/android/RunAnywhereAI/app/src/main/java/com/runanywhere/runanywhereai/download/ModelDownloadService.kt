package com.runanywhere.runanywhereai.download

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.PendingIntent
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
import com.runanywhere.runanywhereai.MainActivity
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.util.RACLog
import com.runanywhere.sdk.public.RunAnywhere
import com.runanywhere.sdk.public.api.models
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
        if (intent?.action == ACTION_CANCEL) return handleCancelIntent()

        val modelId = intent?.getStringExtra(EXTRA_MODEL_ID)
        val model = modelId?.let { pending.remove(it) }
        if (model == null) {
            // A redelivered/duplicate intent whose queued model was already consumed.
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

        // Drive a single job + notification here. The picker enforces one active
        // download at a time (the busy row hides the download action), but prepare()
        // and rapid re-taps can still hand us a new target while one is in flight —
        // preempt the prior job so we never leak a second runDownload coroutine
        // racing on _state. Cancel unwinds the SDK stream, which preserves resume bytes.
        downloadJob?.cancel()
        downloadJob = serviceScope.launch {
            runDownload(model)
        }
        return START_NOT_STICKY
    }

    /**
     * The notification's Cancel button.
     *
     * Once the app is in the background the notification is the only surface the transfer has, so
     * Cancel has to work from there or a user who changed their mind has to come back into the app
     * to stop several gigabytes of traffic. Delivered as a foreground-service start (the transfer
     * may be the only thing keeping the process alive), which obligates a `startForeground()` call
     * even on the path where there is nothing left to cancel.
     */
    private fun handleCancelIntent(): Int {
        val job = downloadJob
        if (job == null || !job.isActive) {
            // The transfer settled between the tap and this delivery.
            startForegroundGeneric("Finishing up")
            stopSelfSafely()
            return START_NOT_STICKY
        }
        // Unwinding the SDK stream is not instant, so the notification says what is happening
        // instead of leaving a progress bar that has visibly stopped moving. This also re-posts
        // the foreground notification, discharging the start obligation on this delivery.
        startForegroundGeneric("Cancelling download")
        // The SDK's `finally` fires the native cancel with delete_partial_bytes = false — the
        // bytes already on disk survive for a later resume.
        serviceScope.launch { job.cancelAndJoin() }
        return START_NOT_STICKY
    }

    private suspend fun runDownload(model: RAModelInfo) {
        _state.value = Download(model.id, progress = DownloadProgressInfo(), status = Status.RUNNING)
        try {
            // Resident STT/LLM weights hold multi-GB of MemAvailable and trip the
            // download RAM preflight on mid-range phones. Free them first; the
            // user can re-select after the transfer finishes.
            freeResidentModelsForDownload()
            var latest = DownloadProgressInfo()
            RunAnywhere.models.download(model.id).collect { event ->
                val info = DownloadProgressInfo.advance(latest, event) ?: return@collect
                latest = info
                _state.value = Download(model.id, progress = info, status = Status.RUNNING)
                updateNotification(model, info)
            }
            _state.value = Download(
                model.id,
                progress = DownloadProgressInfo(fraction = 1f),
                status = Status.COMPLETED,
            )
            postOutcome(
                title = "${model.name} is ready",
                body = "Downloaded and available on this device.",
            )
        } catch (e: CancellationException) {
            // Cancellation is a user action (or teardown); the SDK preserves
            // resume bytes. Surface it as a terminal "cancelled" state.
            _state.value = Download(model.id, status = Status.CANCELLED)
            postOutcome(
                title = "${model.name} download paused",
                body = "The bytes already transferred are kept — resume picks up where it stopped.",
            )
            throw e
        } catch (e: Exception) {
            RACLog.e("foreground download failed: ${model.id}", e)
            _state.value = Download(model.id, status = Status.FAILED, error = e.message ?: "Download failed")
            postOutcome(
                title = "${model.name} download failed",
                body = "Retry resumes from the bytes already on disk.",
            )
        } finally {
            stopSelfSafely()
        }
    }

    private suspend fun freeResidentModelsForDownload() {
        if (!RuntimeModelSelection.unloadAllForDownload()) {
            RACLog.w("pre-download unload skipped; keeping prior model selections")
        }
    }

    private fun startAsForeground(model: RAModelInfo): Boolean {
        ensureChannel(this)
        val notification = buildNotification(model, DownloadProgressInfo())
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

    /**
     * Minimal startForeground for the deliveries that carry no model of their own — a duplicate
     * intent, or the Cancel action. Every `startForegroundService()` obligates a `startForeground()`
     * within ~5s or Android raises `ForegroundServiceDidNotStartInTimeException` (a hard crash), so
     * these paths still have to post something; [title] keeps it honest about which one it is.
     */
    private fun startForegroundGeneric(title: String = "Preparing download") {
        ensureChannel(this)
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(openAppIntent())
            .setProgress(0, 0, true)
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

    private fun updateNotification(model: RAModelInfo, progress: DownloadProgressInfo) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildNotification(model, progress))
    }

    /**
     * The notification is the only view of the transfer once the app is backgrounded, which is the
     * normal case for a multi-gigabyte model, so it carries the same detail line the picker row does
     * — size, rate, and time remaining — rather than a bare percentage.
     *
     * It also carries both of the things a user wants from that surface: tapping it returns to the
     * app, and Cancel stops the transfer without one. A progress notification with no way to act on
     * it makes the background download feel like something happening *to* the user.
     */
    private fun buildNotification(model: RAModelInfo, progress: DownloadProgressInfo): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Downloading ${model.name}")
            .setContentText(progress.detailLine.ifBlank { "Starting…" })
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setProgress(100, progress.percent ?: 0, progress.isIndeterminate)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelIntent())
            .build()

    /**
     * What the user sees when the transfer settles while they are elsewhere.
     *
     * `STOP_FOREGROUND_REMOVE` takes the progress notification down with the service, so without
     * this a download that finished — or failed — during a phone call simply vanishes, and the only
     * way to learn the outcome is to reopen the app and read a row. Posted under its own id so it
     * outlives the ongoing one, and dismissible because it is a report, not a running task.
     */
    private fun postOutcome(title: String, body: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setContentIntent(openAppIntent())
            .setAutoCancel(true)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .build()
        manager.notify(OUTCOME_NOTIFICATION_ID, notification)
    }

    /** Tapping either notification brings the app back to the front rather than doing nothing. */
    private fun openAppIntent(): PendingIntent =
        PendingIntent.getActivity(
            this,
            0,
            Intent(this, MainActivity::class.java).apply {
                flags = Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TOP
            },
            PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
        )

    /**
     * No model id rides along: the service runs exactly one transfer at a time (a second start
     * preempts the first), so "the active download" is unambiguous and an id here could only ever
     * name a job that is already gone.
     */
    private fun cancelIntent(): PendingIntent {
        val intent = Intent(this, ModelDownloadService::class.java).apply { action = ACTION_CANCEL }
        // getForegroundService, not getService: the download may be the only thing keeping the
        // process alive, and a plain service start from the background would be refused.
        return if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            PendingIntent.getForegroundService(
                this,
                CANCEL_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        } else {
            PendingIntent.getService(
                this,
                CANCEL_REQUEST_CODE,
                intent,
                PendingIntent.FLAG_UPDATE_CURRENT or PendingIntent.FLAG_IMMUTABLE,
            )
        }
    }

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
        val progress: DownloadProgressInfo? = null,
        val status: Status,
        val error: String? = null,
    )

    companion object {
        private const val CHANNEL_ID = "model_downloads"
        private const val NOTIFICATION_ID = 4801

        /**
         * The settled-outcome notification. A separate id on purpose: the ongoing one is torn down
         * with the foreground service, so reusing that id would post a report that is immediately
         * removed.
         */
        private const val OUTCOME_NOTIFICATION_ID = 4802
        private const val CANCEL_REQUEST_CODE = 1
        private const val ACTION_CANCEL = "com.runanywhere.runanywhereai.action.CANCEL_DOWNLOAD"
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
                _state.value = Download(model.id, progress = DownloadProgressInfo(), status = Status.RUNNING)
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
