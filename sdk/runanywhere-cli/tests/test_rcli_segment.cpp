/**
 * @file test_rcli_segment.cpp
 * @brief rcli `segment` command tests — pure suite: no backend, no models, no
 *        network, no stream redirection.
 *
 * Covers exactly what is reachable for the `segment` command WITHOUT a
 * segmentation backend:
 *   - io/image_io.cpp read_ppm(): the CLI-owned input gate for `segment`.
 *   - io/image_io.cpp write_png(): the sibling encoder (smoke + guards).
 *   - The CLI11 parse/validation layer of `rcli segment` (fires before the
 *     callback), asserting the documented 0/1/2 exit-code contract for usage
 *     errors via src/app.cpp's exact catch ladder.
 *   - Structural wiring of register_segment (arg/flag spec) via introspection.
 *   - The documented --json output shape (JsonWriter sequence reproduced from
 *     cmd_segment.cpp's print_result; see the note on that test).
 *
 * run_segment(), resolve_model_path() and print_result() live in an anonymous
 * namespace in cmd_segment.cpp and are unreachable from here; anything that
 * needs to *execute* them requires a SEGMENT backend and belongs in a separate
 * backend-gated e2e test (cf. test_rcli_mlx_e2e.cpp).
 *
 * Uses the commons TestSuite harness so ctest drives it the same way as the
 * other rcli suites (--run-all / --test-<name>).
 */

#include "test_common.h"

#include <chrono>
#include <cstdint>
#include <filesystem>
#include <fstream>
#include <string>
#include <system_error>
#include <vector>

#include <CLI11.hpp>

#include "app.h"
#include "bootstrap.h"
#include "commands/commands.h"
#include "io/image_io.h"
#include "io/output.h"
#include "rac/features/segmentation/rac_segmentation_types.h"

