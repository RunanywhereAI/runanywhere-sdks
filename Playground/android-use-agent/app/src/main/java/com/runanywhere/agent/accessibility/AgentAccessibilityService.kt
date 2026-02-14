package com.runanywhere.agent.accessibility

import android.accessibilityservice.AccessibilityService
import android.accessibilityservice.AccessibilityServiceInfo
import android.accessibilityservice.GestureDescription
import android.content.Context
import android.graphics.Bitmap
import android.graphics.Path
import android.graphics.Rect
import android.os.Build
import android.os.Bundle
import android.provider.Settings
import android.util.Log
import android.view.accessibility.AccessibilityEvent
import android.view.accessibility.AccessibilityNodeInfo
import kotlinx.coroutines.suspendCancellableCoroutine
import java.io.ByteArrayOutputStream
import java.io.File
import java.io.FileOutputStream
import java.util.Locale
import kotlin.coroutines.resume

class AgentAccessibilityService : AccessibilityService() {

    companion object {
        private const val TAG = "AgentAccessibility"
        @Volatile var instance: AgentAccessibilityService? = null

        fun isEnabled(context: Context): Boolean {
            val enabledServices = Settings.Secure.getString(
                context.contentResolver,
                Settings.Secure.ENABLED_ACCESSIBILITY_SERVICES
            ) ?: return false
            return enabledServices.contains("${context.packageName}/${AgentAccessibilityService::class.java.name}")
        }
    }

    override fun onServiceConnected() {
        super.onServiceConnected()
        instance = this
        serviceInfo = serviceInfo.apply {
            eventTypes = AccessibilityEvent.TYPES_ALL_MASK
            feedbackType = AccessibilityServiceInfo.FEEDBACK_GENERIC
            flags = AccessibilityServiceInfo.FLAG_REPORT_VIEW_IDS or
                    AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS or
                    AccessibilityServiceInfo.FLAG_REQUEST_TOUCH_EXPLORATION_MODE
        }
        Log.i(TAG, "Accessibility service connected")
    }

    override fun onDestroy() {
        super.onDestroy()
        instance = null
        Log.i(TAG, "Accessibility service destroyed")
    }

    override fun onAccessibilityEvent(event: AccessibilityEvent?) {
        // No-op: agent pulls state on demand
    }

    override fun onInterrupt() {
        // No-op
    }

    // ========== Screen State ==========

    data class ScreenElement(
        val index: Int,
        val label: String,
        val resourceId: String,
        val className: String,
        val centerX: Int,
        val centerY: Int,
        val isClickable: Boolean,
        val isEditable: Boolean,
        val isCheckable: Boolean,
        val isChecked: Boolean,
        val suggestedAction: String
    )

    data class ScreenState(
        val compactText: String,
        val elements: List<ScreenElement>,
        val indexToCoords: Map<Int, Pair<Int, Int>>
    )

    fun getScreenState(maxElements: Int = 30, maxTextLength: Int = 50): ScreenState {
        val root = rootInActiveWindow ?: return ScreenState("", emptyList(), emptyMap())
        val elements = mutableListOf<ScreenElement>()
        val indexToCoords = mutableMapOf<Int, Pair<Int, Int>>()
        val lines = mutableListOf<String>()

        traverseForElements(root, elements, maxElements, maxTextLength)

        elements.forEachIndexed { idx, elem ->
            indexToCoords[idx] = Pair(elem.centerX, elem.centerY)

            val caps = mutableListOf<String>()
            if (elem.isClickable) caps.add("tap")
            if (elem.isEditable) caps.add("edit")
            if (elem.isCheckable) caps.add(if (elem.isChecked) "checked" else "unchecked")

            val capsStr = if (caps.isNotEmpty()) " [${caps.joinToString(",")}]" else ""
            val displayLabel = elem.label.ifEmpty { elem.className.split(".").lastOrNull() ?: "element" }
            val typeStr = elem.className.split(".").lastOrNull() ?: ""
            lines.add("$idx: $displayLabel ($typeStr) $capsStr".trim())
        }

        return ScreenState(lines.joinToString("\n"), elements, indexToCoords)
    }

