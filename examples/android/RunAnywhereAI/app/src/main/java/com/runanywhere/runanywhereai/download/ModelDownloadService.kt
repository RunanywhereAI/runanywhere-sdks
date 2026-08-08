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
import android.os.SystemClock
import androidx.compose.ui.graphics.toArgb
import androidx.core.app.NotificationCompat
import androidx.core.app.ServiceCompat
import androidx.core.content.ContextCompat
import com.runanywhere.runanywhereai.MainActivity
import com.runanywhere.runanywhereai.ui.screens.models.RuntimeModelSelection
import com.runanywhere.runanywhereai.ui.screens.models.displayTitle
import com.runanywhere.runanywhereai.ui.theme.BrandOrange
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
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicLong
import kotlin.coroutines.cancellation.CancellationException

/**
 * Foreground service that owns a model download so it survives the app being backgrounded and the
 * screen turning off.
 *
 * Without a started foreground service + wake lock, Doze suspends the collecting coroutine the
 * moment the screen sleeps mid-download, stalling multi-GB NPU bundles indefinitely. This service:
 *  - runs `RunAnywhere.models.download(...)` in its **own** scope (not a ViewModel/Activity scope
 *    that dies with the UI),
 *  - holds a `PARTIAL_WAKE_LOCK` so the CPU keeps servicing the socket in Doze,
 *  - shows a progress notification carrying the same size/rate/ETA line the picker row does, and
 *  - publishes the transfer on [active] / [interrupted] so every picker mirrors it.
 *
 * Cancellation cancels the collecting job; the SDK's `downloadModel` `finally` block then fires the
 * native cancel with `delete_partial_bytes = false`, so resume bytes are preserved for a later
 * retry — a re-issued download continues from the `.part` sidecar rather than starting over.
 */
class ModelDownloadService : Service() {

    // Service-owned scope: independent of any Activity/ViewModel lifecycle.
    private val serviceScope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    private var wakeLock: PowerManager.WakeLock? = null
    private var wakeLockRefreshedAt = 0L

    private var lastNotifiedAt = 0L
    private var lastNotifiedPhase: DownloadPhase? = null

    /** How a transfer ended, from this service's point of view. */
    private sealed interface Outcome {
        /** Every byte is on disk and the model is registered. */
        data object Finished : Outcome

        /** It stopped short; [record] is what the picker rows will say about it. */
        data class Stopped(val record: Interrupted) : Outcome
    }

    override fun onBind(intent: Intent?): IBinder? = null

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        if (intent?.action == ACTION_CANCEL) return handleCancelIntent()

        val modelId = intent?.getStringExtra(EXTRA_MODEL_ID)
        val model = modelId?.let { pending.remove(it) }
        if (model == null) {
            // A duplicate delivery whose queued model an earlier delivery already consumed — two
            // taps on Get landing before the row could repaint. Tearing the service down here
            // would kill the transfer the first tap started, so a live job is re-posted and kept;
            // only a delivery that finds nothing running has anything to stop.
            val running = activeModel
            if (downloadJob?.isActive == true && running != null) {
                startAsForeground(running)
            } else {
                startForegroundGeneric()
                stopSelfSafely()
            }
            return START_NOT_STICKY
        }

        // startForeground can be rejected on Android 12+ when the app is not in an
        // eligible state. Fail gracefully (mark the download failed) instead of
        // crashing; the picker then surfaces a normal error and the user can retry.
        if (!startAsForeground(model)) {
            recordInterruption(
                model.id,
                Interrupted(cancelled = false, message = "Could not start the background download"),
            )
            _active.value = null
            stopSelfSafely()
            return START_NOT_STICKY
        }
        acquireWakeLock()

