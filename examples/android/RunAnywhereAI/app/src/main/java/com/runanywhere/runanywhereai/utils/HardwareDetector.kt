package com.runanywhere.runanywhereai.utils

import android.os.Build
import android.util.Log
import java.io.BufferedReader
import java.io.FileReader

/**
 * Utility class for detecting hardware capabilities and optimal backends
 */
object HardwareDetector {
    private const val TAG = "HardwareDetector"

    /**
     * Detects the device chipset manufacturer and model
     */
    fun getChipset(): Chipset {
        val hardware = Build.HARDWARE.lowercase()
        val board = Build.BOARD.lowercase()
        val device = Build.DEVICE.lowercase()

        Log.d(TAG, "Hardware: $hardware, Board: $board, Device: $device")

        return when {
            // Qualcomm Snapdragon
            hardware.contains("qcom") ||
            board.contains("msm") ||
            board.contains("sdm") ||
            board.contains("sm") -> {
                Chipset.QUALCOMM(getQualcommModel())
            }

            // Samsung Exynos
            hardware.contains("exynos") ||
            board.contains("exynos") -> {
                Chipset.SAMSUNG_EXYNOS(getExynosModel())
            }

            // MediaTek
            hardware.contains("mt") ||
            board.contains("mt") ||
            hardware.contains("mediatek") -> {
                Chipset.MEDIATEK(getMediaTekModel())
            }

            // Google Tensor
            hardware.contains("tensor") ||
            device.contains("oriole") || // Pixel 6
            device.contains("raven") ||   // Pixel 6 Pro
            device.contains("bluejay") || // Pixel 6a
            device.contains("cheetah") || // Pixel 7 Pro
            device.contains("panther") -> // Pixel 7
            {
                Chipset.GOOGLE_TENSOR(getTensorModel())
            }

            // Huawei Kirin
            hardware.contains("kirin") ||
            board.contains("kirin") -> {
                Chipset.HUAWEI_KIRIN(getKirinModel())
            }

            else -> Chipset.UNKNOWN
        }
    }

    /**
     * Determines if the device has a neural processing unit
     */
    fun hasNeuralAccelerator(): Boolean {
        return when (getChipset()) {
            is Chipset.QUALCOMM -> hasQualcommHexagon()
            is Chipset.SAMSUNG_EXYNOS -> hasSamsungNPU()
            is Chipset.MEDIATEK -> hasMediaTekAPU()
            is Chipset.GOOGLE_TENSOR -> true // All Tensor chips have TPU
            is Chipset.HUAWEI_KIRIN -> hasKirinNPU()
            else -> false
        }
    }

    /**
     * Gets the optimal backend for the current device
     */
    fun getOptimalBackend(): Backend {
        val chipset = getChipset()

        return when {
            // Qualcomm with Hexagon DSP
            chipset is Chipset.QUALCOMM && hasQualcommHexagon() -> Backend.QNN

            // Google Tensor with TPU
            chipset is Chipset.GOOGLE_TENSOR -> Backend.NNAPI

            // Samsung with NPU
            chipset is Chipset.SAMSUNG_EXYNOS && hasSamsungNPU() -> Backend.SAMSUNG_NPU

            // MediaTek with APU
            chipset is Chipset.MEDIATEK && hasMediaTekAPU() -> Backend.MEDIATEK_APU

            // Vulkan capable GPU
            hasVulkanSupport() -> Backend.VULKAN

            // OpenCL capable GPU
            hasOpenCLSupport() -> Backend.OPENCL

            // NNAPI as fallback for Android 8.1+
            Build.VERSION.SDK_INT >= Build.VERSION_CODES.O_MR1 -> Backend.NNAPI

            // CPU fallback
            else -> Backend.CPU
        }
    }

    private fun getQualcommModel(): String {
        val hardware = Build.HARDWARE.lowercase()
        return when {
            hardware.contains("sm8650") -> "Snapdragon 8 Gen 3"
            hardware.contains("sm8550") -> "Snapdragon 8 Gen 2"
            hardware.contains("sm8450") -> "Snapdragon 8 Gen 1"
            hardware.contains("sm8350") -> "Snapdragon 888"
            hardware.contains("sm8250") -> "Snapdragon 865"
            hardware.contains("sm8150") -> "Snapdragon 855"
            hardware.contains("sm7475") -> "Snapdragon 7+ Gen 2"
            hardware.contains("sm7450") -> "Snapdragon 7 Gen 1"
            else -> "Snapdragon"
        }
    }

