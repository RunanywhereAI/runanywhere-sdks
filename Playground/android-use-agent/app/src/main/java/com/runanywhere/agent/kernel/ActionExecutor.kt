package com.runanywhere.agent.kernel

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.util.Log
import com.runanywhere.agent.accessibility.AgentAccessibilityService
import com.runanywhere.agent.actions.AppActions
import kotlinx.coroutines.delay
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.File
import kotlin.coroutines.resume

class ActionExecutor(
    private val context: Context,
    private val accessibilityService: () -> AgentAccessibilityService?,
    private val onLog: (String) -> Unit
) {
    companion object {
        private const val TAG = "ActionExecutor"
    }

    suspend fun execute(decision: Decision, indexToCoords: Map<Int, Pair<Int, Int>>): ExecutionResult {
        val service = accessibilityService()
        if (service == null && decision.action !in listOf("open", "url", "search", "done", "wait")) {
            return ExecutionResult(false, "Accessibility service not connected")
        }

        return when (decision.action) {
            "open" -> executeOpenApp(decision)
            "tap" -> executeTap(service!!, decision, indexToCoords)
            "type" -> executeType(service!!, decision)
            "enter" -> executeEnter(service!!)
            "swipe" -> executeSwipe(service!!, decision)
            "long" -> executeLongPress(service!!, decision, indexToCoords)
            "back" -> executeBack(service!!)
            "home" -> executeHome(service!!)
            "url" -> executeOpenUrl(decision)
            "search" -> executeWebSearch(decision)
            "notif" -> executeOpenNotifications(service!!)
            "quick" -> executeOpenQuickSettings(service!!)
            "screenshot" -> executeScreenshot(service!!)
            "wait" -> executeWait()
            "done" -> ExecutionResult(true, "Goal complete")
            else -> ExecutionResult(false, "Unknown action: ${decision.action}")
        }
    }

    private suspend fun executeTap(
        service: AgentAccessibilityService,
        decision: Decision,
        indexToCoords: Map<Int, Pair<Int, Int>>
    ): ExecutionResult {
        val index = decision.elementIndex
            ?: return ExecutionResult(false, "No element index provided")

        // Try ACTION_CLICK first — bypasses gesture interceptor overlays (e.g., X's fab_menu_background_overlay)
        val clickSuccess = service.performClickAtIndex(index)
        if (clickSuccess) {
            onLog("Clicked element $index via accessibility action")
            return ExecutionResult(true, "Clicked element $index")
        }

        // Fall back to coordinate gesture
        val coords = indexToCoords[index]
            ?: return ExecutionResult(false, "Invalid element index: $index")

        onLog("Tapping element $index at (${coords.first}, ${coords.second})")

        return suspendCancellableCoroutine { cont ->
            service.tap(coords.first, coords.second) { success ->
                if (success) {
                    cont.resume(ExecutionResult(true, "Tapped element $index"))
                } else {
                    cont.resume(ExecutionResult(false, "Tap failed"))
                }
            }
        }
    }

    private fun executeType(service: AgentAccessibilityService, decision: Decision): ExecutionResult {
        val text = decision.text ?: return ExecutionResult(false, "No text to type")
        onLog("Typing: $text")
        val success = service.typeText(text)
        return ExecutionResult(success, if (success) "Typed: $text" else "Type failed - no editable field")
    }

    private fun executeEnter(service: AgentAccessibilityService): ExecutionResult {
        onLog("Pressing Enter")
        val success = service.pressEnter()
        return ExecutionResult(success, if (success) "Pressed Enter" else "Enter failed")
    }

    private suspend fun executeSwipe(
        service: AgentAccessibilityService,
        decision: Decision
    ): ExecutionResult {
        val direction = decision.direction ?: "u"
        val dirName = when (direction) {
            "u" -> "up"
            "d" -> "down"
            "l" -> "left"
            "r" -> "right"
            else -> direction
        }
        onLog("Swiping $dirName")

        return suspendCancellableCoroutine { cont ->
            service.swipe(direction) { success ->
                cont.resume(ExecutionResult(success, if (success) "Swiped $dirName" else "Swipe failed"))
            }
        }
    }

    private suspend fun executeLongPress(
        service: AgentAccessibilityService,
        decision: Decision,
        indexToCoords: Map<Int, Pair<Int, Int>>
    ): ExecutionResult {
        val coords = indexToCoords[decision.elementIndex]
            ?: return ExecutionResult(false, "Invalid element index: ${decision.elementIndex}")

        onLog("Long pressing element ${decision.elementIndex}")

        return suspendCancellableCoroutine { cont ->
            service.longPress(coords.first, coords.second) { success ->
                cont.resume(ExecutionResult(success, if (success) "Long pressed" else "Long press failed"))
            }
        }
    }

    private fun executeBack(service: AgentAccessibilityService): ExecutionResult {
        onLog("Going back")
        val success = service.pressBack()
        return ExecutionResult(success, if (success) "Went back" else "Back failed")
    }

    private fun executeHome(service: AgentAccessibilityService): ExecutionResult {
        onLog("Going home")
        val success = service.pressHome()
        return ExecutionResult(success, if (success) "Went home" else "Home failed")
    }

    private fun executeOpenUrl(decision: Decision): ExecutionResult {
        val url = decision.url ?: return ExecutionResult(false, "No URL provided")
        onLog("Opening URL: $url")
        return try {
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(url)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            ExecutionResult(true, "Opened URL: $url")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open URL: ${e.message}")
            ExecutionResult(false, "Failed to open URL: ${e.message}")
        }
    }

    private fun executeWebSearch(decision: Decision): ExecutionResult {
        val query = decision.query ?: return ExecutionResult(false, "No search query provided")
        onLog("Searching: $query")
        return try {
            val searchUrl = "https://www.google.com/search?q=${Uri.encode(query)}"
            val intent = Intent(Intent.ACTION_VIEW, Uri.parse(searchUrl)).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            ExecutionResult(true, "Searched: $query")
        } catch (e: Exception) {
            Log.e(TAG, "Failed to search: ${e.message}")
            ExecutionResult(false, "Failed to search: ${e.message}")
        }
    }

    private fun executeOpenNotifications(service: AgentAccessibilityService): ExecutionResult {
        onLog("Opening notifications")
        val success = service.openNotifications()
        return ExecutionResult(success, if (success) "Opened notifications" else "Failed to open notifications")
    }

    private fun executeOpenQuickSettings(service: AgentAccessibilityService): ExecutionResult {
        onLog("Opening quick settings")
        val success = service.openQuickSettings()
        return ExecutionResult(success, if (success) "Opened quick settings" else "Failed to open quick settings")
    }

    private suspend fun executeScreenshot(service: AgentAccessibilityService): ExecutionResult {
        onLog("Taking screenshot")
        val file = File(context.cacheDir, "screenshot_${System.currentTimeMillis()}.png")

        return suspendCancellableCoroutine { cont ->
            service.takeScreenshot(file) { success ->
                if (success) {
                    cont.resume(ExecutionResult(true, "Screenshot saved: ${file.absolutePath}"))
                } else {
                    cont.resume(ExecutionResult(false, "Screenshot failed"))
                }
            }
        }
    }

    private fun executeOpenApp(decision: Decision): ExecutionResult {
        val appName = decision.text ?: return ExecutionResult(false, "No app name provided")
        onLog("Opening app: $appName")

        // Try known app shortcuts first, with Samsung fallbacks
        val appLower = appName.lowercase()
        val success = when {
            appLower.contains("youtube") -> AppActions.openApp(context, AppActions.Packages.YOUTUBE)
            appLower.contains("chrome") || appLower.contains("browser") -> AppActions.openApp(context, AppActions.Packages.CHROME)
            appLower.contains("whatsapp") -> AppActions.openApp(context, AppActions.Packages.WHATSAPP)
            appLower.contains("instagram") -> AppActions.openApp(context, AppActions.Packages.INSTAGRAM)
            appLower.contains("twitter") || appLower.trim() == "x" -> AppActions.openX(context)
            appLower.contains("telegram") -> AppActions.openApp(context, AppActions.Packages.TELEGRAM)
            appLower.contains("netflix") -> AppActions.openApp(context, AppActions.Packages.NETFLIX)
            appLower.contains("gmail") || appLower.contains("email") -> AppActions.openApp(context, AppActions.Packages.GMAIL)
            appLower.contains("maps") || appLower.contains("map") -> AppActions.openApp(context, AppActions.Packages.MAPS)
            appLower.contains("spotify") -> AppActions.openApp(context, AppActions.Packages.SPOTIFY)
            appLower.contains("clock") || appLower.contains("timer") || appLower.contains("alarm") -> AppActions.openClock(context)
            appLower.contains("camera") ->
                AppActions.openCamera(context) || AppActions.openApp(context, AppActions.Packages.CAMERA_SAMSUNG)
            appLower.contains("phone") || appLower.contains("dialer") ->
                AppActions.openApp(context, AppActions.Packages.PHONE) || AppActions.openApp(context, AppActions.Packages.PHONE_SAMSUNG)
            appLower.contains("messages") || appLower.contains("sms") ->
                AppActions.openApp(context, AppActions.Packages.MESSAGES) || AppActions.openApp(context, AppActions.Packages.MESSAGES_SAMSUNG)
            appLower.contains("calendar") ->
                AppActions.openApp(context, AppActions.Packages.CALENDAR) || AppActions.openApp(context, AppActions.Packages.CALENDAR_SAMSUNG)
            appLower.contains("contacts") ->
                AppActions.openApp(context, AppActions.Packages.CONTACTS) || AppActions.openApp(context, AppActions.Packages.CONTACTS_SAMSUNG)
            appLower.contains("gallery") || appLower.contains("photos") ->
                AppActions.openApp(context, AppActions.Packages.GALLERY_SAMSUNG)
            appLower.contains("calculator") ->
                AppActions.openApp(context, AppActions.Packages.CALCULATOR) || AppActions.openApp(context, AppActions.Packages.CALCULATOR_SAMSUNG)
            appLower.contains("files") || appLower.contains("file manager") ->
                AppActions.openApp(context, AppActions.Packages.FILES) || AppActions.openApp(context, AppActions.Packages.FILES_SAMSUNG)
            appLower == "notes" || appLower == "note" || appLower == "samsung notes" || appLower == "google keep" ->
                AppActions.openNotes(context)
            appLower.contains("setting") -> {
                openSettings()
                true
            }
            else -> AppActions.openAppByName(context, appName) // Bixby-safe fuzzy search
        }

        return ExecutionResult(success, if (success) "Opened $appName" else "Failed to open $appName")
    }

    private suspend fun executeWait(): ExecutionResult {
        onLog("Waiting...")
        delay(2000)
        return ExecutionResult(true, "Waited 2 seconds")
    }

    fun openSettings(settingType: String? = null): Boolean {
        val action = when (settingType?.lowercase()) {
            "bluetooth" -> android.provider.Settings.ACTION_BLUETOOTH_SETTINGS
            "wifi", "wi-fi" -> android.provider.Settings.ACTION_WIFI_SETTINGS
            "display" -> android.provider.Settings.ACTION_DISPLAY_SETTINGS
            "sound", "audio" -> android.provider.Settings.ACTION_SOUND_SETTINGS
            "battery" -> android.provider.Settings.ACTION_BATTERY_SAVER_SETTINGS
            "location" -> android.provider.Settings.ACTION_LOCATION_SOURCE_SETTINGS
            "notification", "notifications" -> android.provider.Settings.ACTION_APP_NOTIFICATION_SETTINGS
            "storage" -> android.provider.Settings.ACTION_INTERNAL_STORAGE_SETTINGS
            "security", "privacy" -> android.provider.Settings.ACTION_SECURITY_SETTINGS
            "accessibility" -> android.provider.Settings.ACTION_ACCESSIBILITY_SETTINGS
            "about" -> android.provider.Settings.ACTION_DEVICE_INFO_SETTINGS
            "developer", "dev" -> android.provider.Settings.ACTION_APPLICATION_DEVELOPMENT_SETTINGS
            "date", "time" -> android.provider.Settings.ACTION_DATE_SETTINGS
            "language" -> android.provider.Settings.ACTION_LOCALE_SETTINGS
            "airplane", "flight" -> android.provider.Settings.ACTION_AIRPLANE_MODE_SETTINGS
            "nfc" -> android.provider.Settings.ACTION_NFC_SETTINGS
            "apps", "applications" -> android.provider.Settings.ACTION_APPLICATION_SETTINGS
            else -> android.provider.Settings.ACTION_SETTINGS
        }

        return try {
            val intent = Intent(action).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)
            }
            context.startActivity(intent)
            onLog("Opened settings: ${settingType ?: "main"}")
            true
        } catch (e: Exception) {
            Log.e(TAG, "Failed to open settings: ${e.message}")
            false
        }
    }
}

data class Decision(
    val action: String,
    val elementIndex: Int? = null,
    val text: String? = null,
    val direction: String? = null,
    val url: String? = null,
    val query: String? = null
)

data class ExecutionResult(
    val success: Boolean,
    val message: String
)