    private fun traverseForElements(
        node: AccessibilityNodeInfo,
        elements: MutableList<ScreenElement>,
        maxElements: Int,
        maxTextLength: Int
    ) {
        if (elements.size >= maxElements) return

        val text = node.text?.toString()?.trim()?.take(maxTextLength) ?: ""
        val desc = node.contentDescription?.toString()?.trim()?.take(maxTextLength) ?: ""
        val label = text.ifEmpty { desc }
        val clickable = node.isClickable
        val editable = node.isEditable
        val checkable = node.isCheckable
        val checked = node.isChecked
        val enabled = node.isEnabled
        val className = node.className?.toString() ?: ""
        val resourceId = node.viewIdResourceName?.substringAfterLast("/") ?: ""

        // Include interactive or labeled elements
        if (enabled && (label.isNotEmpty() || clickable || editable || checkable)) {
            val bounds = Rect()
            node.getBoundsInScreen(bounds)

            if (bounds.width() > 0 && bounds.height() > 0) {
                val suggestedAction = when {
                    editable -> "type"
                    checkable -> "toggle"
                    clickable -> "tap"
                    else -> "read"
                }

                elements.add(
                    ScreenElement(
                        index = elements.size,
                        label = label,
                        resourceId = resourceId,
                        className = className.split(".").lastOrNull() ?: "",
                        centerX = (bounds.left + bounds.right) / 2,
                        centerY = (bounds.top + bounds.bottom) / 2,
                        isClickable = clickable,
                        isEditable = editable,
                        isCheckable = checkable,
                        isChecked = checked,
                        suggestedAction = suggestedAction
                    )
                )
            }
        }

        for (i in 0 until node.childCount) {
            if (elements.size >= maxElements) return
            node.getChild(i)?.let { child ->
                traverseForElements(child, elements, maxElements, maxTextLength)
            }
        }
    }

    // ========== Actions ==========

