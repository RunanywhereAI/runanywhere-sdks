#include "io/wav_io.h"

#include <cstdio>
#include <cstring>
#include <vector>

#include "rac/core/rac_audio_utils.h"
#include "rac/core/rac_types.h"

namespace rcli::wav {

namespace {

uint32_t read_u32(const uint8_t* p) {
    return static_cast<uint32_t>(p[0]) | (static_cast<uint32_t>(p[1]) << 8) |
           (static_cast<uint32_t>(p[2]) << 16) | (static_cast<uint32_t>(p[3]) << 24);
}

uint16_t read_u16(const uint8_t* p) {
    return static_cast<uint16_t>(p[0] | (p[1] << 8));
}

bool write_bytes(const std::string& path, const void* data, size_t size, std::string* error) {
    FILE* f = std::fopen(path.c_str(), "wb");
    if (!f) {
        if (error) {
            *error = "cannot create " + path;
        }
        return false;
    }
    const bool ok = size == 0 || std::fwrite(data, 1, size, f) == size;
    std::fclose(f);
    if (!ok && error) {
        *error = "failed writing " + path;
    }
    return ok;
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
    if (samples == nullptr || count == 0 || sample_rate <= 0) {
        if (error) {
            *error = "invalid PCM16 input for " + path;
        }
        return false;
    }

    void* wav_data = nullptr;
    size_t wav_size = 0;
    const rac_result_t rc =
        rac_audio_int16_to_wav(samples, count * sizeof(int16_t), sample_rate, &wav_data, &wav_size);
    if (rc != RAC_SUCCESS || wav_data == nullptr || wav_size == 0) {
        if (error) {
            *error = "rac_audio_int16_to_wav failed for " + path;
        }
        return false;
    }

    const bool ok = write_bytes(path, wav_data, wav_size, error);
    rac_free(wav_data);
    return ok;
}

bool write_wav_f32(const std::string& path, const float* samples, size_t count, int sample_rate,
                   std::string* error) {
    if (samples == nullptr || count == 0 || sample_rate <= 0) {
        if (error) {
            *error = "invalid float32 PCM input for " + path;
        }
        return false;
    }

    void* wav_data = nullptr;
    size_t wav_size = 0;
    const rac_result_t rc =
        rac_audio_float32_to_wav(samples, count * sizeof(float), sample_rate, &wav_data, &wav_size);
    if (rc != RAC_SUCCESS || wav_data == nullptr || wav_size == 0) {
        if (error) {
            *error = "rac_audio_float32_to_wav failed for " + path;
        }
        return false;
    }

    const bool ok = write_bytes(path, wav_data, wav_size, error);
    rac_free(wav_data);
    return ok;
}

std::vector<int16_t> resample(const std::vector<int16_t>& samples, int from_rate, int to_rate) {
    if (samples.empty() || from_rate == to_rate) {
        return samples;
    }

    std::vector<float> in_f(samples.size());
    if (rac_audio_pcm16_to_float32(samples.data(), samples.size(), in_f.data()) != RAC_SUCCESS) {
        return {};
    }

    float* out_f = nullptr;
    size_t out_frames = 0;
    const rac_result_t rc =
        rac_audio_resample_f32(in_f.data(), in_f.size(), from_rate, to_rate, &out_f, &out_frames);
    if (rc != RAC_SUCCESS) {
        return {};
    }
    if (out_frames == 0) {
        rac_free(out_f);
        return {};
    }

    std::vector<int16_t> out(out_frames);
    const rac_result_t qrc = rac_audio_float32_to_pcm16(out_f, out_frames, out.data());
    rac_free(out_f);
    if (qrc != RAC_SUCCESS) {
        return {};
    }
    return out;
}

std::vector<float> to_float(const std::vector<int16_t>& samples) {
    std::vector<float> out(samples.size());
    if (!samples.empty()) {
        (void)rac_audio_pcm16_to_float32(samples.data(), samples.size(), out.data());
    }
    return out;
}

}  // namespace rcli::wav