    private fun getExynosModel(): String {
        val board = Build.BOARD.lowercase()
        return when {
            board.contains("s5e9945") -> "Exynos 2400"
            board.contains("s5e9935") -> "Exynos 2300"
            board.contains("s5e9925") -> "Exynos 2200"
            board.contains("s5e9840") -> "Exynos 2100"
            board.contains("s5e9830") -> "Exynos 990"
            else -> "Exynos"
        }
    }

    private fun getMediaTekModel(): String {
        val hardware = Build.HARDWARE.lowercase()
        return when {
            hardware.contains("mt6985") -> "Dimensity 9300"
            hardware.contains("mt6983") -> "Dimensity 9200"
            hardware.contains("mt6893") -> "Dimensity 1200"
            hardware.contains("mt6889") -> "Dimensity 1000"
            else -> "MediaTek"
        }
    }

    private fun getTensorModel(): String {
        val device = Build.DEVICE.lowercase()
        return when {
            device.contains("cheetah") || device.contains("panther") -> "Tensor G2"
            device.contains("oriole") || device.contains("raven") -> "Tensor G1"
            else -> "Tensor"
        }
    }

    private fun getKirinModel(): String {
        val hardware = Build.HARDWARE.lowercase()
        return when {
            hardware.contains("kirin9000") -> "Kirin 9000"
            hardware.contains("kirin990") -> "Kirin 990"
            hardware.contains("kirin980") -> "Kirin 980"
            else -> "Kirin"
        }
    }

    private fun hasQualcommHexagon(): Boolean {
        // Snapdragon 835 and newer have Hexagon DSP
        val model = getQualcommModel()
        return model.contains("8") || model.contains("7")
    }

    private fun hasSamsungNPU(): Boolean {
        // Exynos 9820 and newer have NPU
        val model = getExynosModel()
        return model.contains("2") || model.contains("990") || model.contains("9925")
    }

    private fun hasMediaTekAPU(): Boolean {
        // Dimensity 1000 and newer have APU
        val model = getMediaTekModel()
        return model.contains("Dimensity")
    }

    private fun hasKirinNPU(): Boolean {
        // Kirin 970 and newer have NPU
        val model = getKirinModel()
        return model.contains("9")
    }

    fun hasVulkanSupport(): Boolean {
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.N
    }

    fun hasOpenCLSupport(): Boolean {
        // Most modern Android GPUs support OpenCL
        // This is a simplified check
        return Build.VERSION.SDK_INT >= Build.VERSION_CODES.LOLLIPOP
    }

    /**
     * Represents different chipset manufacturers
     */
    sealed class Chipset {
        data class QUALCOMM(val model: String) : Chipset()
        data class SAMSUNG_EXYNOS(val model: String) : Chipset()
        data class MEDIATEK(val model: String) : Chipset()
        data class GOOGLE_TENSOR(val model: String) : Chipset()
        data class HUAWEI_KIRIN(val model: String) : Chipset()
        object UNKNOWN : Chipset()
    }

    /**
     * Available backend options for AI inference
     */
    enum class Backend {
        CPU,           // Pure CPU execution
        NNAPI,         // Android Neural Networks API
        VULKAN,        // Vulkan GPU compute
        OPENCL,        // OpenCL GPU compute
        QNN,           // Qualcomm Neural Network (Hexagon DSP)
        SAMSUNG_NPU,   // Samsung Neural Processing Unit
        MEDIATEK_APU,  // MediaTek AI Processing Unit
        XNNPACK        // Cross-platform neural network inference
    }

    /**
     * Gets device information for debugging
     */
    fun getDeviceInfo(): String {
        return buildString {
            appendLine("Device: ${Build.DEVICE}")
            appendLine("Model: ${Build.MODEL}")
            appendLine("Manufacturer: ${Build.MANUFACTURER}")
            appendLine("Hardware: ${Build.HARDWARE}")
            appendLine("Board: ${Build.BOARD}")
            appendLine("SDK: ${Build.VERSION.SDK_INT}")
            appendLine("Chipset: ${getChipset()}")
            appendLine("Neural Accelerator: ${hasNeuralAccelerator()}")
            appendLine("Optimal Backend: ${getOptimalBackend()}")
        }
    }
}