    fun tap(x: Int, y: Int, callback: ((Boolean) -> Unit)? = null) {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 100))
            .build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                callback?.invoke(true)
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                callback?.invoke(false)
            }
        }, null)
    }

    fun longPress(x: Int, y: Int, durationMs: Long = 1000, callback: ((Boolean) -> Unit)? = null) {
        val path = Path().apply { moveTo(x.toFloat(), y.toFloat()) }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, durationMs))
            .build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                callback?.invoke(true)
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                callback?.invoke(false)
            }
        }, null)
    }

    fun swipe(direction: String, callback: ((Boolean) -> Unit)? = null) {
        val (sx, sy, ex, ey) = when (direction.lowercase()) {
            "up", "u" -> listOf(540, 1400, 540, 400)
            "down", "d" -> listOf(540, 400, 540, 1400)
            "left", "l" -> listOf(900, 800, 200, 800)
            "right", "r" -> listOf(200, 800, 900, 800)
            else -> listOf(540, 1400, 540, 400)
        }

        val path = Path().apply {
            moveTo(sx.toFloat(), sy.toFloat())
            lineTo(ex.toFloat(), ey.toFloat())
        }
        val gesture = GestureDescription.Builder()
            .addStroke(GestureDescription.StrokeDescription(path, 0, 300))
            .build()
        dispatchGesture(gesture, object : GestureResultCallback() {
            override fun onCompleted(gestureDescription: GestureDescription?) {
                callback?.invoke(true)
            }
            override fun onCancelled(gestureDescription: GestureDescription?) {
                callback?.invoke(false)
            }
        }, null)
    }

    fun typeText(text: String): Boolean {
        val node = findEditableNode() ?: return false
        val args = Bundle().apply {
            putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, text)
        }
        return node.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, args)
    }

    fun pressEnter(): Boolean {
        val root = rootInActiveWindow ?: return false
        val focused = findNode(root) { it.isFocused || it.isEditable }

        if (focused != null) {
            // API 30+: use ACTION_IME_ENTER which triggers the keyboard's search/done/enter action
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                if (focused.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_IME_ENTER.id)) {
                    return true
                }
            }
            // Fallback: click the focused node (may submit on some fields)
            if (focused.performAction(AccessibilityNodeInfo.ACTION_CLICK)) {
                return true
            }
        }

        // Last resort: try global back (unreliable for Enter)
        return false
    }

    fun pressBack(): Boolean = performGlobalAction(GLOBAL_ACTION_BACK)

    fun pressHome(): Boolean = performGlobalAction(GLOBAL_ACTION_HOME)

    fun openRecents(): Boolean = performGlobalAction(GLOBAL_ACTION_RECENTS)

    fun openNotifications(): Boolean = performGlobalAction(GLOBAL_ACTION_NOTIFICATIONS)

    fun openQuickSettings(): Boolean = performGlobalAction(GLOBAL_ACTION_QUICK_SETTINGS)

    fun takeScreenshot(outputFile: File, callback: (Boolean) -> Unit) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        try {
                            val bitmap = Bitmap.wrapHardwareBuffer(
                                screenshot.hardwareBuffer,
                                screenshot.colorSpace
                            )
                            if (bitmap != null) {
                                FileOutputStream(outputFile).use { out ->
                                    bitmap.compress(Bitmap.CompressFormat.PNG, 100, out)
                                }
                                callback(true)
                            } else {
                                callback(false)
                            }
                            screenshot.hardwareBuffer.close()
                        } catch (e: Exception) {
                            Log.e(TAG, "Screenshot save failed: ${e.message}")
                            callback(false)
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "Screenshot failed with error code: $errorCode")
                        callback(false)
                    }
                }
            )
        } else {
            callback(false)
        }
    }

    /**
     * Capture screenshot and return as base64-encoded JPEG string.
     * Resizes to half resolution and compresses as JPEG at 60% quality.
     */
    suspend fun captureScreenshotBase64(): String? {
        if (Build.VERSION.SDK_INT < Build.VERSION_CODES.R) return null

        return suspendCancellableCoroutine { cont ->
            takeScreenshot(
                android.view.Display.DEFAULT_DISPLAY,
                mainExecutor,
                object : TakeScreenshotCallback {
                    override fun onSuccess(screenshot: ScreenshotResult) {
                        try {
                            val hardwareBitmap = Bitmap.wrapHardwareBuffer(
                                screenshot.hardwareBuffer,
                                screenshot.colorSpace
                            )
                            screenshot.hardwareBuffer.close()

                            if (hardwareBitmap == null) {
                                cont.resume(null)
                                return
                            }

                            // Hardware bitmaps can't be manipulated directly
                            val softBitmap = hardwareBitmap.copy(Bitmap.Config.ARGB_8888, false)
                            hardwareBitmap.recycle()

                            // Resize to half resolution
                            val scaled = Bitmap.createScaledBitmap(
                                softBitmap,
                                softBitmap.width / 2,
                                softBitmap.height / 2,
                                true
                            )
                            softBitmap.recycle()

                            // Compress to JPEG at 60% quality
                            val baos = ByteArrayOutputStream()
                            scaled.compress(Bitmap.CompressFormat.JPEG, 60, baos)
                            scaled.recycle()

                            val base64 = android.util.Base64.encodeToString(
                                baos.toByteArray(),
                                android.util.Base64.NO_WRAP
                            )
                            cont.resume(base64)
                        } catch (e: Exception) {
                            Log.e(TAG, "Screenshot base64 failed: ${e.message}")
                            cont.resume(null)
                        }
                    }

                    override fun onFailure(errorCode: Int) {
                        Log.e(TAG, "Screenshot capture failed: $errorCode")
                        cont.resume(null)
                    }
                }
            )
        }
    }

    // ========== Node Finders ==========

    fun findEditableNode(): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return findNode(root) { it.isEditable }
    }

    fun findNodeByText(text: String, ignoreCase: Boolean = true): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        val searchText = if (ignoreCase) text.lowercase(Locale.getDefault()) else text
        return findNode(root) { node ->
            val nodeText = node.text?.toString() ?: ""
            val nodeDesc = node.contentDescription?.toString() ?: ""
            val t = if (ignoreCase) nodeText.lowercase(Locale.getDefault()) else nodeText
            val d = if (ignoreCase) nodeDesc.lowercase(Locale.getDefault()) else nodeDesc
            t.contains(searchText) || d.contains(searchText)
        }
    }

    fun findNodeByResourceId(resourceId: String): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        return findNode(root) { node ->
            node.viewIdResourceName?.contains(resourceId) == true
        }
    }

    fun findToggleNode(keyword: String): AccessibilityNodeInfo? {
        val root = rootInActiveWindow ?: return null
        val lower = keyword.lowercase(Locale.getDefault())

        val match = findNode(root) { node ->
            val text = node.text?.toString()?.lowercase(Locale.getDefault()).orEmpty()
            val desc = node.contentDescription?.toString()?.lowercase(Locale.getDefault()).orEmpty()
            text.contains(lower) || desc.contains(lower)
        } ?: return null

        // Prefer a Switch/CompoundButton in the matched subtree
        val toggle = findNode(match) { node ->
            val cls = node.className?.toString().orEmpty()
            cls.contains("Switch") || cls.contains("CompoundButton") || cls.contains("Toggle")
        }
        if (toggle != null) return toggle

        // Fallback: clickable node or clickable parent
        if (match.isClickable) return match
        var parent = match.parent
        while (parent != null) {
            if (parent.isClickable) return parent
            parent = parent.parent
        }
        return null
    }

    private fun findNode(
        node: AccessibilityNodeInfo,
        predicate: (AccessibilityNodeInfo) -> Boolean
    ): AccessibilityNodeInfo? {
        if (predicate(node)) return node
        for (i in 0 until node.childCount) {
            val child = node.getChild(i) ?: continue
            val found = findNode(child, predicate)
            if (found != null) return found
        }
        return null
    }
}
