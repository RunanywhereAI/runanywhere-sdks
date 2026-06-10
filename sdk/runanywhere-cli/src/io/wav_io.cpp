#include "io/wav_io.h"

#include <algorithm>
#include <cstdio>
#include <cstring>

namespace rcli::wav {

namespace {

struct ChunkHeader {
    char id[4];
    uint32_t size;
};

uint32_t read_u32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

uint16_t read_u16(const uint8_t* p) {
    return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

}  // namespace

bool read_wav(const std::string& path, WavData* out, std::string* error) {
    FILE* f = std::fopen(path.c_str(), "rb");
    if (!f) {
        if (error) {
            *error = "cannot open " + path;
        }
        return false;
    }

    bool ok = false;
    uint16_t channels = 0;
    uint16_t bits = 0;
    uint32_t rate = 0;
    std::vector<uint8_t> data;

    do {
        uint8_t riff[12];
        if (std::fread(riff, 1, sizeof(riff), f) != sizeof(riff) ||
            std::memcmp(riff, "RIFF", 4) != 0 || std::memcmp(riff + 8, "WAVE", 4) != 0) {
            if (error) {
                *error = path + " is not a RIFF/WAVE file";
            }
            break;
        }

        bool have_fmt = false;
        bool have_data = false;
        while (!have_fmt || !have_data) {
            uint8_t header[8];
            if (std::fread(header, 1, sizeof(header), f) != sizeof(header)) {
                break;
            }
            const uint32_t chunk_size = read_u32(header + 4);
            if (std::memcmp(header, "fmt ", 4) == 0) {
                std::vector<uint8_t> fmt(chunk_size);
                if (std::fread(fmt.data(), 1, chunk_size, f) != chunk_size || chunk_size < 16) {
                    break;
                }
                const uint16_t format = read_u16(fmt.data());
                channels = read_u16(fmt.data() + 2);
                rate = read_u32(fmt.data() + 4);
                bits = read_u16(fmt.data() + 14);
                if (format != 1 /*PCM*/ || bits != 16 || channels == 0) {
                    if (error) {
                        *error = "only 16-bit PCM WAV is supported";
                    }
                    have_fmt = false;
                    break;
                }
                have_fmt = true;
            } else if (std::memcmp(header, "data", 4) == 0) {
                data.resize(chunk_size);
                if (std::fread(data.data(), 1, chunk_size, f) != chunk_size) {
                    break;
                }
                have_data = true;
            } else {
                // Skip unknown chunk (padded to even size).
                std::fseek(f, static_cast<long>(chunk_size + (chunk_size & 1)), SEEK_CUR);
            }
        }
        if (!have_fmt || !have_data) {
            if (error && error->empty()) {
                *error = path + " is missing fmt/data chunks";
            }
            break;
        }

        const size_t frame_count = data.size() / (2 * channels);
        out->samples.resize(frame_count);
        const auto* pcm = reinterpret_cast<const int16_t*>(data.data());
        if (channels == 1) {
            std::memcpy(out->samples.data(), pcm, frame_count * sizeof(int16_t));
        } else {
            for (size_t i = 0; i < frame_count; ++i) {
                int32_t acc = 0;
                for (uint16_t c = 0; c < channels; ++c) {
                    acc += pcm[i * channels + c];
                }
                out->samples[i] = static_cast<int16_t>(acc / channels);
            }
        }
        out->sample_rate = static_cast<int>(rate);
        ok = true;
    } while (false);

    std::fclose(f);
    return ok;
}

bool write_wav(const std::string& path, const int16_t* samples, size_t count, int sample_rate,
               std::string* error) {
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) {
        if (error) {
            *error = "cannot create " + path;
        }
        return false;
    }

    const uint32_t data_size = static_cast<uint32_t>(count * sizeof(int16_t));
    const uint32_t riff_size = 36 + data_size;
    const uint16_t channels = 1;
    const uint16_t bits = 16;
    const uint32_t byte_rate = static_cast<uint32_t>(sample_rate) * channels * (bits / 8);
    const uint16_t block_align = channels * (bits / 8);

    uint8_t header[44];
    std::memcpy(header, "RIFF", 4);
    std::memcpy(header + 8, "WAVEfmt ", 8);
    std::memcpy(header + 36, "data", 4);
    auto put_u32 = [&header](size_t offset, uint32_t value) {
        header[offset] = static_cast<uint8_t>(value & 0xFF);
        header[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
        header[offset + 2] = static_cast<uint8_t>((value >> 16) & 0xFF);
        header[offset + 3] = static_cast<uint8_t>((value >> 24) & 0xFF);
    };
    auto put_u16 = [&header](size_t offset, uint16_t value) {
        header[offset] = static_cast<uint8_t>(value & 0xFF);
        header[offset + 1] = static_cast<uint8_t>((value >> 8) & 0xFF);
    };
    put_u32(4, riff_size);
    put_u32(16, 16);          // fmt chunk size
    put_u16(20, 1);           // PCM
    put_u16(22, channels);
    put_u32(24, static_cast<uint32_t>(sample_rate));
    put_u32(28, byte_rate);
    put_u16(32, block_align);
    put_u16(34, bits);
    put_u32(40, data_size);

    const bool ok = std::fwrite(header, 1, sizeof(header), f) == sizeof(header) &&
                    (count == 0 || std::fwrite(samples, sizeof(int16_t), count, f) == count);
    std::fclose(f);
    if (!ok && error) {
        *error = "failed writing " + path;
    }
    return ok;
}

std::vector<int16_t> resample(const std::vector<int16_t>& samples, int from_rate, int to_rate) {
    if (from_rate == to_rate || samples.empty() || from_rate <= 0 || to_rate <= 0) {
        return samples;
    }
    const double ratio = static_cast<double>(to_rate) / from_rate;
    const size_t out_count = static_cast<size_t>(static_cast<double>(samples.size()) * ratio);
    std::vector<int16_t> out(out_count);
    for (size_t i = 0; i < out_count; ++i) {
        const double src = static_cast<double>(i) / ratio;
        const size_t i0 = static_cast<size_t>(src);
        const size_t i1 = std::min(i0 + 1, samples.size() - 1);
        const double frac = src - static_cast<double>(i0);
        out[i] = static_cast<int16_t>(samples[i0] * (1.0 - frac) + samples[i1] * frac);
    }
    return out;
}

std::vector<float> to_float(const std::vector<int16_t>& samples) {
    std::vector<float> out(samples.size());
    for (size_t i = 0; i < samples.size(); ++i) {
        out[i] = static_cast<float>(samples[i]) / 32768.0f;
    }
    return out;
}

std::vector<int16_t> to_int16(const float* samples, size_t count) {
    std::vector<int16_t> out(count);
    for (size_t i = 0; i < count; ++i) {
        const float clamped = std::clamp(samples[i], -1.0f, 1.0f);
        out[i] = static_cast<int16_t>(clamped * 32767.0f);
    }
    return out;
}

}  // namespace rcli::wav
