/**
 * cancel_parity.kt — Kotlin consumer for GAP 09 #7 (v3.1 Phase 5.1).
 */

package tests.streaming.cancel_parity

import ai.runanywhere.proto.v1.VoiceEvent
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder

object CancelParity {
    const val DEFAULT_INPUT_PATH = "/tmp/cancel_input.bin"
    const val DEFAULT_OUTPUT_PATH = "/tmp/cancel_trace.kt.log"
    const val MAGIC = 0x43504152u  // 'CPAR'

    data class Result(
        val total: Int,
        val interruptOrdinal: Int?,
        val postCancelCount: Int,
        val postCancelMaxDeltaNs: Long,
    )

    fun run(
        inputPath: String = DEFAULT_INPUT_PATH,
        outputPath: String = DEFAULT_OUTPUT_PATH,
    ): Result {
        val bytes = File(inputPath).readBytes()
        require(bytes.size >= 8) { "input too short" }
        val header = ByteBuffer.wrap(bytes, 0, 8).order(ByteOrder.LITTLE_ENDIAN)
        require(header.int.toUInt() == MAGIC) { "bad magic" }
        val count = header.int

        val lines = mutableListOf<String>()
        var cursor = 8
        var interruptOrdinal: Int? = null
        var cancelNs: Long? = null
        var postCancelCount = 0
        var postCancelMaxDelta = 0L

        for (i in 0 until count) {
            if (cursor + 4 > bytes.size) break
            val lenBuf = ByteBuffer.wrap(bytes, cursor, 4).order(ByteOrder.LITTLE_ENDIAN)
            val len = lenBuf.int
            cursor += 4
            if (cursor + len > bytes.size) break

            val recvNs = System.nanoTime()
            val frame = bytes.copyOfRange(cursor, cursor + len)
            cursor += len

            val kind = try {
                val event = VoiceEvent.ADAPTER.decode(frame)
                when {
                    event.user_said != null       -> "userSaid"
                    event.assistant_token != null -> "assistantToken"
                    event.audio != null           -> "audio"
                    event.vad != null             -> "vad"
                    event.state != null           -> "state"
                    event.error != null           -> "error"
                    event.interrupted != null     -> "interrupted"
                    event.metrics != null         -> "metrics"
                    else                          -> "unknown"
                }
            } catch (_: Exception) {
                "unknown"
            }
            lines.add("$i $kind $recvNs")

            if (kind == "interrupted" && interruptOrdinal == null) {
                interruptOrdinal = i
                cancelNs = recvNs
            } else if (cancelNs != null) {
                postCancelCount++
                val delta = recvNs - cancelNs!!
                if (delta > postCancelMaxDelta) postCancelMaxDelta = delta
            }
        }

        File(outputPath).writeText(lines.joinToString("\n") + "\n")
        return Result(
            total = count,
            interruptOrdinal = interruptOrdinal,
            postCancelCount = postCancelCount,
            postCancelMaxDeltaNs = postCancelMaxDelta,
        )
    }
}
