/**
 * @file image_io.h
 * @brief Minimal RGBA → PNG encoder for `rcli image` output.
 *
 * CLI-owned file I/O, mirroring io/wav_io: commons diffusion engines return
 * raw RGBA pixels (image_media_type "image/raw-rgba"); rcli renders them to a
 * real PNG so `--out foo.png` is a valid image. Self-contained (no libpng /
 * zlib dependency): emits a PNG whose IDAT is a zlib stream of *stored*
 * (uncompressed) DEFLATE blocks, which every decoder accepts.
 */

#ifndef RCLI_IO_IMAGE_IO_H
#define RCLI_IO_IMAGE_IO_H

#include <cstdint>
#include <string>
#include <vector>

namespace rcli::image {

/**
 * Write 8-bit RGBA pixels (row-major, width*height*4 bytes) as a PNG file.
 * Returns false and fills `error` (when non-null) on any failure.
 */
bool write_png(const std::string& path, const uint8_t* rgba, int width, int height,
               std::string* error);

/** Decoded 8-bit RGB image (row-major, width*height*3 bytes, tightly packed). */
struct RgbImage {
    std::vector<uint8_t> rgb;
    uint32_t width = 0;
    uint32_t height = 0;
};

/**
 * Read a binary PPM (P6, maxval 255) image into tightly-packed RGB8. PPM is the
 * dependency-free counterpart to write_png: `magick in.png out.ppm` (or
 * `ffmpeg -i in.png out.ppm`) produces one. Returns false + fills `error` on any
 * malformed input.
 */
bool read_ppm(const std::string& path, RgbImage* out, std::string* error);

}  // namespace rcli::image

#endif  // RCLI_IO_IMAGE_IO_H
