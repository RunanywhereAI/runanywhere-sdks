package com.runanywhere.runanywhereai.ui.screens.vision

import android.content.Context
import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.graphics.ImageDecoder
import android.net.Uri
import android.os.Build

/**
 * Reads a picked image into a bitmap small enough to hold and to caption.
 *
 * Lives beside the vision view models rather than inside the screen so the decode runs off the
 * main thread once, in one place, for both the gallery and the file-picker route.
 */
internal object VisionImageDecoder {

    /**
     * Cap the longest edge so a 12-50 MP photo does not decode at full native resolution and
     * blow the heap. VLM backends downscale well below this anyway.
     */
    private const val MAX_DECODE_EDGE = 1568

    /** The decoded bitmap, or null when the bytes behind [uri] are not a readable image. */
    fun decode(context: Context, uri: Uri): Bitmap? =
        // Catch Throwable (not just Exception): a huge photo can raise OutOfMemoryError even
        // after downsampling, and we want that to degrade to a stated failure rather than
        // crash. runCatching{} only covers Exception, so this is an explicit try/catch.
        try {
            if (Build.VERSION.SDK_INT < Build.VERSION_CODES.P) {
                decodeDownsampled(context, uri)
            } else {
                val source = ImageDecoder.createSource(context.contentResolver, uri)
                ImageDecoder.decodeBitmap(source) { decoder, info, _ ->
                    val longest = maxOf(info.size.width, info.size.height)
                    if (longest > MAX_DECODE_EDGE) decoder.setTargetSampleSize(sampleSizeFor(longest))
                    decoder.allocator = ImageDecoder.ALLOCATOR_SOFTWARE
                    decoder.isMutableRequired = false
                }
            }
        } catch (t: Throwable) {
            null
        }

    private fun decodeDownsampled(context: Context, uri: Uri): Bitmap? {
        val bounds = BitmapFactory.Options().apply { inJustDecodeBounds = true }
        context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, bounds) }
        val longest = maxOf(bounds.outWidth, bounds.outHeight)
        val options = BitmapFactory.Options().apply {
            inSampleSize = if (longest > MAX_DECODE_EDGE) sampleSizeFor(longest) else 1
        }
        return context.contentResolver.openInputStream(uri)?.use { BitmapFactory.decodeStream(it, null, options) }
    }

    /** Smallest power-of-two sample size that brings [longest] at or under [MAX_DECODE_EDGE]. */
    private fun sampleSizeFor(longest: Int): Int {
        var sample = 1
        while (longest / sample > MAX_DECODE_EDGE) sample *= 2
        return sample
    }
}
