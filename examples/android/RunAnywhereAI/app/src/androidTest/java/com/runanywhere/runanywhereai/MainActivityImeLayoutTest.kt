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
        val activity = instrumentation.startActivitySync(
            Intent(instrumentation.targetContext, MainActivity::class.java).apply {
                addFlags(Intent.FLAG_ACTIVITY_NEW_TASK or Intent.FLAG_ACTIVITY_CLEAR_TASK)
            },
        ) as MainActivity
        try {
            waitFor("landscape orientation") {
                activity.resources.configuration.orientation == Configuration.ORIENTATION_LANDSCAPE
            }

            tap(waitForNode("Enable web and tools"))
            waitForNode(
                "Disable web and tools",
                "Web and tools unavailable for current model",
            )

            tap(waitForNode("Message input"))
            waitFor("visible IME") { windowAndImeHeight(activity).imeHeight > 0 }
            waitFor("IME-safe composer layout") {
                val window = windowAndImeHeight(activity)
                val visibleBottom = window.bottomOnScreen - window.imeHeight
                val root = instrumentation.uiAutomation.rootInActiveWindow
                val input = findNode(root, "Message input")
                val send = findNode(root, "Send message")
                if (input == null || send == null) {
                    false
                } else {
                    val inputBounds = Rect().also(input::getBoundsInScreen)
                    val sendBounds = Rect().also(send::getBoundsInScreen)
                    inputBounds.bottom <= visibleBottom + 1 && sendBounds.bottom <= visibleBottom + 1
                }
            }

            val window = windowAndImeHeight(activity)
            val visibleBottom = window.bottomOnScreen - window.imeHeight
            val inputBounds = Rect().also(waitForNode("Message input")::getBoundsInScreen)
            val sendBounds = Rect().also(waitForNode("Send message")::getBoundsInScreen)
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
            instrumentation.runOnMainSync(activity::finish)
            instrumentation.waitForIdleSync()
            instrumentation.uiAutomation.setRotation(UiAutomation.ROTATION_UNFREEZE)
        }
    }

    private fun waitForNode(vararg descriptions: String): AccessibilityNodeInfo {
        val found = AtomicReference<AccessibilityNodeInfo?>()
        waitFor("node ${descriptions.joinToString()}") {
            findNode(instrumentation.uiAutomation.rootInActiveWindow, descriptions)
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
            val decorView = activity.window.decorView
            val location = IntArray(2)
            decorView.getLocationOnScreen(location)
            result.set(
                WindowImeMetrics(
                    bottomOnScreen = location[1] + decorView.height,
                    imeHeight = decorView.rootWindowInsets
                        ?.getInsets(WindowInsets.Type.ime())
                        ?.bottom
                        ?: 0,
                ),
            )
        }
        return result.get()
    }

    private data class WindowImeMetrics(
        val bottomOnScreen: Int,
        val imeHeight: Int,
    )
}
