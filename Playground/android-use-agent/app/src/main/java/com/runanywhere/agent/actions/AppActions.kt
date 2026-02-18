package com.runanywhere.agent.actions

import android.content.ComponentName
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.AlarmClock
import android.util.Log

object AppActions {
    private const val TAG = "AppActions"

    // Package names for common apps (Google defaults + Samsung fallbacks)
    object Packages {
        const val YOUTUBE = "com.google.android.youtube"
        const val WHATSAPP = "com.whatsapp"
        const val CHROME = "com.android.chrome"
        const val GMAIL = "com.google.android.gm"
        const val PHONE = "com.google.android.dialer"
        const val PHONE_SAMSUNG = "com.samsung.android.dialer"
        const val MESSAGES = "com.google.android.apps.messaging"
        const val MESSAGES_SAMSUNG = "com.samsung.android.messaging"
        const val MAPS = "com.google.android.apps.maps"
        const val SPOTIFY = "com.spotify.music"
        const val CAMERA = "com.android.camera"
        const val CAMERA_SAMSUNG = "com.sec.android.app.camera"
        const val CLOCK = "com.google.android.deskclock"
        const val CLOCK_SAMSUNG = "com.sec.android.app.clockpackage"
        const val CALENDAR = "com.google.android.calendar"
        const val CALENDAR_SAMSUNG = "com.samsung.android.calendar"
        const val CONTACTS = "com.google.android.contacts"
        const val CONTACTS_SAMSUNG = "com.samsung.android.contacts"
        const val GALLERY_SAMSUNG = "com.sec.android.gallery3d"
        const val CALCULATOR = "com.google.android.calculator"
        const val CALCULATOR_SAMSUNG = "com.sec.android.app.popupcalculator"
        const val FILES = "com.google.android.apps.nbu.files"
        const val FILES_SAMSUNG = "com.sec.android.app.myfiles"
        const val INSTAGRAM = "com.instagram.android"
        const val TWITTER = "com.twitter.android"
        const val TELEGRAM = "org.telegram.messenger"
        const val NETFLIX = "com.netflix.mediaclient"
        const val NOTES_SAMSUNG = "com.samsung.android.app.notes"
        const val KEEP = "com.google.android.keep"
    }

    /** Package names that should never be opened by the agent */
    private val BLOCKED_PACKAGES = setOf(
        "com.samsung.android.bixby.agent",
        "com.samsung.android.bixby.service",
        "com.samsung.android.visionintelligence",
        "com.samsung.android.bixby.sidebar",
        "com.samsung.android.app.routines",
    )

