/**
 * @file image_io.cpp
 * @brief RGBA → PNG encoder (stored/uncompressed DEFLATE, zero dependencies).
 *
 * The commons CoreML diffusion engine returns raw RGBA pixel data. To honour
 * `rcli image ... --out foo.png` we wrap those pixels in a valid PNG container.
 * We avoid pulling libpng/zlib into the CLI by emitting the IDAT as a zlib
 * stream built from *stored* DEFLATE blocks (BTYPE=00). The file is larger than
 * a compressed PNG but is byte-for-byte valid per the PNG/zlib/DEFLATE specs.
 */

#include "io/image_io.h"

#include <algorithm>
#include <cctype>
#include <cstdint>
#include <cstdio>
#include <string>
#include <vector>

namespace rcli::image {

namespace {

void put_u32_be(std::vector<uint8_t>& out, uint32_t v) {
    out.push_back(static_cast<uint8_t>((v >> 24) & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 16) & 0xFF));
    out.push_back(static_cast<uint8_t>((v >> 8) & 0xFF));
    out.push_back(static_cast<uint8_t>(v & 0xFF));
}

uint32_t crc32(const uint8_t* data, size_t len) {
    static uint32_t table[256];
    static bool ready = false;
    if (!ready) {
        for (uint32_t n = 0; n < 256; ++n) {
            uint32_t c = n;
            for (int k = 0; k < 8; ++k) {
                c = (c & 1U) ? (0xEDB88320U ^ (c >> 1)) : (c >> 1);
            }
            table[n] = c;
        }
        ready = true;
    }
    uint32_t crc = 0xFFFFFFFFU;
    for (size_t i = 0; i < len; ++i) {
        crc = table[(crc ^ data[i]) & 0xFF] ^ (crc >> 8);
    }
    return crc ^ 0xFFFFFFFFU;
}

uint32_t adler32(const uint8_t* data, size_t len) {
    constexpr uint32_t kMod = 65521;
    uint32_t a = 1;
    uint32_t b = 0;
    size_t i = 0;
    while (i < len) {
        const size_t block = std::min<size_t>(len - i, 5552);
        for (size_t j = 0; j < block; ++j) {
            a += data[i + j];
            b += a;
        }
        a %= kMod;
        b %= kMod;
        i += block;
    }
    return (b << 16) | a;
}

void write_chunk(std::vector<uint8_t>& png, const char type[4], const std::vector<uint8_t>& data) {
    put_u32_be(png, static_cast<uint32_t>(data.size()));
    const size_t crc_start = png.size();
    png.insert(png.end(), type, type + 4);
    png.insert(png.end(), data.begin(), data.end());
    const uint32_t crc = crc32(png.data() + crc_start, png.size() - crc_start);
    put_u32_be(png, crc);
}

}  // namespace

bool write_png(const std::string& path, const uint8_t* rgba, int width, int height,
               std::string* error) {
    if (!rgba || width <= 0 || height <= 0) {
        if (error) {
            *error = "invalid image dimensions or data";
        }
        return false;
    }

    // Filtered scanlines: PNG requires a per-row filter byte (0 = None).
    const size_t row_bytes = static_cast<size_t>(width) * 4;
    std::vector<uint8_t> raw;
    raw.reserve(static_cast<size_t>(height) * (1 + row_bytes));
    for (int y = 0; y < height; ++y) {
        raw.push_back(0);  // filter type: none
        const uint8_t* row = rgba + static_cast<size_t>(y) * row_bytes;
        raw.insert(raw.end(), row, row + row_bytes);
    }

    // zlib stream: 2-byte header, stored DEFLATE blocks, 4-byte Adler-32.
    std::vector<uint8_t> zlib;
    zlib.push_back(0x78);  // CMF: deflate, 32K window
    zlib.push_back(0x01);  // FLG: no dict, fastest
    size_t pos = 0;
    do {
        const size_t block = std::min<size_t>(raw.size() - pos, 0xFFFF);
        const bool final_block = (pos + block >= raw.size());
        zlib.push_back(final_block ? 1 : 0);  // BFINAL + BTYPE=00 (stored)
        const uint16_t len = static_cast<uint16_t>(block);
        const uint16_t nlen = static_cast<uint16_t>(~len);
        zlib.push_back(static_cast<uint8_t>(len & 0xFF));
        zlib.push_back(static_cast<uint8_t>((len >> 8) & 0xFF));
        zlib.push_back(static_cast<uint8_t>(nlen & 0xFF));
        zlib.push_back(static_cast<uint8_t>((nlen >> 8) & 0xFF));
        zlib.insert(zlib.end(), raw.begin() + static_cast<std::ptrdiff_t>(pos),
                    raw.begin() + static_cast<std::ptrdiff_t>(pos + block));
        pos += block;
    } while (pos < raw.size());
    const uint32_t adler = adler32(raw.data(), raw.size());
    put_u32_be(zlib, adler);

    std::vector<uint8_t> png;
    const uint8_t signature[8] = {137, 80, 78, 71, 13, 10, 26, 10};
    png.insert(png.end(), signature, signature + 8);

    std::vector<uint8_t> ihdr;
    put_u32_be(ihdr, static_cast<uint32_t>(width));
    put_u32_be(ihdr, static_cast<uint32_t>(height));
    ihdr.push_back(8);  // bit depth
    ihdr.push_back(6);  // color type: RGBA
    ihdr.push_back(0);  // compression: deflate
    ihdr.push_back(0);  // filter: adaptive
    ihdr.push_back(0);  // interlace: none
    write_chunk(png, "IHDR", ihdr);
    write_chunk(png, "IDAT", zlib);
    write_chunk(png, "IEND", {});

    FILE* file = std::fopen(path.c_str(), "wb");
    if (!file) {
        if (error) {
            *error = "cannot open " + path + " for writing";
        }
        return false;
    }
    const size_t written = std::fwrite(png.data(), 1, png.size(), file);
    std::fclose(file);
    if (written != png.size()) {
        if (error) {
            *error = "short write to " + path;
        }
        return false;
    }
    return true;
}

