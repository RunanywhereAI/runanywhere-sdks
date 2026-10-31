/*
 * Copyright 2026 RunAnywhere SDK
 * SPDX-License-Identifier: Apache-2.0
 */

package com.runanywhere.sdk.foundation.bridge.extensions

import org.junit.Rule
import org.junit.rules.TemporaryFolder
import java.io.File
import java.io.IOException
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

class CppBridgePlatformAdapterDirectoryTest {
    @get:Rule
    val temporaryFolder = TemporaryFolder()

    @Test
    fun `missing path remains a not-found result`() {
        val missing = File(temporaryFolder.root, "missing")

        assertNull(CppBridgePlatformAdapter.fileListDirectoryCallback(missing.path))
    }

    @Test
    fun `regular file remains a not-found directory result`() {
        val file = temporaryFolder.newFile("weights.gguf")

        assertNull(CppBridgePlatformAdapter.fileListDirectoryCallback(file.path))
    }

    @Test
    fun `successfully enumerated empty directory remains empty`() {
        val directory = temporaryFolder.newFolder("empty")

        val entries = assertNotNull(CppBridgePlatformAdapter.fileListDirectoryCallback(directory.path))

        assertTrue(entries.isEmpty())
    }

    @Test
    fun `successful listing preserves file and directory metadata`() {
        val directory = temporaryFolder.newFolder("model")
        File(directory, "weights.gguf").writeBytes(ByteArray(42))
        assertTrue(File(directory, "nested").mkdir())

        val entries = assertNotNull(CppBridgePlatformAdapter.fileListDirectoryCallback(directory.path)).associateBy { it.name }

        assertEquals(setOf("weights.gguf", "nested"), entries.keys)
        assertEquals(RacDirectoryEntry("weights.gguf", false, 42), entries["weights.gguf"])
        assertEquals(RacDirectoryEntry("nested", true, 0), entries["nested"])
    }

    @Test
    fun `null listing is an error rather than an empty directory`() {
        val directory = Directory(children = { null })

        assertFailsWith<IOException> {
            CppBridgePlatformAdapter.readDirectoryEntries(directory)
        }
    }

    @Test
    fun `permission denial propagates to the JNI boundary`() {
        val failure = SecurityException("directory access denied")
        val directory = Directory(children = { throw failure })

        assertSame(
            failure,
            assertFailsWith<SecurityException> {
                CppBridgePlatformAdapter.readDirectoryEntries(directory)
            },
        )
    }

    @Test
    fun `enumeration exception propagates to the JNI boundary`() {
        val failure = IOException("directory read failed")
        val directory = Directory(children = { throw failure })

        assertSame(
            failure,
            assertFailsWith<IOException> {
                CppBridgePlatformAdapter.readDirectoryEntries(directory)
            },
        )
    }

    @Test
    fun `denied existence probe does not become not-found`() {
        val directory = Directory(existsValue = { throw SecurityException("probe denied") })

        assertFailsWith<SecurityException> {
            CppBridgePlatformAdapter.readDirectoryEntries(directory)
        }
    }

    @Test
    fun `denied directory probe does not become not-found`() {
        val directory = Directory(directoryValue = { throw SecurityException("probe denied") })

        assertFailsWith<SecurityException> {
            CppBridgePlatformAdapter.readDirectoryEntries(directory)
        }
    }

    private class Directory(
        private val children: () -> Array<File>? = { emptyArray() },
        private val existsValue: () -> Boolean = { true },
        private val directoryValue: () -> Boolean = { true },
    ) : File("model-directory") {
        override fun exists(): Boolean = existsValue()

        override fun isDirectory(): Boolean = directoryValue()

        override fun listFiles(): Array<File>? = children()
    }
}
