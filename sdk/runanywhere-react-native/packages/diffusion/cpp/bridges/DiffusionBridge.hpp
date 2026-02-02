#pragma once

#include <string>
#include <vector>
#include <cstdint>

namespace margelo::nitro::runanywhere::diffusion {

/**
 * DiffusionBridge - Utility class for diffusion operations
 *
 * Provides helper functions for:
 * - Base64 encoding/decoding
 * - File I/O operations
 * - Image format conversion
 */
class DiffusionBridge {
public:
    // Base64 Encoding/Decoding
    static std::string encodeBase64(const uint8_t* data, size_t size);
    static std::string encodeBase64(const std::vector<uint8_t>& data);
    static std::vector<uint8_t> decodeBase64(const std::string& base64);

    // File Operations
    static std::string encodeFileToBase64(const std::string& filePath);
    static bool saveBase64ToFile(const std::string& base64, const std::string& outputPath);

    // Image Utilities
    static std::vector<uint8_t> convertRGBAToRGB(const uint8_t* rgba, size_t width, size_t height);
    static std::vector<uint8_t> convertRGBToRGBA(const uint8_t* rgb, size_t width, size_t height);

private:
    // Base64 lookup tables
    static const std::string BASE64_CHARS;
    static bool isBase64(unsigned char c);
};

} // namespace margelo::nitro::runanywhere::diffusion
