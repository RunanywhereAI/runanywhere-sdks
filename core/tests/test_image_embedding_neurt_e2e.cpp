/**
 * @file test_image_embedding_neurt_e2e.cpp
 * @brief End-to-end proof that EMBED_IMAGE is reachable through the PUBLIC C API.
 *
 * The point of this file is the word "public". `RAC_PRIMITIVE_EMBED_IMAGE` and NeuRT's
 * `image_embedding_ops` slot both existed before `rac_image_embedding_service.cpp` did, and the
 * registry could already *find* the slot — but no caller could reach it, because there was no
 * service factory, no create, and no embed. A vtable slot nothing can call is not a feature, and
 * `test_plugin_entry_neurt` (which only inspects the vtable's SHAPE) would never have noticed.
 *
 * So this test deliberately goes through the same entry points a platform SDK does:
 *   rac_image_embedding_create -> _initialize -> _embed -> rac_embeddings_result_free.
 *
 * Env-gated on a real bundle because a vision tower is 400 MB of Core ML. When the bundle is
 * absent it exits 77, which CMakeLists registers as SKIP_RETURN_CODE, so CTest reports the test
 * as SKIPPED rather than passed.
 *
 * That distinction is not pedantry. `test_stt_neurt_e2e` returns 0 on the same condition, so it
 * has been reported as passing for as long as it has existed while never once running -- and the
 * first time it was handed a real bundle it failed immediately, because every published ASR
 * bundle is missing the manifest blocks the runtime requires. A test that cannot fail is not a
 * test, and a green tick that means "no bundle" is worse than a red one.
 */
#include <cmath>
#include <cstdio>
#include <cstdlib>
#include <cstring>
#include <vector>

#include "rac/features/embeddings/rac_image_embedding_service.h"
#include "rac/plugin/rac_plugin_entry.h"
#include "rac/plugin/rac_plugin_entry_neurt.h"
#include "rac/plugin/rac_primitive.h"

namespace {

int g_fail = 0;

void check(bool ok, const char* what) {
    std::fprintf(stdout, "  %s %s\n", ok ? "ok:" : "FAIL:", what);
    if (!ok) {
        ++g_fail;
    }
}

/**
 * A deterministic 256x256 RGB8 test image: two diagonal colour fields.
 *
 * Synthetic on purpose. The claim under test is "pixels reach the tower and a real vector comes
 * back", not "SigLIP recognises a cat" — and a synthetic image keeps the test hermetic. The
 * numeric-fidelity claim is carried by neurun's own gate against the SigLIP oracle.
 */
std::vector<uint8_t> make_image(uint32_t w, uint32_t h, bool swap) {
    std::vector<uint8_t> px(static_cast<size_t>(w) * h * 3);
    for (uint32_t y = 0; y < h; ++y) {
        for (uint32_t x = 0; x < w; ++x) {
            const size_t i = (static_cast<size_t>(y) * w + x) * 3;
            const uint8_t a = static_cast<uint8_t>((x * 255) / (w - 1));
            const uint8_t b = static_cast<uint8_t>((y * 255) / (h - 1));
            px[i + 0] = swap ? b : a;
            px[i + 1] = static_cast<uint8_t>(255 - a);
            px[i + 2] = swap ? a : b;
        }
    }
    return px;
}

}  // namespace