namespace {

// Unique temp path (steady_clock stamp + a per-process counter), mirroring the
// uniqueness scheme in test_rcli_mlx_e2e.cpp. Does not create the file.
std::filesystem::path unique_temp_path(const std::string& stem, const std::string& ext) {
  static int counter = 0;
  const auto stamp = std::chrono::steady_clock::now().time_since_epoch().count();
  return std::filesystem::temp_directory_path() /
         (stem + "-" + std::to_string(stamp) + "-" + std::to_string(counter++) + ext);
}

// PPM/PNG payloads are binary — write raw bytes with no text translation.
bool write_binary_file(const std::filesystem::path& path, const std::string& bytes) {
  std::ofstream out(path, std::ios::binary);
  if (!out.is_open()) {
    return false;
  }
  if (!bytes.empty()) {
    out.write(bytes.data(), static_cast<std::streamsize>(bytes.size()));
  }
  return out.good();
}

// Remove a temp file on scope exit, even on an early return from a test.
struct TempFileGuard {
  std::filesystem::path path;
  explicit TempFileGuard(std::filesystem::path p) : path(std::move(p)) {}
  ~TempFileGuard() {
    std::error_code ec;
    std::filesystem::remove(path, ec);
  }
  TempFileGuard(const TempFileGuard&) = delete;
  TempFileGuard& operator=(const TempFileGuard&) = delete;
};

// -----------------------------------------------------------------------------
// read_ppm(): the CLI's dependency-free image decoder and the `segment` input
// gate. Highest-value coverage available in the pure suite (public, pure,
// model-free).
// -----------------------------------------------------------------------------
TestResult test_read_ppm() {
  TestResult result;
  result.test_name = "read_ppm";

  // (a) Valid P6 round-trips width/height and the exact RGB bytes.
  {
    const unsigned char pixels[6] = {10, 20, 30, 40, 50, 60};
    std::string content = "P6\n2 1\n255\n";
    content.append(reinterpret_cast<const char*>(pixels), sizeof(pixels));
    const auto path = unique_temp_path("rcli-seg-valid", ".ppm");
    TempFileGuard guard(path);
    if (!write_binary_file(path, content)) {
      result.details = "could not write valid PPM fixture";
      return result;
    }
    rcli::image::RgbImage img;
    std::string err;
    if (!rcli::image::read_ppm(path.string(), &img, &err)) {
      result.details = "valid P6 was rejected: " + err;
      return result;
    }
    if (img.width != 2 || img.height != 1 || img.rgb.size() != 6) {
      result.expected = "2x1 with 6 rgb bytes";
      result.actual = std::to_string(img.width) + "x" + std::to_string(img.height) + " with " +
                      std::to_string(img.rgb.size()) + " bytes";
      return result;
    }
    for (size_t i = 0; i < sizeof(pixels); ++i) {
      if (img.rgb[i] != pixels[i]) {
        result.details = "RGB payload mismatch at byte " + std::to_string(i);
        result.expected = std::to_string(pixels[i]);
        result.actual = std::to_string(img.rgb[i]);
        return result;
      }
    }
  }

  // (g) '#'-comment lines in the header are skipped (next_ppm_uint comment
  // branch) and parsing still succeeds.
  {
    const unsigned char pixels[6] = {1, 2, 3, 4, 5, 6};
    std::string content = "P6\n# rcli comment before dims\n2 1\n# and a trailing one\n255\n";
    content.append(reinterpret_cast<const char*>(pixels), sizeof(pixels));
    const auto path = unique_temp_path("rcli-seg-comment", ".ppm");
    TempFileGuard guard(path);
    if (!write_binary_file(path, content)) {
      result.details = "could not write commented PPM fixture";
      return result;
    }
    rcli::image::RgbImage img;
    std::string err;
    if (!rcli::image::read_ppm(path.string(), &img, &err)) {
      result.details = "commented P6 header was rejected: " + err;
      return result;
    }
    if (img.width != 2 || img.height != 1 || img.rgb.size() != 6 || img.rgb[0] != 1 ||
        img.rgb[5] != 6) {
      result.details = "comment-header parse produced the wrong image";
      return result;
    }
  }

  // (b)-(f) Malformed/format-violating inputs must fail with an actionable
  // error. Non-empty payloads keep the P3 case a real (if mis-tagged) pixmap.
  const std::string three(3, '\x01');
  const std::string six(6, '\x01');
  const std::string five(5, '\x01');
  struct Neg {
    std::string content;
    std::string want_substr;
    std::string note;
  };
  const Neg negatives[] = {
      {"P3\n1 1\n255\n" + three, "not a binary PPM (P6)", "wrong magic P3"},
      {"", "not a binary PPM (P6)", "empty file"},
      {"P6\n64\n", "malformed PPM header", "header ends before all three ints"},
      {"P6\nWxH\n255\n", "malformed PPM header", "non-numeric dimension"},
      {"P6\n2 1\n254\n" + six, "unsupported PPM", "maxval != 255"},
      {"P6\n0 1\n255\n", "unsupported PPM", "zero width"},
      {"P6\n1 0\n255\n", "unsupported PPM", "zero height"},
      {"P6\n4 4\n255\n" + five, "truncated PPM pixel data", "payload shorter than header promises"},
  };
  for (const Neg& n : negatives) {
    const auto path = unique_temp_path("rcli-seg-neg", ".ppm");
    TempFileGuard guard(path);
    if (!write_binary_file(path, n.content)) {
      result.details = "could not write negative fixture: " + n.note;
      return result;
    }
    rcli::image::RgbImage img;
    std::string err;
    if (rcli::image::read_ppm(path.string(), &img, &err)) {
      result.details = "expected failure but read_ppm succeeded: " + n.note;
      return result;
    }
    if (err.find(n.want_substr) == std::string::npos) {
      result.details = "wrong error for: " + n.note;
      result.expected = "error containing \"" + n.want_substr + "\"";
      result.actual = err;
      return result;
    }
  }

  // (h) Nonexistent path → false with "cannot open" (file never created).
  {
    const std::string missing = unique_temp_path("rcli-seg-missing", ".ppm").string();
    rcli::image::RgbImage img;
    std::string err;
    if (rcli::image::read_ppm(missing, &img, &err)) {
      result.details = "read_ppm succeeded on a nonexistent path";
      return result;
    }
    if (err.find("cannot open") == std::string::npos) {
      result.expected = "error containing \"cannot open\"";
      result.actual = err;
      return result;
    }
  }

  result.passed = true;
  return result;
}

// -----------------------------------------------------------------------------
// write_png(): public sibling encoder in io/image_io.h. Smoke + input guards.
// -----------------------------------------------------------------------------
TestResult test_write_png_smoke() {
  TestResult result;
  result.test_name = "write_png_smoke";

  const int width = 2;
  const int height = 2;
  std::vector<uint8_t> rgba(static_cast<size_t>(width) * height * 4);
  for (size_t i = 0; i < rgba.size(); ++i) {
    rgba[i] = static_cast<uint8_t>(i * 7 + 3);
  }

  const auto path = unique_temp_path("rcli-seg-png", ".png");
  TempFileGuard guard(path);
  std::string err;
  if (!rcli::image::write_png(path.string(), rgba.data(), width, height, &err)) {
    result.details = "write_png failed on a valid RGBA buffer: " + err;
    return result;
  }

  std::ifstream in(path, std::ios::binary);
  if (!in.is_open()) {
    result.details = "written PNG could not be reopened";
    return result;
  }
  unsigned char header[8] = {0};
  in.read(reinterpret_cast<char*>(header), static_cast<std::streamsize>(sizeof(header)));
  if (in.gcount() != static_cast<std::streamsize>(sizeof(header))) {
    result.details = "PNG shorter than its 8-byte signature";
    return result;
  }
  const unsigned char signature[8] = {137, 80, 78, 71, 13, 10, 26, 10};
  for (size_t i = 0; i < sizeof(signature); ++i) {
    if (header[i] != signature[i]) {
      result.details = "PNG signature mismatch at byte " + std::to_string(i);
      result.expected = std::to_string(signature[i]);
      result.actual = std::to_string(header[i]);
      return result;
    }
  }

  // width <= 0 and null data are rejected before any file is opened.
  const std::string throwaway = unique_temp_path("rcli-seg-png-bad", ".png").string();
  std::string err_dim;
  if (rcli::image::write_png(throwaway, rgba.data(), 0, height, &err_dim) ||
      err_dim.find("invalid image dimensions or data") == std::string::npos) {
    result.details = "width<=0 must fail with 'invalid image dimensions or data'";
    result.actual = err_dim;
    return result;
  }
  std::string err_null;
  if (rcli::image::write_png(throwaway, nullptr, width, height, &err_null) ||
      err_null.find("invalid image dimensions or data") == std::string::npos) {
    result.details = "null data must fail with 'invalid image dimensions or data'";
    result.actual = err_null;
    return result;
  }

  result.passed = true;
  return result;
}

// -----------------------------------------------------------------------------
// Exit-code contract for `segment` usage errors.
//
// Builds the real app via rcli::configure_app (which adds the global flags AND
// every subcommand, including segment) and maps the thrown CLI11 exception to a
// process exit code using the EXACT catch ladder from src/app.cpp:
//   RuntimeError -> get_exit_code() or 1
//   ParseError   -> app.exit(e) (usage to stderr), then 2
//   std::exception -> 1
// No process is exec'd/forked — the pure suite never redirects streams.
//
// All cases below throw during parse (RequiredError / ValidationError /
// ExtrasError, all ParseError subclasses) BEFORE the top-level run_callback()
// fires the segment callback, so run_segment/bootstrap/backend are never
// entered.
// -----------------------------------------------------------------------------
int segment_exit_code(const std::vector<std::string>& args) {
  rcli::GlobalOptions options;
  CLI::App app{"RunAnywhere on-device AI CLI — run, manage and serve local models"};
  rcli::configure_app(app, options);

  std::vector<std::string> mutable_args = args;
  std::vector<char*> argv;
  argv.reserve(mutable_args.size());
  for (std::string& arg : mutable_args) {
    argv.push_back(arg.data());
  }

  try {
    app.parse(static_cast<int>(argv.size()), argv.data());
    return 0;
  } catch (const CLI::RuntimeError& e) {
    return (e.get_exit_code() != 0) ? e.get_exit_code() : 1;
  } catch (const CLI::ParseError& e) {
    app.exit(e);  // prints the usage message to stderr, mirroring src/app.cpp
    return 2;
  } catch (const std::exception&) {
    return 1;
  }
}

TestResult test_segment_usage_errors() {
  TestResult result;
  result.test_name = "segment_usage_errors";

  // A real existing PPM isolates the "missing --model" and "extra flag" cases
  // from the positional's ->check(CLI::ExistingFile) validation.
  const unsigned char pixels[3] = {9, 9, 9};
  std::string ppm_content = "P6\n1 1\n255\n";
  ppm_content.append(reinterpret_cast<const char*>(pixels), sizeof(pixels));
  const auto ppm = unique_temp_path("rcli-seg-usage", ".ppm");
  TempFileGuard guard(ppm);
  if (!write_binary_file(ppm, ppm_content)) {
    result.details = "could not write usage-test PPM fixture";
    return result;
  }

  const std::string existing = ppm.string();
  const std::string missing = unique_temp_path("rcli-seg-usage-missing", ".ppm").string();

  struct Case {
    std::vector<std::string> args;
    int expected;
    std::string note;
  };
  const Case cases[] = {
      {{"rcli", "segment"}, 2, "image + --model both missing (RequiredError -> 2)"},
      {{"rcli", "segment", "--model", "seg-model"}, 2, "image missing (RequiredError -> 2)"},
      {{"rcli", "segment", existing}, 2, "--model missing (RequiredError -> 2)"},
      {{"rcli", "segment", missing, "--model", "seg-model"}, 2,
       "image not on disk (ExistingFile -> ValidationError -> 2)"},
      {{"rcli", "segment", existing, "--model", "seg-model", "--bogus"}, 2,
       "unknown flag (ExtrasError -> 2)"},
  };
  for (const Case& c : cases) {
    const int code = segment_exit_code(c.args);
    if (code != c.expected) {
      result.details = "wrong exit code for: " + c.note;
      result.expected = std::to_string(c.expected);
      result.actual = std::to_string(code);
      return result;
    }
  }

  result.passed = true;
  return result;
}

// -----------------------------------------------------------------------------
// Structural wiring of register_segment — positive spec assertion with ZERO
// callback execution (the only way to verify the happy-path option spec without
// a segmentation model). Uses CLI11 introspection on the registered subcommand.
// -----------------------------------------------------------------------------
TestResult test_segment_option_spec() {
  TestResult result;
  result.test_name = "segment_option_spec";

  rcli::GlobalOptions options;
  CLI::App app{"RunAnywhere on-device AI CLI — run, manage and serve local models"};
  rcli::configure_app(app, options);

  CLI::App* seg = app.get_subcommand_no_throw("segment");
  if (seg == nullptr) {
    result.details = "segment subcommand not registered by configure_app";
    return result;
  }
  const std::string want_desc = "Semantic segmentation of an image (per-class mask summary)";
  if (seg->get_description() != want_desc) {
    result.expected = want_desc;
    result.actual = seg->get_description();
    return result;
  }

  CLI::Option* image = seg->get_option_no_throw("image");
  if (image == nullptr) {
    result.details = "positional 'image' option missing";
    return result;
  }
  if (!image->get_required()) {
    result.details = "'image' positional must be required";
    return result;
  }

  CLI::Option* model_long = seg->get_option_no_throw("--model");
  if (model_long == nullptr) {
    result.details = "'--model' option missing";
    return result;
  }
  if (!model_long->get_required()) {
    result.details = "'--model' must be required";
    return result;
  }

  CLI::Option* model_short = seg->get_option_no_throw("-m");
  if (model_short != model_long) {
    result.details = "'-m' must resolve to the same Option as '--model'";
    return result;
  }

  result.passed = true;
  return result;
}

// -----------------------------------------------------------------------------
// --json output-shape guard (mirrors test_json_writer_shape).
//
// print_result() lives in an anonymous namespace in cmd_segment.cpp and cannot
// be called here, so this reproduces the EXACT JsonWriter sequence it emits for
// the --json branch and asserts the serialized string. It is fed real
// rac_segmentation_result_t / rac_segmentation_class_summary_t structs so the
// test stays coupled to the actual field names/types.
//
// NOTE: this LOCKS the documented --json contract (one flat JSON document) but
// does NOT execute print_result(). Genuine coverage of print_result /
// --no-progress / the human table + "(no classes)" + verbose "(N ms)" rendering
// requires driving run_segment(), which needs a SEGMENT backend and belongs in
// a separate backend-gated e2e test.
// -----------------------------------------------------------------------------
TestResult test_segment_json_shape() {
  TestResult result;
  result.test_name = "segment_json_shape";

  char model_id_buf[] = "segformer-b0-ade20k";
  char label_background[] = "background";
  char label_person[] = "person";

  rac_segmentation_class_summary_t classes[2] = {};
  classes[0].class_id = 0;
  classes[0].pixel_count = 200000;
  classes[0].fraction = 0.75f;  // exactly representable -> %g emits "0.75"
  classes[0].label = label_background;
  classes[1].class_id = 15;
  classes[1].pixel_count = 67000;
  classes[1].fraction = 0.25f;  // exactly representable -> %g emits "0.25"
  classes[1].label = label_person;

  rac_segmentation_result_t seg_result = {};
  seg_result.width = 640;
  seg_result.height = 480;
  seg_result.class_summaries = classes;
  seg_result.class_summary_count = 2;
  seg_result.processing_time_ms = 12;
  seg_result.model_id = model_id_buf;
  // Not freed: every pointer above is stack/literal, not malloc-owned.

  const std::string model_ref = "unused-fallback-ref";  // model_id is non-null

  // Reproduced verbatim from cmd_segment.cpp print_result()'s --json branch.
  rcli::out::JsonWriter json;
  json.begin_object()
      .field("model", seg_result.model_id ? seg_result.model_id : model_ref)
      .field("width", static_cast<int64_t>(seg_result.width))
      .field("height", static_cast<int64_t>(seg_result.height))
      .field("class_count", static_cast<int64_t>(seg_result.class_summary_count))
      .field("processing_time_ms", static_cast<int64_t>(seg_result.processing_time_ms));
  json.begin_array("classes");
  for (size_t i = 0; i < seg_result.class_summary_count; ++i) {
    const rac_segmentation_class_summary_t& cls = seg_result.class_summaries[i];
    json.begin_array_object()
        .field("class_id", static_cast<int64_t>(cls.class_id))
        .field("label", cls.label ? cls.label : "")
        .field("pixel_count", static_cast<int64_t>(cls.pixel_count))
        .field("fraction", static_cast<double>(cls.fraction))
        .end_object();
  }
  json.end_array().end_object();

  const std::string expected =
      R"({"model":"segformer-b0-ade20k","width":640,"height":480,"class_count":2,)"
      R"("processing_time_ms":12,"classes":[)"
      R"({"class_id":0,"label":"background","pixel_count":200000,"fraction":0.75},)"
      R"({"class_id":15,"label":"person","pixel_count":67000,"fraction":0.25}]})";
  if (json.str() != expected) {
    result.expected = expected;
    result.actual = json.str();
    return result;
  }

  result.passed = true;
  return result;
}

}  // namespace

int main(int argc, char** argv) {
  TestSuite suite("rcli_segment");
  suite.add("read_ppm", test_read_ppm);
  suite.add("write_png_smoke", test_write_png_smoke);
  suite.add("segment_usage_errors", test_segment_usage_errors);
  suite.add("segment_option_spec", test_segment_option_spec);
  suite.add("segment_json_shape", test_segment_json_shape);
  return suite.run(argc, argv);
}
