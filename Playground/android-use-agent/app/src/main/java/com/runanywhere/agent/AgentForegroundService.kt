package com.runanywhere.agent

import android.app.Notification
import android.app.NotificationChannel
import android.app.NotificationManager
import android.app.Service
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.IBinder
import android.os.PowerManager
import android.util.Log

/**
 * Foreground service to keep the agent process alive while it controls other apps.
 *
 * Android aggressively freezes/kills background processes (Samsung FreecessHandler, etc.).
 * Without a foreground service + WakeLock, the agent's coroutine loop stops or CPU is
 * throttled as soon as the user switches away from the agent app to the target app.
 *
 * The PARTIAL_WAKE_LOCK keeps the CPU running at full speed even when the app is
 * in background — critical for on-device LLM inference performance.
 */
class AgentForegroundService : Service() {

    companion object {
        private const val TAG = "AgentForegroundService"
        private const val CHANNEL_ID = "agent_running_channel"
        private const val NOTIFICATION_ID = 1001
        private const val WAKE_LOCK_TAG = "RunAnywhereAgent::AgentInference"

        fun start(context: Context) {
            val intent = Intent(context, AgentForegroundService::class.java)
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
                context.startForegroundService(intent)
            } else {
                context.startService(intent)
            }
        }

        fun stop(context: Context) {
            context.stopService(Intent(context, AgentForegroundService::class.java))
        }
    }

    private var wakeLock: PowerManager.WakeLock? = null

    override fun onCreate() {
        super.onCreate()
        createNotificationChannel()
    }

    override fun onStartCommand(intent: Intent?, flags: Int, startId: Int): Int {
        val notification = buildNotification()
        startForeground(NOTIFICATION_ID, notification)
        acquireWakeLock()
        return START_STICKY
    }

    override fun onDestroy() {
        releaseWakeLock()
        super.onDestroy()
    }

    override fun onBind(intent: Intent?): IBinder? = null

    private fun acquireWakeLock() {
        if (wakeLock == null) {
            val powerManager = getSystemService(Context.POWER_SERVICE) as PowerManager
            wakeLock = powerManager.newWakeLock(
                PowerManager.PARTIAL_WAKE_LOCK,
                WAKE_LOCK_TAG
            ).apply {
                // 15 minutes max — matches MAX_DURATION_MS in AgentKernel (10 min) with buffer
                acquire(15 * 60 * 1000L)
            }
            Log.i(TAG, "WakeLock acquired for agent inference")
        }
    }

    private fun releaseWakeLock() {
        wakeLock?.let {
            if (it.isHeld) {
                it.release()
                Log.i(TAG, "WakeLock released")
            }
        }
        wakeLock = null
    }

    private fun createNotificationChannel() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            val channel = NotificationChannel(
                CHANNEL_ID,
                "Agent Running",
                NotificationManager.IMPORTANCE_LOW
            ).apply {
                description = "Keeps the agent alive while controlling other apps"
                setShowBadge(false)
            }
            val manager = getSystemService(NotificationManager::class.java)
            manager.createNotificationChannel(channel)
        }
    }

    private fun buildNotification(): Notification {
        val builder = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.O) {
            Notification.Builder(this, CHANNEL_ID)
        } else {
            @Suppress("DEPRECATION")
            Notification.Builder(this)
        }
        return builder
            .setContentTitle("RunAnywhere Agent")
            .setContentText("Agent is running...")
            .setSmallIcon(android.R.drawable.ic_dialog_info)
            .setOngoing(true)
            .build()
    }
}
