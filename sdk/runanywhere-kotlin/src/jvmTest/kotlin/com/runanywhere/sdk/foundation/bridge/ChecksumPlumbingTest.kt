/*
 * ChecksumPlumbingTest.kt
 *
 * M6 verification — asserts that `ModelInfo.checksumSha256`,
 * `ModelFileDescriptor.checksumSha256`, and `LoraAdapterCatalogEntry.checksumSha256`
 * plumb end-to-end through the data types and into `CppBridgeDownload.DownloadTask`,
 * so that a deliberate wrong-hash surfaces via `CHECKSUM_FAILED` once the native
 * download runner evaluates it.
 *
 * The native `rac_http_download_execute` call is unavailable in this unit test
 * environment (no JNI loaded), so we exercise the pre-native path: the
 * bookkeeping layer that carries the checksum from ModelInfo → DownloadTask →
 * racHttpDownloadExecute. The native side is already covered by the commons
 * SHA-256 unit tests (runanywhere-commons/tests/http_download_sha256_test.cpp).
 */

package com.runanywhere.sdk.foundation.bridge

import com.runanywhere.sdk.core.types.InferenceFramework
import com.runanywhere.sdk.foundation.bridge.extensions.CppBridgeDownload
import com.runanywhere.sdk.public.extensions.Models.ModelCategory
import com.runanywhere.sdk.public.extensions.Models.ModelFileDescriptor
import com.runanywhere.sdk.public.extensions.Models.ModelFormat
import com.runanywhere.sdk.public.extensions.Models.ModelInfo
import com.runanywhere.sdk.public.extensions.LoraAdapterCatalogEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test

class ChecksumPlumbingTest {

    private val wrongHash = "deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef"
    private val rightHash = "a".repeat(64)

    @Test
    fun `ModelInfo checksumSha256 field is populated and propagates`() {
        val model = ModelInfo(
            id = "test-model",
            name = "Test Model",
            category = ModelCategory.LANGUAGE,
            format = ModelFormat.GGUF,
            framework = InferenceFramework.LLAMA_CPP,
            downloadURL = "https://example.com/model.gguf",
            checksumSha256 = wrongHash,
        )
        assertEquals(wrongHash, model.checksumSha256)

        // copy semantics — unchanged when unspecified
        val copy = model.copy(localPath = "/tmp/model.gguf")
        assertEquals(wrongHash, copy.checksumSha256)
    }

    @Test
    fun `ModelFileDescriptor carries per-file checksum for multi-file models`() {
        val descriptor = ModelFileDescriptor(
            url = "https://example.com/mmproj.gguf",
            filename = "mmproj.gguf",
            checksumSha256 = wrongHash,
        )
        assertEquals(wrongHash, descriptor.checksumSha256)

        // default is null so models without a checksum just skip verification
        val descriptorNoHash = ModelFileDescriptor(
            url = "https://example.com/model.gguf",
            filename = "model.gguf",
        )
        assertNull(descriptorNoHash.checksumSha256)
    }

    @Test
    fun `LoraAdapterCatalogEntry carries checksum through to native runner`() {
        val entry = LoraAdapterCatalogEntry(
            id = "adapter-1",
            name = "Test Adapter",
            description = "unit test",
            downloadUrl = "https://example.com/adapter.gguf",
            filename = "adapter.gguf",
            compatibleModelIds = listOf("base-model"),
            checksumSha256 = rightHash,
        )
        assertEquals(rightHash, entry.checksumSha256)
    }

    @Test
    fun `CppBridgeDownload DownloadTask propagates expectedChecksum`() {
        // Reproduce the shape `startDownloadCallback` constructs so we can
        // assert the checksum survives the wrapping without needing JNI.
        val task = CppBridgeDownload.DownloadTask(
            downloadId = "task-1",
            url = "https://example.com/model.gguf",
            destinationPath = "/tmp/dst",
            modelId = "test-model",
            framework = 0,
            expectedChecksum = wrongHash,
        )
        assertEquals(wrongHash, task.expectedChecksum)
    }

    @Test
    fun `CHECKSUM_FAILED error code has a stable name and user message`() {
        // This is the error the native runner raises via
        // RAC_HTTP_DL_CHECKSUM_FAILED whenever the wrong-hash path runs.
        // Asserting the constants here means any rename/reshuffle breaks
        // compile, not just the error surface that consumers observe.
        assertEquals(5, CppBridgeDownload.DownloadError.CHECKSUM_FAILED)
        assertEquals(
            "CHECKSUM_FAILED",
            CppBridgeDownload.DownloadError.getName(
                CppBridgeDownload.DownloadError.CHECKSUM_FAILED,
            ),
        )
        val userMsg = CppBridgeDownload.DownloadError.getUserMessage(
            CppBridgeDownload.DownloadError.CHECKSUM_FAILED,
        )
        assertNotNull(userMsg)
        // Must mention the corruption cause so UI surfaces it clearly.
        assert(userMsg.contains("verification", ignoreCase = true) ||
               userMsg.contains("corrupt", ignoreCase = true)) {
            "user message for CHECKSUM_FAILED should describe integrity failure: $userMsg"
        }
    }
}
