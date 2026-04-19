package com.runanywhere.sdk.data.transform

import java.nio.ByteBuffer
import java.nio.CharBuffer
import java.nio.charset.CoderResult

class IncompleteBytesToStringBuffer(
    initialByteCapacity: Int = 8 * 1024,
    private val charCapacity: Int = 8 * 1024,
) {
    private val decoder = Charsets.UTF_8.newDecoder()
    private var inBuf: ByteBuffer = ByteBuffer.allocate(initialByteCapacity)
    private val outBuf: CharBuffer = CharBuffer.allocate(charCapacity)

    fun push(chunk: ByteArray): String {
        ensureCapacity(chunk.size)
        inBuf.put(chunk) // 1) collect
        inBuf.flip() // switch to read mode

        val sb = StringBuilder()

        while (true) {
            outBuf.clear()
            val res: CoderResult = decoder.decode(inBuf, outBuf, false) // 2) opportunistic decode
            outBuf.flip()
            sb.append(outBuf)

            when {
                res.isOverflow -> continue // outBuf too small, loop drains more
                res.isUnderflow -> break // need more bytes for next char (dangling)
                res.isError -> res.throwException() // invalid sequence
            }
        }

        inBuf.compact() // 3) drop consumed bytes, keep leftovers at start
        return sb.toString()
    }

    fun finish(): String {
        // Call when stream ends to flush any buffered partial state
        inBuf.flip()
        val sb = StringBuilder()

        while (true) {
            outBuf.clear()
            val res = decoder.decode(inBuf, outBuf, true)
            outBuf.flip()
            sb.append(outBuf)

            if (res.isOverflow) continue
            if (res.isUnderflow) break
            if (res.isError) res.throwException()
        }

        outBuf.clear()
        decoder.flush(outBuf)
        outBuf.flip()
        sb.append(outBuf)

        inBuf.clear()
        return sb.toString()
    }

    private fun ensureCapacity(incoming: Int) {
        if (inBuf.remaining() >= incoming) return

        // Preserve existing buffered leftovers
        inBuf.flip()
        val needed = inBuf.remaining() + incoming
        var newCap = inBuf.capacity()
        while (newCap < needed) newCap *= 2

        val newBuf = ByteBuffer.allocate(newCap)
        newBuf.put(inBuf)
        inBuf = newBuf
    }
}
