#include "DiffusionBridge.hpp"
#include <fstream>
#include <sstream>
#include <stdexcept>

namespace margelo::nitro::runanywhere::diffusion {

const std::string DiffusionBridge::BASE64_CHARS =
    "ABCDEFGHIJKLMNOPQRSTUVWXYZ"
    "abcdefghijklmnopqrstuvwxyz"
    "0123456789+/";

bool DiffusionBridge::isBase64(unsigned char c) {
    return (isalnum(c) || (c == '+') || (c == '/'));
}

std::string DiffusionBridge::encodeBase64(const uint8_t* data, size_t size) {
    std::string result;
    result.reserve(((size + 2) / 3) * 4);

    int i = 0;
    unsigned char char_array_3[3];
    unsigned char char_array_4[4];

    while (size--) {
        char_array_3[i++] = *(data++);
        if (i == 3) {
            char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
            char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
            char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);
            char_array_4[3] = char_array_3[2] & 0x3f;

            for (int j = 0; j < 4; j++) {
                result += BASE64_CHARS[char_array_4[j]];
            }
            i = 0;
        }
    }

    if (i) {
        for (int j = i; j < 3; j++) {
            char_array_3[j] = '\0';
        }

        char_array_4[0] = (char_array_3[0] & 0xfc) >> 2;
        char_array_4[1] = ((char_array_3[0] & 0x03) << 4) + ((char_array_3[1] & 0xf0) >> 4);
        char_array_4[2] = ((char_array_3[1] & 0x0f) << 2) + ((char_array_3[2] & 0xc0) >> 6);

        for (int j = 0; j < i + 1; j++) {
            result += BASE64_CHARS[char_array_4[j]];
        }

        while (i++ < 3) {
            result += '=';
        }
    }

    return result;
}

std::string DiffusionBridge::encodeBase64(const std::vector<uint8_t>& data) {
    return encodeBase64(data.data(), data.size());
}

std::vector<uint8_t> DiffusionBridge::decodeBase64(const std::string& encoded_string) {
    size_t in_len = encoded_string.size();
    int i = 0;
    int j = 0;
    int in_ = 0;
    unsigned char char_array_4[4], char_array_3[3];
    std::vector<uint8_t> result;

    while (in_len-- && (encoded_string[in_] != '=') && isBase64(encoded_string[in_])) {
        char_array_4[i++] = encoded_string[in_];
        in_++;
        if (i == 4) {
            for (i = 0; i < 4; i++) {
                char_array_4[i] = static_cast<unsigned char>(BASE64_CHARS.find(char_array_4[i]));
            }

            char_array_3[0] = (char_array_4[0] << 2) + ((char_array_4[1] & 0x30) >> 4);
            char_array_3[1] = ((char_array_4[1] & 0xf) << 4) + ((char_array_4[2] & 0x3c) >> 2);
            char_array_3[2] = ((char_array_4[2] & 0x3) << 6) + char_array_4[3];

            for (i = 0; i < 3; i++) {
                result.push_back(char_array_3[i]);
            }
            i = 0;
        }
    }

    if (i) {
        for (j = 0; j < i; j++) {
            char_array_4[j] = static_cast<unsigned char>(BASE64_CHARS.find(char_array_4[j]));
        }

        char_array_3[0] = (char_array_4[0] << 2) + ((char_array_4[1] & 0x30) >> 4);
        char_array_3[1] = ((char_array_4[1] & 0xf) << 4) + ((char_array_4[2] & 0x3c) >> 2);

        for (j = 0; j < i - 1; j++) {
            result.push_back(char_array_3[j]);
        }
    }

    return result;
}

std::string DiffusionBridge::encodeFileToBase64(const std::string& filePath) {
    std::ifstream file(filePath, std::ios::binary);
    if (!file.is_open()) {
        throw std::runtime_error("Failed to open file: " + filePath);
    }

    std::vector<uint8_t> buffer(std::istreambuf_iterator<char>(file), {});
    return encodeBase64(buffer);
}

bool DiffusionBridge::saveBase64ToFile(const std::string& base64, const std::string& outputPath) {
    try {
        std::vector<uint8_t> data = decodeBase64(base64);

        std::ofstream file(outputPath, std::ios::binary);
        if (!file.is_open()) {
            return false;
        }

        file.write(reinterpret_cast<const char*>(data.data()), data.size());
        return file.good();
    } catch (...) {
        return false;
    }
}

std::vector<uint8_t> DiffusionBridge::convertRGBAToRGB(const uint8_t* rgba, size_t width, size_t height) {
    std::vector<uint8_t> rgb;
    rgb.reserve(width * height * 3);

    for (size_t i = 0; i < width * height; i++) {
        rgb.push_back(rgba[i * 4]);     // R
        rgb.push_back(rgba[i * 4 + 1]); // G
        rgb.push_back(rgba[i * 4 + 2]); // B
        // Skip A
    }

    return rgb;
}

std::vector<uint8_t> DiffusionBridge::convertRGBToRGBA(const uint8_t* rgb, size_t width, size_t height) {
    std::vector<uint8_t> rgba;
    rgba.reserve(width * height * 4);

    for (size_t i = 0; i < width * height; i++) {
        rgba.push_back(rgb[i * 3]);     // R
        rgba.push_back(rgb[i * 3 + 1]); // G
        rgba.push_back(rgb[i * 3 + 2]); // B
        rgba.push_back(255);            // A (fully opaque)
    }

    return rgba;
}

} // namespace margelo::nitro::runanywhere::diffusion
