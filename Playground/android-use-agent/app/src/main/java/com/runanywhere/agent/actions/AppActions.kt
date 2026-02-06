package com.runanywhere.agent.actions

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.AlarmClock
import android.util.Log

object AppActions {
    private const val TAG = "AppActions"

    // Package names for common apps
    object Packages {
        const val YOUTUBE = "com.google.android.youtube"
        const val WHATSAPP = "com.whatsapp"
        const val CHROME = "com.android.chrome"
        const val GMAIL = "com.google.android.gm"
        const val PHONE = "com.google.android.dialer"
        const val MESSAGES = "com.google.android.apps.messaging"
        const val MAPS = "com.google.android.apps.maps"
        const val SPOTIFY = "com.spotify.music"
        const val CAMERA = "com.android.camera"
        const val CLOCK = "com.google.android.deskclock"
    }

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

    fun openApp(context: Context, packageName: String): Boolean {
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
}
