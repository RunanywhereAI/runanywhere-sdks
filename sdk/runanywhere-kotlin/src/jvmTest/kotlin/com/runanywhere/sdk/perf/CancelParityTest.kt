/**
 * CancelParityTest.kt — JUnit runner for GAP 09 #7 (v3.1 Phase 5.1).
 */

package com.runanywhere.sdk.perf

import org.junit.Test
import org.junit.Assume
import java.io.File
import tests.streaming.cancel_parity.CancelParity
import kotlin.test.assertTrue
import kotlin.test.assertNotNull

class CancelParityTest {
    @Test
    fun `cancel parity records interrupt and writes trace`() {
        Assume.assumeTrue(
            "cancel_parity input missing at /tmp/cancel_input.bin",
            File(CancelParity.DEFAULT_INPUT_PATH).exists()
        )
        val result = CancelParity.run()
        assertTrue(result.total > 0, "expected >0 events")
        assertNotNull(result.interruptOrdinal, "expected interrupt marker")
    }
}