namespace {

// Parse the next whitespace-delimited unsigned integer from a PPM header,
// skipping '#'-to-EOL comments. Returns false at EOF / on non-numeric input.
bool next_ppm_uint(const std::vector<uint8_t>& bytes, size_t* pos, uint32_t* out) {
    size_t i = *pos;
    for (;;) {
        while (i < bytes.size() && std::isspace(bytes[i])) {
            ++i;
        }
        if (i < bytes.size() && bytes[i] == '#') {  // comment to end of line
            while (i < bytes.size() && bytes[i] != '\n') {
                ++i;
            }
            continue;
        }
        break;
    }
    if (i >= bytes.size() || !std::isdigit(bytes[i])) {
        return false;
    }
    uint64_t value = 0;
    while (i < bytes.size() && std::isdigit(bytes[i])) {
        value = value * 10 + static_cast<uint64_t>(bytes[i] - '0');
        if (value > 0xFFFFFFFFULL) {
            return false;
        }
        ++i;
    }
    *out = static_cast<uint32_t>(value);
    *pos = i;
    return true;
}

}  // namespace

bool read_ppm(const std::string& path, RgbImage* out, std::string* error) {
    FILE* file = std::fopen(path.c_str(), "rb");
    if (!file) {
        if (error) {
            *error = "cannot open " + path;
        }
        return false;
    }
    std::vector<uint8_t> bytes;
    uint8_t chunk[4096];
    size_t n = 0;
    while ((n = std::fread(chunk, 1, sizeof(chunk), file)) > 0) {
        bytes.insert(bytes.end(), chunk, chunk + n);
    }
    std::fclose(file);

    if (bytes.size() < 2 || bytes[0] != 'P' || bytes[1] != '6') {
        if (error) {
            *error = path + " is not a binary PPM (P6); convert with e.g. `magick in.png out.ppm`";
        }
        return false;
    }
    size_t pos = 2;
    uint32_t width = 0;
    uint32_t height = 0;
    uint32_t maxval = 0;
    if (!next_ppm_uint(bytes, &pos, &width) || !next_ppm_uint(bytes, &pos, &height) ||
        !next_ppm_uint(bytes, &pos, &maxval)) {
        if (error) {
            *error = "malformed PPM header in " + path;
        }
        return false;
    }
    if (width == 0 || height == 0 || maxval != 255) {
        if (error) {
            *error = "unsupported PPM (need non-empty dimensions and maxval 255)";
        }
        return false;
    }
    // Exactly one whitespace byte separates the header from the pixel payload.
    ++pos;
    const size_t expected = static_cast<size_t>(width) * height * 3;
    if (pos + expected > bytes.size()) {
        if (error) {
            *error = "truncated PPM pixel data in " + path;
        }
        return false;
    }
    out->width = width;
    out->height = height;
    out->rgb.assign(bytes.begin() + static_cast<std::ptrdiff_t>(pos),
                    bytes.begin() + static_cast<std::ptrdiff_t>(pos + expected));
    return true;
}

}  // namespace rcli::image
