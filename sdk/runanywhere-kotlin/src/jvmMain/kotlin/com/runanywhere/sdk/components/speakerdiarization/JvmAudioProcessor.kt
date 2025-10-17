package com.runanywhere.sdk.components.speakerdiarization

import kotlin.math.*

/**
 * JVM implementation of PlatformAudioProcessor with optimized audio processing
 * Matches iOS Accelerate framework functionality using Java/Kotlin optimizations
 */
actual class PlatformAudioProcessor {

    /**
     * Create speaker embedding from audio samples
     * Uses energy-based features with spectral analysis
     */
    actual fun createEmbedding(audioSamples: FloatArray): FloatArray {
        if (audioSamples.isEmpty()) {
            return FloatArray(128) // Default embedding size
        }

        val embeddingSize = 128
        val embedding = FloatArray(embeddingSize)
        val chunkSize = max(1, audioSamples.size / embeddingSize)

        for (i in 0 until min(embeddingSize, audioSamples.size / chunkSize)) {
            val start = i * chunkSize
            val end = min(start + chunkSize, audioSamples.size)
            val chunk = audioSamples.sliceArray(start until end)

            if (chunk.isNotEmpty()) {
                // Calculate multiple features for more robust embedding
                val mean = chunk.average().toFloat()
                val variance = chunk.map { (it - mean).pow(2) }.average().toFloat()
                val rmsEnergy = sqrt(chunk.map { it * it }.average()).toFloat()
                val zeroCrossingRate = calculateZeroCrossingRate(chunk)

                // Combine features (similar to iOS implementation)
                embedding[i] = mean + sqrt(variance) + rmsEnergy * 0.5f + zeroCrossingRate * 0.1f
            }
        }

        // Normalize embedding to unit vector
        return normalizeVector(embedding)
    }

    /**
     * Calculate cosine similarity between two embeddings
     * Optimized vector operations matching iOS Accelerate framework
     */
    actual fun cosineSimilarity(a: FloatArray, b: FloatArray): Float {
        if (a.size != b.size || a.isEmpty()) return 0.0f

        var dotProduct = 0.0f
        var normA = 0.0f
        var normB = 0.0f

        // Vectorized operations for better performance
        for (i in a.indices) {
            dotProduct += a[i] * b[i]
            normA += a[i] * a[i]
            normB += b[i] * b[i]
        }

        val denominator = sqrt(normA) * sqrt(normB)
        return if (denominator > 0.0f) dotProduct / denominator else 0.0f
    }

    /**
     * Calculate RMS energy of audio samples
     */
    actual fun calculateRMSEnergy(samples: FloatArray): Float {
        if (samples.isEmpty()) return 0.0f

        val sumSquares = samples.map { it * it }.sum()
        return sqrt(sumSquares / samples.size)
    }

    /**
     * Extract comprehensive audio features for speaker identification
     */
    actual fun extractFeatures(samples: FloatArray, sampleRate: Int): AudioFeatures {
        if (samples.isEmpty()) {
            return AudioFeatures(0.0f, 0.0f, 0.0f, FloatArray(128))
        }

        val rmsEnergy = calculateRMSEnergy(samples)
        val zeroCrossingRate = calculateZeroCrossingRate(samples)
        val spectralCentroid = calculateSpectralCentroid(samples, sampleRate)
        val embedding = createEmbedding(samples)

        return AudioFeatures(
            rmsEnergy = rmsEnergy,
            zeroCrossingRate = zeroCrossingRate,
            spectralCentroid = spectralCentroid,
            embedding = embedding
        )
    }

    /**
     * Apply windowing function to audio samples
     */
    actual fun applyWindow(samples: FloatArray, windowType: WindowType): FloatArray {
        if (samples.isEmpty()) return samples

        val windowed = samples.copyOf()
        val n = samples.size

        for (i in samples.indices) {
            val window = when (windowType) {
                WindowType.RECTANGULAR -> 1.0f
                WindowType.HANN -> (0.5f * (1.0f - cos(2.0f * PI.toFloat() * i / (n - 1)))).toFloat()
                WindowType.HAMMING -> (0.54f - 0.46f * cos(2.0f * PI.toFloat() * i / (n - 1))).toFloat()
                WindowType.BLACKMAN -> {
                    val a0 = 0.42f
                    val a1 = 0.5f
                    val a2 = 0.08f
                    (a0 - a1 * cos(2.0f * PI.toFloat() * i / (n - 1)) +
                     a2 * cos(4.0f * PI.toFloat() * i / (n - 1))).toFloat()
                }
            }
            windowed[i] *= window
        }

        return windowed
    }

    /**
     * Segment audio into overlapping chunks
     */
    actual fun segmentAudio(
        samples: FloatArray,
        sampleRate: Int,
        windowSize: Double,
        stepSize: Double
    ): List<AudioChunk> {
        if (samples.isEmpty()) return emptyList()

        val chunks = mutableListOf<AudioChunk>()
        val windowSamples = (windowSize * sampleRate).toInt()
        val stepSamples = (stepSize * sampleRate).toInt()
        val totalDuration = samples.size.toDouble() / sampleRate

        var startSample = 0
        while (startSample < samples.size) {
            val endSample = min(startSample + windowSamples, samples.size)
            val chunkSamples = samples.sliceArray(startSample until endSample)

            if (chunkSamples.isNotEmpty()) {
                val startTime = startSample.toDouble() / sampleRate
                val endTime = endSample.toDouble() / sampleRate

                chunks.add(
                    AudioChunk(
                        samples = chunkSamples,
                        startTime = startTime,
                        endTime = endTime,
                        sampleRate = sampleRate
                    )
                )
            }

            startSample += stepSamples

            // Prevent infinite loop if step size is too small
            if (stepSamples <= 0) break
        }

        return chunks
    }

    // MARK: - Private Utility Methods

    /**
     * Calculate zero crossing rate for voice activity detection
     */
    private fun calculateZeroCrossingRate(samples: FloatArray): Float {
        if (samples.size < 2) return 0.0f

        var crossings = 0
        for (i in 1 until samples.size) {
            if ((samples[i] >= 0 && samples[i - 1] < 0) ||
                (samples[i] < 0 && samples[i - 1] >= 0)) {
                crossings++
            }
        }

        return crossings.toFloat() / (samples.size - 1)
    }

    /**
     * Calculate spectral centroid for voice characterization
     */
    private fun calculateSpectralCentroid(samples: FloatArray, sampleRate: Int): Float {
        if (samples.isEmpty()) return 0.0f

        // Simple spectral centroid calculation using FFT approximation
        // For a more accurate implementation, we would use a proper FFT
        val spectrum = computeSimpleSpectrum(samples)
        val freqBins = spectrum.size
        val binWidth = sampleRate.toFloat() / (2 * freqBins)

        var numerator = 0.0f
        var denominator = 0.0f

        for (i in spectrum.indices) {
            val frequency = i * binWidth
            val magnitude = spectrum[i]
            numerator += frequency * magnitude
            denominator += magnitude
        }

        return if (denominator > 0.0f) numerator / denominator else 0.0f
    }

    /**
     * Compute simple spectrum approximation (not a proper FFT)
     */
    private fun computeSimpleSpectrum(samples: FloatArray): FloatArray {
        val spectrumSize = min(64, samples.size / 2)
        val spectrum = FloatArray(spectrumSize)
        val chunkSize = samples.size / spectrumSize

        for (i in 0 until spectrumSize) {
            val start = i * chunkSize
            val end = min(start + chunkSize, samples.size)
            val chunk = samples.sliceArray(start until end)

            // Calculate magnitude for this frequency bin
            var realPart = 0.0f
            var imagPart = 0.0f

            for (j in chunk.indices) {
                val angle = -2.0f * PI.toFloat() * i * j / chunk.size
                realPart += chunk[j] * cos(angle)
                imagPart += chunk[j] * sin(angle)
            }

            spectrum[i] = sqrt(realPart * realPart + imagPart * imagPart)
        }

        return spectrum
    }

    /**
     * Normalize vector to unit length
     */
    private fun normalizeVector(vector: FloatArray): FloatArray {
        val norm = sqrt(vector.map { it * it }.sum())
        return if (norm > 0.0f) {
            vector.map { it / norm }.toFloatArray()
        } else {
            vector
        }
    }

    /**
     * Apply Gaussian window for smoothing
     */
    private fun applyGaussianSmoothing(samples: FloatArray, sigma: Float = 1.0f): FloatArray {
        if (samples.size < 3) return samples

        val smoothed = FloatArray(samples.size)
        val kernelSize = min(7, samples.size) // Adaptive kernel size
        val halfKernel = kernelSize / 2

        for (i in samples.indices) {
            var sum = 0.0f
            var weightSum = 0.0f

            for (j in -halfKernel..halfKernel) {
                val idx = i + j
                if (idx in samples.indices) {
                    val weight = exp(-(j * j).toFloat() / (2 * sigma * sigma))
                    sum += samples[idx] * weight
                    weightSum += weight
                }
            }

            smoothed[i] = if (weightSum > 0) sum / weightSum else samples[i]
        }

        return smoothed
    }

    /**
     * Compute autocorrelation for pitch analysis
     */
    private fun computeAutocorrelation(samples: FloatArray, maxLag: Int): FloatArray {
        val lags = min(maxLag, samples.size / 2)
        val autocorr = FloatArray(lags)

        for (lag in 0 until lags) {
            var sum = 0.0f
            val count = samples.size - lag

            for (i in 0 until count) {
                sum += samples[i] * samples[i + lag]
            }

            autocorr[lag] = if (count > 0) sum / count else 0.0f
        }

        // Normalize by first value (lag 0)
        if (autocorr[0] > 0) {
            for (i in autocorr.indices) {
                autocorr[i] /= autocorr[0]
            }
        }

        return autocorr
    }

    /**
     * Detect fundamental frequency (F0) for voice characterization
     */
    private fun detectFundamentalFrequency(samples: FloatArray, sampleRate: Int): Float {
        if (samples.size < 64) return 0.0f

        val minF0 = 50.0f  // Hz
        val maxF0 = 500.0f // Hz
        val minPeriod = (sampleRate / maxF0).toInt()
        val maxPeriod = (sampleRate / minF0).toInt()

        val autocorr = computeAutocorrelation(samples, maxPeriod)
        var bestLag = minPeriod
        var maxCorr = 0.0f

        // Find peak in autocorrelation (excluding lag 0)
        for (lag in minPeriod until min(maxPeriod, autocorr.size)) {
            if (autocorr[lag] > maxCorr) {
                maxCorr = autocorr[lag]
                bestLag = lag
            }
        }

        return if (maxCorr > 0.3f) { // Threshold for reliable pitch detection
            sampleRate.toFloat() / bestLag
        } else {
            0.0f // No reliable pitch detected
        }
    }
}