    fun openYouTubeSearch(context: Context, query: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_SEARCH).apply {
                setPackage(Packages.YOUTUBE)
                putExtra("query", query)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open YouTube search: ${e.message}")
            // Fallback to web
            openYouTubeWeb(context, query)
        }
    }

    fun openYouTubeWeb(context: Context, query: String): Boolean {
        return try {
            val url = "https://www.youtube.com/results?search_query=${Uri.encode(query)}"
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open YouTube web: ${e.message}")
            false
        }
    }

    fun openWhatsAppChat(context: Context, phoneNumber: String): Boolean {
        return try {
            // Format phone number (remove spaces, dashes, etc.)
            val cleanNumber = phoneNumber.replace("[^0-9+]".toRegex(), "")
            val url = "https://wa.me/$cleanNumber"
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open WhatsApp chat: ${e.message}")
            false
        }
    }

    fun openWhatsApp(context: Context): Boolean {
        return openApp(context, Packages.WHATSAPP)
    }

    fun composeEmail(
        context: Context,
        to: String,
        subject: String? = null,
        body: String? = null
    ): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_SENDTO).apply {
                data = Uri.parse("mailto:$to")
                subject?.let { putExtra(Intent.EXTRA_SUBJECT, it) }
                body?.let { putExtra(Intent.EXTRA_TEXT, it) }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to compose email: ${e.message}")
            false
        }
    }

    fun dialNumber(context: Context, phoneNumber: String): Boolean {
        return try {
            val cleanNumber = phoneNumber.replace("[^0-9+*#]".toRegex(), "")
            val intent = Intent(Intent.ACTION_DIAL, Uri.parse("tel:$cleanNumber")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to dial number: ${e.message}")
            false
        }
    }

    fun callNumber(context: Context, phoneNumber: String): Boolean {
        return try {
            val cleanNumber = phoneNumber.replace("[^0-9+*#]".toRegex(), "")
            val intent = Intent(Intent.ACTION_CALL, Uri.parse("tel:$cleanNumber")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to call number: ${e.message}")
            false
        }
    }

    fun openMaps(context: Context, query: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("geo:0,0?q=${Uri.encode(query)}")).apply {
                setPackage(Packages.MAPS)
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open Maps: ${e.message}")
            // Fallback to web
            try {
                val webIntent = Intent(Intent.ACTION_VIEW, Uri.parse("https://www.google.com/maps/search/${Uri.encode(query)}")).apply {
                    addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
                }
                context.startActivity(webIntent)
                true
            } catch (e2: Exception) {
                false
            }
        }
    }

    fun openSpotifySearch(context: Context, query: String): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse("spotify:search:${Uri.encode(query)}")).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open Spotify: ${e.message}")
            false
        }
    }

    fun sendSMS(context: Context, phoneNumber: String, message: String? = null): Boolean {
        return try {
            val cleanNumber = phoneNumber.replace("[^0-9+]".toRegex(), "")
            val intent = Intent(Intent.ACTION_SENDTO, Uri.parse("smsto:$cleanNumber")).apply {
                message?.let { putExtra("sms_body", it) }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open SMS: ${e.message}")
            false
        }
    }

    fun openCamera(context: Context): Boolean {
        return try {
            val intent = Intent(android.provider.MediaStore.ACTION_IMAGE_CAPTURE).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open camera: ${e.message}")
            openApp(context, Packages.CAMERA)
        }
    }

    fun openClock(context: Context): Boolean {
        if (openApp(context, Packages.CLOCK)) return true
        val knownPackages = listOf("com.android.deskclock", "com.sec.android.app.clockpackage")
        if (knownPackages.any { openApp(context, it) }) return true

        return try {
            val intent = Intent(AlarmClock.ACTION_SHOW_TIMERS).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open clock: ${e.message}")
            false
        }
    }

    fun setTimer(context: Context, totalSeconds: Int, label: String? = null, skipUi: Boolean = false): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_TIMER).apply {
                putExtra(AlarmClock.EXTRA_LENGTH, totalSeconds)
                putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
                label?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it.take(30)) }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set timer: ${e.message}")
            openClock(context)
        }
    }

    /**
     * Open X (formerly Twitter) using explicit component intent.
     * getLaunchIntentForPackage fails for X because it has 20+ LAUNCHER activity-aliases
     * (subscription icon variants) that confuse the PackageManager resolver.
     */
    fun openX(context: Context): Boolean {
        return try {
            val intent = Intent(Intent.ACTION_MAIN).apply {
                addCategory(Intent.CATEGORY_LAUNCHER)
                component = ComponentName(Packages.TWITTER, "com.twitter.android.StartActivity")
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open X via StartActivity: ${e.message}")
            // Fallback to generic package launch
            openApp(context, Packages.TWITTER)
        }
    }

    /**
     * Open a notes app (Samsung Notes or Google Keep) and optionally create a new note.
     * Returns true if successfully launched.
     */
    fun openNotes(context: Context, text: String? = null): Boolean {
        // Try Samsung Notes first (on Samsung devices), then Google Keep
        if (openApp(context, Packages.NOTES_SAMSUNG)) return true
        if (openApp(context, Packages.KEEP)) return true

        // Fallback: use ACTION_SEND to any notes app
        return try {
            val intent = Intent(Intent.ACTION_SEND).apply {
                type = "text/plain"
                text?.let { putExtra(Intent.EXTRA_TEXT, it) }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open notes app: ${e.message}")
            false
        }
    }

    /**
     * Set an alarm at a specific hour/minute.
     */
    fun setAlarm(context: Context, hour: Int, minute: Int, label: String? = null, skipUi: Boolean = false): Boolean {
        return try {
            val intent = Intent(AlarmClock.ACTION_SET_ALARM).apply {
                putExtra(AlarmClock.EXTRA_HOUR, hour)
                putExtra(AlarmClock.EXTRA_MINUTES, minute)
                putExtra(AlarmClock.EXTRA_SKIP_UI, skipUi)
                label?.let { putExtra(AlarmClock.EXTRA_MESSAGE, it.take(30)) }
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to set alarm: ${e.message}")
            openClock(context)
        }
    }

    fun openApp(context: Context, packageName: String): Boolean {
        if (packageName in BLOCKED_PACKAGES) return false
        return try {
            val pm = context.packageManager
            val intent = pm.getLaunchIntentForPackage(packageName)
            intent?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            if (intent != null) {
                context.startActivity(intent)
                true
            } else {
                false
            }
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open app: ${e.message}")
            false
        }
    }

    /**
     * Try to open an app by name using fuzzy package/label matching.
     * Excludes Bixby and other Samsung system apps from results.
     */
    fun openAppByName(context: Context, appName: String): Boolean {
        val pm = context.packageManager
        val intent = Intent(Intent.ACTION_MAIN).apply {
            addCategory(Intent.CATEGORY_LAUNCHER)
        }
        val apps = pm.queryIntentActivities(intent, 0)
        val target = appName.lowercase().replace("[^a-z0-9]".toRegex(), "")

        // Filter out blocked packages and find best match
        val candidates = apps.filter { info ->
            info.activityInfo.packageName !in BLOCKED_PACKAGES &&
                !info.activityInfo.packageName.contains("bixby", ignoreCase = true)
        }

        // Try exact label match first
        val exactMatch = candidates.firstOrNull { info ->
            val label = info.loadLabel(pm)?.toString().orEmpty()
            label.equals(appName, ignoreCase = true)
        }

        // Then try contains match
        val containsMatch = exactMatch ?: candidates.firstOrNull { info ->
            val label = info.loadLabel(pm)?.toString().orEmpty()
            val labelNorm = label.lowercase().replace("[^a-z0-9]".toRegex(), "")
            val pkgNorm = info.activityInfo.packageName.lowercase().replace("[^a-z0-9]".toRegex(), "")
            labelNorm.contains(target) || target.contains(labelNorm) || pkgNorm.contains(target)
        }

        val match = containsMatch ?: return false

        val launch = pm.getLaunchIntentForPackage(match.activityInfo.packageName)
        launch?.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
        if (launch != null) {
            context.startActivity(launch)
            Log.d(TAG, "Opened app: ${match.loadLabel(pm)} (${match.activityInfo.packageName})")
            return true
        }
        return false
    }
}