        // Drive a single job + notification here. The picker enforces one active download at a time
        // (the busy row hides the download action), but prepare() and rapid re-taps can still hand
        // us a new target while one is in flight — preempt the prior job so we never leak a second
        // runDownload coroutine racing on the published state. Cancel unwinds the SDK stream, which
        // preserves resume bytes. The generation stamp is what stops the preempted job's own
        // teardown from stopping the service out from under its replacement.
        val generation = generations.incrementAndGet()
        activeModel = model
        downloadJob?.cancel()
        downloadJob = serviceScope.launch {
            runDownload(model, generation)
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

    private suspend fun runDownload(model: RAModelInfo, generation: Long) {
        // Starting again makes the last report obsolete. Leaving "download paused" sitting in the
        // shade beneath a live progress bar tells the user two different things about one model.
        getSystemService(NotificationManager::class.java)?.cancel(OUTCOME_NOTIFICATION_ID)
        publish(generation, Active(model.id, DownloadProgressInfo()))
        var latest = DownloadProgressInfo()
        // Defensive default: the SDK ends every stream in Completed or Failed, so this is only
        // reached if that contract ever changes. It errs toward "stopped, bytes kept", which
        // offers a resume — the safe wrong answer, where claiming success is the unsafe one.
        var outcome: Outcome = Outcome.Stopped(
            Interrupted(cancelled = true, message = "The download ended before the model was complete"),
        )
        try {
            // Resident STT/LLM weights hold multi-GB of MemAvailable and trip the
            // download RAM preflight on mid-range phones. Free them first; the
            // user can re-select after the transfer finishes.
            freeResidentModelsForDownload()
            RunAnywhere.models.download(model.id).collect { event ->
                when (val update = DownloadProgressInfo.advance(latest, event)) {
                    is DownloadUpdate.Advanced -> {
                        latest = update.info
                        publish(generation, Active(model.id, update.info))
                        updateNotification(model, update.info)
                    }
                    DownloadUpdate.Finished -> outcome = Outcome.Finished
                    // A failure is a terminal *event*, not an exception: the stream ends normally
                    // right after it. Treating the end of the stream as success is how a failed
                    // download used to announce itself as ready.
                    is DownloadUpdate.Stopped -> outcome = Outcome.Stopped(
                        Interrupted(update.cancelled, update.message, latest.takeIf { it.bytesDone > 0 }),
                    )
                    DownloadUpdate.Ignored -> Unit
                }
            }
            // Inside the try, and before the finally stops the service: settling first is what
            // guarantees onDestroy never finds a live-looking transfer to invent an outcome for.
            settle(generation, model, outcome)
        } catch (e: CancellationException) {
            // Cancellation is a user action (or teardown); the SDK preserves
            // resume bytes. Surface it as a terminal "paused" state.
            settle(
                generation,
                model,
                Outcome.Stopped(Interrupted(cancelled = true, message = null, progress = latest.takeIf { it.bytesDone > 0 })),
            )
            throw e
        } catch (e: Exception) {
            RACLog.e("foreground download failed: ${model.id}", e)
            settle(
                generation,
                model,
                Outcome.Stopped(
                    Interrupted(false, e.message ?: "Download failed", latest.takeIf { it.bytesDone > 0 }),
                ),
            )
        } finally {
            // Only the transfer that still owns the service may stop it. A preempted job reaches
            // here while its replacement is starting, and an unguarded stopSelf() there would take
            // the new download down with it.
            if (generation == generations.get()) stopSelfSafely()
        }
    }

    /** Publish live progress, unless a newer transfer has already taken the state over. */
    private fun publish(generation: Long, snapshot: Active) {
        if (generation != generations.get()) return
        _active.value = snapshot
    }

    /**
     * Publish the end of a transfer, and tell the user about it if they are not looking at the app.
     *
     * `STOP_FOREGROUND_REMOVE` takes the progress notification down with the service, so without an
     * outcome notification a download that finished — or failed — during a phone call simply
     * vanishes, and the only way to learn what happened is to reopen the app and read a row.
     */
    private fun settle(generation: Long, model: RAModelInfo, outcome: Outcome) {
        val name = model.displayTitle()
        // Clearing the live snapshot is the one part a preempted job must not do — its replacement
        // already owns that field. The per-model record and the report are keyed to *this* model, so
        // they are still this job's to write: a transfer that was pushed aside by another still left
        // bytes on disk, and the row for it has to say so.
        val ownsLiveState = generation == generations.get()
        when (outcome) {
            Outcome.Finished -> {
                _interrupted.update { it - model.id }
                if (ownsLiveState) _active.value = null
                postOutcome("$name is ready", "Downloaded and available on this device.")
            }
            is Outcome.Stopped -> {
                recordInterruption(model.id, outcome.record)
                if (ownsLiveState) _active.value = null
                if (outcome.record.cancelled) {
                    postOutcome(
                        "$name download paused",
                        "The bytes already transferred are kept — resume picks up where it stopped.",
                    )
                } else {
                    val why = outcome.record.message?.takeIf { it.isNotBlank() }?.let { "${it.asSentence()}. " }
                    postOutcome("$name download failed", "${why.orEmpty()}Retry resumes from the bytes already on disk.")
                }
            }
        }
    }

    private fun recordInterruption(modelId: String, record: Interrupted) {
        _interrupted.update { it + (modelId to record) }
    }

    private suspend fun freeResidentModelsForDownload() {
        if (!RuntimeModelSelection.unloadAllForDownload()) {
            RACLog.w("pre-download unload skipped; keeping prior model selections")
        }
    }

    private fun startAsForeground(model: RAModelInfo): Boolean {
        ensureChannel(this)
        val notification = buildNotification(model, _active.value?.progress ?: DownloadProgressInfo())
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
            .setColor(BrandOrange.toArgb())
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

    /**
     * Re-post the progress notification, at most once a second.
     *
     * The SDK polls progress at 4 Hz. Re-posting that often is not just wasted binder traffic: it
     * pushes the app over `NotificationManagerService`'s per-package enqueue-rate limit, which then
     * *sheds* whichever notification arrives next — and the one that arrives next is the settled
     * outcome, the single notification the user actually needs. A phase change always posts, so
     * "Checking the download…" is never a second late.
     *
     * The wake lock is refreshed on the same beat: bound so a wedged transfer cannot pin the CPU
     * forever, extended while bytes are genuinely moving so a slow multi-gigabyte bundle is never
     * cut off part-way through.
     */
    private fun updateNotification(model: RAModelInfo, progress: DownloadProgressInfo) {
        val now = SystemClock.elapsedRealtime()
        if (progress.phase == lastNotifiedPhase && now - lastNotifiedAt < NOTIFICATION_INTERVAL_MS) return
        lastNotifiedAt = now
        lastNotifiedPhase = progress.phase
        if (now - wakeLockRefreshedAt >= WAKE_LOCK_REFRESH_MS) acquireWakeLock()
        val manager = getSystemService(NotificationManager::class.java) ?: return
        manager.notify(NOTIFICATION_ID, buildNotification(model, progress))
    }

    /**
     * The notification is the only view of the transfer once the app is backgrounded, which is the
     * normal case for a multi-gigabyte model, so it carries the same detail line the picker row does
     * — size, rate, and time remaining — rather than a bare percentage. The title is the same short
     * name the picker shows, not the raw catalog id, so the two surfaces name one thing once.
     *
     * It also carries both of the things a user wants from that surface: tapping it returns to the
     * app, and Cancel stops the transfer without one. A progress notification with no way to act on
     * it makes the background download feel like something happening *to* the user.
     */
    private fun buildNotification(model: RAModelInfo, progress: DownloadProgressInfo): Notification =
        NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle("Downloading ${model.displayTitle()}")
            .setContentText(progress.detailLine.ifBlank { "Starting…" })
            .setSmallIcon(android.R.drawable.stat_sys_download)
            .setColor(BrandOrange.toArgb())
            .setContentIntent(openAppIntent())
            .setOngoing(true)
            .setProgress(100, progress.percent ?: 0, progress.isIndeterminate)
            .setPriority(NotificationCompat.PRIORITY_LOW)
            .setOnlyAlertOnce(true)
            .setForegroundServiceBehavior(NotificationCompat.FOREGROUND_SERVICE_IMMEDIATE)
            .addAction(android.R.drawable.ic_menu_close_clear_cancel, "Cancel", cancelIntent())
            .build()

    /**
     * What the user sees when the transfer settles while they are elsewhere. Posted under its own
     * id so it outlives the ongoing notification — which is torn down with the foreground service —
     * and dismissible, because it is a report rather than a running task.
     */
    private fun postOutcome(title: String, body: String) {
        val manager = getSystemService(NotificationManager::class.java) ?: return
        val notification = NotificationCompat.Builder(this, CHANNEL_ID)
            .setContentTitle(title)
            .setContentText(body)
            .setStyle(NotificationCompat.BigTextStyle().bigText(body))
            .setSmallIcon(android.R.drawable.stat_sys_download_done)
            .setColor(BrandOrange.toArgb())
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
        val pm = getSystemService(PowerManager::class.java) ?: return
        val lock = wakeLock ?: pm.newWakeLock(PowerManager.PARTIAL_WAKE_LOCK, WAKE_LOCK_TAG).also {
            it.setReferenceCounted(false)
            wakeLock = it
        }
        // Re-acquiring a non-reference-counted lock re-arms its timeout, so a transfer that keeps
        // reporting bytes keeps the CPU, while one that wedges releases on its own.
        lock.acquire(WAKE_LOCK_TIMEOUT_MS)
        wakeLockRefreshedAt = SystemClock.elapsedRealtime()
    }

    private fun releaseWakeLock() {
        wakeLock?.let { if (it.isHeld) it.release() }
        wakeLock = null
    }

    private fun stopSelfSafely() {
        releaseWakeLock()
        activeModel = null
        ServiceCompat.stopForeground(this, ServiceCompat.STOP_FOREGROUND_REMOVE)
        stopSelf()
    }

    override fun onDestroy() {
        releaseWakeLock()
        serviceScope.cancel()
        // The system can stop this service without the download coroutine ever reaching its own
        // terminal branch. Leaving `active` set would strand every picker row on a progress bar
        // that has quietly stopped moving — the frozen "12.6 MB/s · 49s left" that outlives the
        // transfer. Settle it here so a stopped download always looks stopped.
        _active.value?.let { snapshot ->
            recordInterruption(
                snapshot.modelId,
                Interrupted(cancelled = true, message = null, progress = snapshot.progress.takeIf { it.bytesDone > 0 }),
            )
            _active.value = null
        }
        super.onDestroy()
    }

    /** The transfer running right now. */
    data class Active(
        val modelId: String,
        val progress: DownloadProgressInfo,
    )

    /**
     * A transfer that stopped with the model still incomplete, remembered for as long as the process
     * lives so the row offering to continue it survives the picker being closed and reopened.
     *
     * [progress] is the last frame seen, so the row can say how much is already banked rather than
     * making a half-finished multi-gigabyte download look like a fresh one.
     */
    data class Interrupted(
        val cancelled: Boolean,
        val message: String? = null,
        val progress: DownloadProgressInfo? = null,
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

        /** Bound on a *silent* transfer. Progress re-arms it, so this only expires on a wedge. */
        private const val WAKE_LOCK_TIMEOUT_MS = 15L * 60L * 1000L
        private const val WAKE_LOCK_REFRESH_MS = 5L * 60L * 1000L

        /** Well inside NotificationManager's per-package enqueue-rate limit (~5/s). */
        private const val NOTIFICATION_INTERVAL_MS = 1_000L

        // Held in-process so the full RAModelInfo (a Wire proto) need not ride
        // through the Intent; the Intent only carries the id as the handoff key.
        private val pending = ConcurrentHashMap<String, RAModelInfo>()

        private val _active = MutableStateFlow<Active?>(null)

        /** The transfer running right now, or null when nothing is downloading. */
        val active: StateFlow<Active?> = _active

        private val _interrupted = MutableStateFlow<Map<String, Interrupted>>(emptyMap())

        /**
         * Downloads that stopped short, by model id.
         *
         * Process-wide rather than per-ViewModel because "there are bytes on disk to continue from"
         * is a fact about the device, not about one open sheet: a picker that was closed and
         * reopened used to offer a plain "Get" over half a gigabyte it had already fetched.
         */
        val interrupted: StateFlow<Map<String, Interrupted>> = _interrupted

        @Volatile
        private var downloadJob: Job? = null

        /** The model [downloadJob] is transferring, for deliveries that arrive without one. */
        @Volatile
        private var activeModel: RAModelInfo? = null

        /** Bumped per accepted start, so a preempted job can tell it no longer owns the service. */
        private val generations = AtomicLong(0)

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
                // Publish synchronously so a picker reads "downloading" on the same frame as the
                // tap, rather than whenever the service's IO coroutine happens to be scheduled.
                _interrupted.update { it - model.id }
                _active.value = Active(model.id, DownloadProgressInfo())
                true
            } catch (e: Exception) {
                // e.g. ForegroundServiceStartNotAllowedException from background.
                RACLog.w("foreground download service start rejected: ${model.id}", e)
                pending.remove(model.id)
                false
            }
        }

        /**
         * Cancel the in-flight download of [modelId]. Cancels the collecting job; the SDK's
         * `finally` fires the native cancel preserving resume bytes.
         *
         * A no-op when [modelId] is not the transfer actually running — otherwise cancelling a row
         * that had already settled would stop somebody else's download.
         */
        suspend fun cancel(modelId: String) {
            pending.remove(modelId)
            if (_active.value?.modelId != modelId) return
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

        /**
         * Suspend until [modelId] is no longer the running transfer.
         *
         * For the flows that stage a model before using it (the Voice AI pipeline card), which need
         * the same wake-lock/foreground guarantees as a picker download but cannot continue until
         * the bytes are there.
         */
        suspend fun awaitFinish(modelId: String) {
            active.first { it?.modelId != modelId }
        }

        /**
         * Forget that [modelId] was ever interrupted — it is on disk now, or its files were deleted,
         * so a row offering to resume it would be describing something that no longer exists.
         */
        fun forget(modelId: String) {
            _interrupted.update { it - modelId }
        }

        /**
         * Record a transfer that stopped short outside this service.
         *
         * The picker falls back to downloading in its own scope when the foreground service cannot
         * be started, and that path has to land in the same place — a resume offer must not depend
         * on which of the two ran, or the row would say "Get" over half a gigabyte on disk purely
         * because the app happened to be in the background when the transfer began.
         */
        fun noteInterrupted(
            modelId: String,
            cancelled: Boolean,
            message: String? = null,
            progress: DownloadProgressInfo? = null,
        ) {
            _interrupted.update { it + (modelId to Interrupted(cancelled, message, progress)) }
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
