package com.runanywhere.runanywhereai

import android.os.Build
import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.Assert.assertEquals
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.HashSet

@RunWith(AndroidJUnit4::class)
class QHexRTStartupTest {
    @Test
    fun applicationStartupExtractsCurrentQHexRTSkels() {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        val packageInfo = context.packageManager.getPackageInfo(context.packageName, 0)
        @Suppress("DEPRECATION")
        val versionCode =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.P) {
                packageInfo.longVersionCode
            } else {
                packageInfo.versionCode.toLong()
            }
        val skelDirectory =
            File(
                context.codeCacheDir,
                "runanywhere/qhexrt/skels/$versionCode-${packageInfo.lastUpdateTime}/arm64-v8a",
            )
        val expected = HashSet<String>()
        expected.add("libQnnHtpV75Skel.so")
        expected.add("libQnnHtpV79Skel.so")
        expected.add("libQnnHtpV81Skel.so")

        val deadline = SystemClock.uptimeMillis() + 15_000
        var actual = HashSet<String>()
        while (SystemClock.uptimeMillis() < deadline) {
            actual = HashSet()
            skelDirectory.listFiles()?.forEach { file ->
                if (file.isFile) actual.add(file.name)
            }
            if (actual == expected) break
            SystemClock.sleep(100)
        }

        assertEquals(expected, actual)
    }
}
