package com.runanywhere.runanywhereai

import android.app.UiAutomation
import android.content.Intent
import android.content.res.Configuration
import android.graphics.Rect
import android.os.ParcelFileDescriptor
import android.os.SystemClock
import android.util.Log
import android.view.WindowInsets
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.atomic.AtomicReference

@RunWith(AndroidJUnit4::class)
class MainActivityImeLayoutTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test
    fun landscapeComposerAndSendStayAboveIme() {
        instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_FREEZE_90)
        val scenario = ActivityScenario.launch<MainActivity>(
            Intent(instrumentation.targetContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            },
        )
        try {
            val currentActivity = AtomicReference<MainActivity?>()
            waitFor("resumed landscape activity") {
                scenario.onActivity { candidate ->
                    if (candidate.resources.configuration.orientation ==
                        Configuration.ORIENTATION_LANDSCAPE
                    ) {
                        currentActivity.set(candidate)
                    }
                }
                currentActivity.get() != null
            }
            val activity = currentActivity.get()!!
            waitFor("focused activity window") {
                !activity.isFinishing &&
                    !activity.isDestroyed &&
                    activity.window.decorView.isAttachedToWindow &&
                    activity.hasWindowFocus()
            }

            val toolsToggle = waitForNode(
                activity,
                "Enable web and tools",
                "Disable web and tools",
                "Web and tools unavailable for current model",
            )
            if (toolsToggle.contentDescription?.toString() == "Enable web and tools") {
                tap(toolsToggle)
            }
            waitForNode(
                activity,
                "Disable web and tools",
                "Web and tools unavailable for current model",
            )

            tap(waitForNode(activity, "Message input"))
            waitFor("visible IME") { windowAndImeHeight(activity).imeHeight > 0 }
            val safeLayout = AtomicReference<LayoutSnapshot?>()
            waitFor("IME-safe composer layout") {
                val window = windowAndImeHeight(activity)
                val root = activeRoot(activity)
                val input = findNode(root, "Message input")
                val send = findNode(root, "Send message")
                if (input == null || send == null) {
                    false
                } else if (!input.refresh() || !send.refresh()) {
                    false
                } else {
                    val inputBounds = Rect().also(input::getBoundsInScreen)
                    val sendBounds = Rect().also(send::getBoundsInScreen)
                    val snapshot = LayoutSnapshot(window, inputBounds, sendBounds)
                    safeLayout.set(snapshot)
                    snapshot.isImeSafe
                }
            }

            val layout = safeLayout.get()!!
            val window = layout.window
            val visibleBottom = window.bottomOnScreen - window.imeHeight
            val inputBounds = layout.inputBounds
            val sendBounds = layout.sendBounds
            Log.i(
                "ImeLayoutTest",
                "windowBottom=${window.bottomOnScreen} imeHeight=${window.imeHeight} " +
                    "visibleBottom=$visibleBottom input=$inputBounds send=$sendBounds",
            )

            assertTrue(
                "Input $inputBounds must not cross the IME top $visibleBottom",
                inputBounds.bottom <= visibleBottom + 1,
            )
            assertTrue(
                "Send $sendBounds must not cross the IME top $visibleBottom",
                sendBounds.bottom <= visibleBottom + 1,
            )
        } finally {
            scenario.close()
            instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_UNFREEZE)
        }
    }

    private fun waitForNode(
        activity: MainActivity,
        vararg descriptions: String,
    ): AccessibilityNodeInfo {
        val found = AtomicReference<AccessibilityNodeInfo?>()
        waitFor("node ${descriptions.joinToString()}") {
            findNode(activeRoot(activity), descriptions)
                ?.also(found::set) != null
        }
        val node = found.get()
        assertNotNull(node)
        return node!!
    }

    private fun tap(node: AccessibilityNodeInfo) {
        val bounds = Rect().also(node::getBoundsInScreen)
        shell("input tap ${bounds.centerX()} ${bounds.centerY()}")
    }

    private fun shell(command: String) {
        ParcelFileDescriptor.AutoCloseInputStream(
            instrumentation.uiAutomation.executeShellCommand(command),
        ).use { it.readBytes() }
    }

    private fun findNode(
        node: AccessibilityNodeInfo?,
        descriptions: Array<out String>,
    ): AccessibilityNodeInfo? {
        node ?: return null
        val contentDescription = node.contentDescription?.toString()
        for (description in descriptions) {
            if (contentDescription == description) return node
        }
        repeat(node.childCount) { index ->
            findNode(node.getChild(index), descriptions)?.let { return it }
        }
        return null
    }

    private fun findNode(node: AccessibilityNodeInfo?, description: String): AccessibilityNodeInfo? =
        findNode(node, arrayOf(description))

    private fun waitFor(
        description: String,
        timeoutMillis: Long = 30_000,
        condition: () -> Boolean,
    ) {
        val deadline = SystemClock.uptimeMillis() + timeoutMillis
        while (SystemClock.uptimeMillis() < deadline) {
            if (condition()) return
            instrumentation.waitForIdleSync()
            SystemClock.sleep(25)
        }
        assertTrue("Timed out waiting for $description", condition())
    }

    private fun windowAndImeHeight(activity: MainActivity): WindowImeMetrics {
        val result = AtomicReference<WindowImeMetrics>()
        instrumentation.runOnMainSync {
            val metrics = activity.windowManager.currentWindowMetrics
            result.set(
                WindowImeMetrics(
                    bottomOnScreen = metrics.bounds.bottom,
                    imeHeight = metrics.windowInsets
                        .getInsets(WindowInsets.Type.ime())
                        .bottom,
                ),
            )
        }
        return result.get()
    }

    private fun activeRoot(activity: MainActivity): AccessibilityNodeInfo? {
        if (!activity.hasWindowFocus()) return null
        val root = instrumentation.uiAutomation.rootInActiveWindow ?: return null
        if (!root.refresh()) return null
        return root.takeIf { it.packageName == instrumentation.targetContext.packageName }
    }

    private data class WindowImeMetrics(
        val bottomOnScreen: Int,
        val imeHeight: Int,
    )

    private data class LayoutSnapshot(
        val window: WindowImeMetrics,
        val inputBounds: Rect,
        val sendBounds: Rect,
    ) {
        val isImeSafe: Boolean
            get() {
                val visibleBottom = window.bottomOnScreen - window.imeHeight
                return inputBounds.bottom <= visibleBottom + 1 &&
                    sendBounds.bottom <= visibleBottom + 1
            }
    }
}
