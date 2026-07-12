package com.runanywhere.runanywhereai.data.security

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import org.junit.After
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

@RunWith(AndroidJUnit4::class)
class NoBackupCiphertextStoreInstrumentedTest {
    private lateinit var context: Context
    private lateinit var directoryName: String

    @Before
    fun setUp() {
        context = InstrumentationRegistry.getInstrumentation().targetContext
        directoryName = "secure_store_test_${UUID.randomUUID()}"
    }

    @After
    fun tearDown() {
        assertTrue(NoBackupCiphertextStore(context, directoryName).clear())
    }

    @Test
    fun persistsEmptyAndBinaryValuesAcrossInstancesOutsideBackupStorage() {
        val first = NoBackupCiphertextStore(context, directoryName)
        val binary = byteArrayOf(0, 1, 2, 0x7f, 0x80.toByte(), 0xff.toByte())

        assertTrue(first.write("empty", byteArrayOf()))
        assertTrue(first.write("binary", binary))

        val reopened = NoBackupCiphertextStore(context, directoryName)
        assertArrayEquals(byteArrayOf(), reopened.read("empty"))
        assertArrayEquals(binary, reopened.read("binary"))
        assertTrue(
            File(context.noBackupFilesDir, directoryName).canonicalPath.startsWith(
                context.noBackupFilesDir.canonicalPath + File.separator,
            ),
        )
    }

    @Test
    fun deleteAndClearReportDurableResults() {
        val store = NoBackupCiphertextStore(context, directoryName)
        assertTrue(store.delete("missing"))
        assertTrue(store.write("first", byteArrayOf(1)))
        assertTrue(store.write("second", byteArrayOf(2)))

        assertTrue(store.delete("first"))
        assertFalse(File(context.noBackupFilesDir, directoryName).listFiles().isNullOrEmpty())
        assertTrue(store.clear())
        assertFalse(File(context.noBackupFilesDir, directoryName).exists())
    }

    @Test
    fun concurrentInstancesDoNotLoseOrPartiallyWriteEntries() {
        val executor = Executors.newFixedThreadPool(8)
        try {
            val writes = (0 until 64).map { index ->
                executor.submit<Boolean> {
                    NoBackupCiphertextStore(context, directoryName).write(
                        "key-$index",
                        ByteArray(256) { index.toByte() },
                    )
                }
            }
            writes.forEach { assertTrue(it.get(30, TimeUnit.SECONDS)) }
        } finally {
            executor.shutdownNow()
        }

        val reopened = NoBackupCiphertextStore(context, directoryName)
        (0 until 64).forEach { index ->
            assertArrayEquals(ByteArray(256) { index.toByte() }, reopened.read("key-$index"))
        }
    }
}