int main() {
    std::fprintf(stdout, "test_image_embedding_neurt_e2e\n");

    const char* bundle = std::getenv("RAC_TEST_NEURT_IMAGE_EMBED_BUNDLE");
    if (!bundle || bundle[0] == '\0') {
        std::fprintf(stdout,
                     "SKIP: set RAC_TEST_NEURT_IMAGE_EMBED_BUNDLE to a SigLIP2 _ANE bundle\n");
        return 77;   // CTest SKIP_RETURN_CODE -- reported as skipped, never as passed
    }

    const rac_engine_vtable_t* vt = rac_plugin_entry_neurt();
    check(vt != nullptr, "neurt plugin entry resolves");
    if (!vt) {
        return 1;
    }
    check(vt->image_embedding_ops != nullptr, "neurt fills image_embedding_ops");
    check(rac_plugin_register(vt) == RAC_SUCCESS, "neurt registers");
    check(rac_plugin_find(RAC_PRIMITIVE_EMBED_IMAGE) != nullptr,
          "registry routes EMBED_IMAGE after registration");

    rac_handle_t handle = nullptr;
    rac_result_t rc = rac_image_embedding_create(bundle, &handle);
    check(rc == RAC_SUCCESS && handle != nullptr, "rac_image_embedding_create");
    if (rc != RAC_SUCCESS || !handle) {
        std::fprintf(stderr, "  create rc=%d\n", static_cast<int>(rc));
        return 1;
    }

    rc = rac_image_embedding_initialize(handle, bundle);
    check(rc == RAC_SUCCESS, "rac_image_embedding_initialize");
    if (rc != RAC_SUCCESS) {
        std::fprintf(stderr, "  initialize rc=%d\n", static_cast<int>(rc));
        rac_image_embedding_destroy(handle);
        return 1;
    }

    // A null/zero image must be REFUSED, not embedded. An all-zero buffer read as pixels produces
    // a perfectly well-formed vector, so this can only be caught by validating the input.
    rac_image_embedding_input_t bad{};
    bad.format = RAC_IMAGE_EMBEDDING_FORMAT_RGB8;
    bad.pixels = nullptr;
    bad.width = 256;
    bad.height = 256;
    rac_embeddings_result_t junk{};
    // INVALID_ARGUMENT, not NULL_POINTER: the struct itself is present, its contents are not.
    check(rac_image_embedding_embed(handle, &bad, &junk) == RAC_ERROR_INVALID_ARGUMENT,
          "null pixel buffer is refused");

    rac_image_embedding_input_t zero_dim{};
    zero_dim.format = RAC_IMAGE_EMBEDDING_FORMAT_RGB8;
    const uint8_t one_px[3] = {1, 2, 3};
    zero_dim.pixels = one_px;
    zero_dim.width = 0;
    zero_dim.height = 8;
    check(rac_image_embedding_embed(handle, &zero_dim, &junk) == RAC_ERROR_INVALID_ARGUMENT,
          "zero width is refused");

    const uint32_t kW = 256, kH = 256;
    std::vector<uint8_t> pixels_a = make_image(kW, kH, false);
    std::vector<uint8_t> pixels_b = make_image(kW, kH, true);

    auto embed = [&](const std::vector<uint8_t>& px, std::vector<float>* out) -> bool {
        rac_image_embedding_input_t in{};
        in.format = RAC_IMAGE_EMBEDDING_FORMAT_RGB8;
        in.pixels = px.data();
        in.width = kW;
        in.height = kH;
        rac_embeddings_result_t res{};
        const rac_result_t r = rac_image_embedding_embed(handle, &in, &res);
        if (r != RAC_SUCCESS || res.num_embeddings != 1 || !res.embeddings ||
            res.embeddings[0].dimension == 0) {
            std::fprintf(stderr, "  embed rc=%d num=%zu\n", static_cast<int>(r),
                         static_cast<size_t>(res.num_embeddings));
            rac_embeddings_result_free(&res);
            return false;
        }
        out->assign(res.embeddings[0].data,
                    res.embeddings[0].data + res.embeddings[0].dimension);
        rac_embeddings_result_free(&res);
        return true;
    };

    std::vector<float> va, vb;
    check(embed(pixels_a, &va), "embed image A through the public API");
    check(embed(pixels_b, &vb), "embed image B through the public API");

    if (!va.empty() && !vb.empty()) {
        check(va.size() == vb.size(), "both images produce the same vector width");

        // Not all-zero and not NaN: the two failures a broken tower actually produces.
        double norm = 0.0;
        bool finite = true;
        for (float v : va) {
            finite = finite && std::isfinite(v);
            norm += static_cast<double>(v) * v;
        }
        norm = std::sqrt(norm);
        std::fprintf(stdout, "  dim=%zu |v|=%.6f\n", va.size(), norm);
        check(finite, "vector is finite (no NaN/Inf)");
        check(norm > 1e-3, "vector is not all zeros");

        // Two DIFFERENT images must not produce the same vector. This is the assertion that
        // catches a tower whose input binding never actually reads the caller's pixels — the
        // failure mode where everything returns a plausible, constant embedding.
        double diff = 0.0;
        for (size_t i = 0; i < va.size(); ++i) {
            diff += std::fabs(static_cast<double>(va[i]) - vb[i]);
        }
        std::fprintf(stdout, "  L1(A,B)=%.6f\n", diff);
        check(diff > 1e-4, "different images produce different vectors");
    }

    rac_embeddings_info_t info{};
    if (rac_image_embedding_get_info(handle, &info) == RAC_SUCCESS) {
        std::fprintf(stdout, "  info: ready=%d dim=%zu\n", static_cast<int>(info.is_ready),
                     static_cast<size_t>(info.dimension));
    }

    check(rac_image_embedding_cleanup(handle) == RAC_SUCCESS, "cleanup");
    rac_image_embedding_destroy(handle);

    std::fprintf(stdout, "%s\n", g_fail == 0 ? "PASS" : "FAIL");
    return g_fail == 0 ? 0 : 1;
}
