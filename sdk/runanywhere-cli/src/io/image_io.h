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

namespace rcli::image {

/**
 * Write 8-bit RGBA pixels (row-major, width*height*4 bytes) as a PNG file.
 * Returns false and fills `error` (when non-null) on any failure.
 */
bool write_png(const std::string& path, const uint8_t* rgba, int width, int height,
               std::string* error);

}  // namespace rcli::image

#endif  // RCLI_IO_IMAGE_IO_H
