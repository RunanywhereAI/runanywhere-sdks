#include "device_info.h"

#include <cstdint>
#include <cstdlib>
#include <string>
#include <vector>

#include "rac/core/rac_sdk_state.h"
#include "rac/foundation/rac_sha256.h"
#include "rac/infrastructure/device/rac_device_identity.h"
#include "rac/infrastructure/device/rac_device_manager.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"
#include "rac/infrastructure/network/rac_auth_manager.h"
#include "rac/infrastructure/network/rac_endpoints.h"
#include "rac/infrastructure/network/rac_environment.h"

#if defined(_WIN32)
#include <windows.h>
#elif defined(__APPLE__)
#include <CoreFoundation/CoreFoundation.h>
#include <IOKit/ps/IOPowerSources.h>
#include <IOKit/ps/IOPSKeys.h>
#include <mach/mach.h>
#include <sys/sysctl.h>
#include <sys/utsname.h>
#include <unistd.h>
#else
#include <sys/utsname.h>
#include <unistd.h>

#include <filesystem>
#include <fstream>
#endif

namespace rcli {

namespace {

struct DeviceInfoState {
  std::string device_id;
  std::string model;
  std::string name;
  std::string platform;
  std::string os_version;
  std::string form_factor;
  std::string architecture;
  std::string chip;
  std::string gpu_family;
  std::string battery_state;
  std::string fingerprint;
  double battery_level = -1.0;
  int64_t total_memory = 0;
  int64_t available_memory = 0;
  int32_t core_count = 0;
  int32_t performance_cores = 0;
  int32_t efficiency_cores = 0;
  bool registered = false;
  std::string http_body;
  std::string http_error;
};

DeviceInfoState &state() {
  static DeviceInfoState s;
  return s;
}

std::string trim(const std::string &value) {
  const char *ws = " \t\r\n";
  const std::size_t begin = value.find_first_not_of(ws);
  if (begin == std::string::npos) {
    return {};
  }
  const std::size_t end = value.find_last_not_of(ws);
  return value.substr(begin, end - begin + 1);
}

#if !defined(_WIN32) && !defined(__APPLE__)

std::string read_first_line(const std::string &path) {
  std::ifstream file(path);
  std::string line;
  if (file.is_open() && std::getline(file, line)) {
    return trim(line);
  }
  return {};
}

std::string os_release_pretty_name() {
  std::ifstream file("/etc/os-release");
  std::string line;
  while (file.is_open() && std::getline(file, line)) {
    const std::string key = "PRETTY_NAME=";
    if (line.compare(0, key.size(), key) == 0) {
      std::string value = trim(line.substr(key.size()));
      if (value.size() >= 2 && value.front() == '"' && value.back() == '"') {
        value = value.substr(1, value.size() - 2);
      }
      return value;
    }
  }
  return {};
}

std::string cpuinfo_model_name() {
  std::ifstream file("/proc/cpuinfo");
  std::string line;
  while (file.is_open() && std::getline(file, line)) {
    if (line.compare(0, 10, "model name") == 0 ||
        line.compare(0, 8, "Hardware") == 0) {
      const std::size_t colon = line.find(':');
      if (colon != std::string::npos) {
        return trim(line.substr(colon + 1));
      }
    }
  }
  return {};
}

int64_t meminfo_bytes(const char *key) {
  std::ifstream file("/proc/meminfo");
  std::string line;
  const std::string prefix = std::string(key) + ":";
  while (file.is_open() && std::getline(file, line)) {
    if (line.compare(0, prefix.size(), prefix) == 0) {
      const int64_t kib = std::strtoll(line.c_str() + prefix.size(), nullptr, 10);
      return kib > 0 ? kib * 1024 : 0;
    }
  }
  return 0;
}

bool has_battery_dir(std::string *battery_path) {
  namespace fs = std::filesystem;
  std::error_code ec;
  for (const auto &entry : fs::directory_iterator("/sys/class/power_supply", ec)) {
    const std::string name = entry.path().filename().string();
    if (name.compare(0, 3, "BAT") == 0) {
      if (battery_path) {
        *battery_path = entry.path().string();
      }
      return true;
    }
  }
  return false;
}

std::string linux_gpu_family() {
  std::error_code ec;
  if (std::filesystem::exists("/proc/driver/nvidia/version", ec)) {
    return "nvidia";
  }
  namespace fs = std::filesystem;
  for (const auto &entry : fs::directory_iterator("/sys/class/drm", ec)) {
    const std::string card = entry.path().filename().string();
    if (card.compare(0, 4, "card") != 0) {
      continue;
    }
    std::ifstream uevent(entry.path() / "device/uevent");
    std::string line;
    while (uevent.is_open() && std::getline(uevent, line)) {
      if (line.compare(0, 7, "DRIVER=") != 0) {
        continue;
      }
      const std::string driver = trim(line.substr(7));
      if (driver == "amdgpu" || driver == "radeon") {
        return "amd";
      }
      if (driver == "i915" || driver == "xe") {
        return "intel";
      }
      if (driver == "nvidia" || driver == "nouveau") {
        return "nvidia";
      }
    }
  }
  return "unknown";
}

void linux_core_topology(int32_t core_count, int32_t *perf, int32_t *eff) {
  std::vector<int64_t> max_freqs;
  max_freqs.reserve(static_cast<std::size_t>(core_count));
  int64_t highest = 0;
  for (int32_t cpu = 0; cpu < core_count; ++cpu) {
    const std::string path = "/sys/devices/system/cpu/cpu" + std::to_string(cpu) +
                             "/cpufreq/cpuinfo_max_freq";
    const std::string value = read_first_line(path);
    const int64_t freq = value.empty() ? 0 : std::strtoll(value.c_str(), nullptr, 10);
    if (freq <= 0) {
      *perf = core_count;
      *eff = 0;
      return;
    }
    max_freqs.push_back(freq);
    highest = freq > highest ? freq : highest;
  }
  int32_t performance = 0;
  for (const int64_t freq : max_freqs) {
    if (freq == highest) {
      ++performance;
    }
  }
  if (performance == 0 || performance == core_count) {
    *perf = core_count;
    *eff = 0;
    return;
  }
  *perf = performance;
  *eff = core_count - performance;
}

void collect_device_info(DeviceInfoState &info) {
  info.platform = "linux";

  info.model = read_first_line("/sys/devices/virtual/dmi/id/product_name");
  if (info.model.empty()) {
    info.model = "Linux Desktop";
  }

  info.name = read_first_line("/etc/hostname");
  if (info.name.empty()) {
    char hostname[256] = {};
    if (gethostname(hostname, sizeof(hostname) - 1) == 0 && hostname[0] != '\0') {
      info.name = hostname;
    }
  }
  if (info.name.empty()) {
    info.name = info.model;
  }

  info.os_version = os_release_pretty_name();
  if (info.os_version.empty()) {
    info.os_version = "Linux";
  }

  info.chip = cpuinfo_model_name();
  if (info.chip.empty()) {
    info.chip = "unknown";
  }

  info.total_memory = meminfo_bytes("MemTotal");
  info.available_memory = meminfo_bytes("MemAvailable");

  const long online = sysconf(_SC_NPROCESSORS_ONLN);
  info.core_count = online > 0 ? static_cast<int32_t>(online) : 1;
  linux_core_topology(info.core_count, &info.performance_cores,
                      &info.efficiency_cores);

  struct utsname uts = {};
  info.architecture = (uname(&uts) == 0 && uts.machine[0] != '\0')
                          ? uts.machine
                          : "unknown";

  std::string battery_path;
  if (has_battery_dir(&battery_path)) {
    info.form_factor = "laptop";
    const std::string capacity = read_first_line(battery_path + "/capacity");
    if (!capacity.empty()) {
      const long percent = std::strtol(capacity.c_str(), nullptr, 10);
      if (percent >= 0 && percent <= 100) {
        info.battery_level = static_cast<double>(percent) / 100.0;
      }
    }
    const std::string status = read_first_line(battery_path + "/status");
    if (info.battery_level >= 0.0 && !status.empty()) {
      if (status == "Full") {
        info.battery_state = "full";
      } else if (status == "Charging") {
        info.battery_state = "charging";
      } else {
        info.battery_state = "unplugged";
      }
    }
  } else {
    info.form_factor = "desktop";
  }

  info.gpu_family = linux_gpu_family();
}

#elif defined(__APPLE__)

std::string sysctl_string(const char *key) {
  std::size_t size = 0;
  if (sysctlbyname(key, nullptr, &size, nullptr, 0) != 0 || size == 0) {
    return {};
  }
  std::string value(size, '\0');
  if (sysctlbyname(key, value.data(), &size, nullptr, 0) != 0) {
    return {};
  }
  value.resize(value.find('\0') != std::string::npos ? value.find('\0')
                                                     : value.size());
  return trim(value);
}

int64_t sysctl_i64(const char *key) {
  int64_t value = 0;
  std::size_t size = sizeof(value);
  if (sysctlbyname(key, &value, &size, nullptr, 0) != 0) {
    return 0;
  }
  return value;
}

int64_t macos_available_memory_bytes() {
  mach_port_t host = mach_host_self();
  vm_statistics64_data_t stats = {};
  mach_msg_type_number_t count = HOST_VM_INFO64_COUNT;
  if (host_statistics64(host, HOST_VM_INFO64,
                        reinterpret_cast<host_info64_t>(&stats),
                        &count) != KERN_SUCCESS) {
    return 0;
  }
  const int64_t page_size = static_cast<int64_t>(sysctl_i64("hw.pagesize"));
  if (page_size <= 0) {
    return 0;
  }
  // Free + speculative pages ≈ "available" for telemetry (not wired/compressed).
  const int64_t free_pages =
      static_cast<int64_t>(stats.free_count) +
      static_cast<int64_t>(stats.purgeable_count);
  return free_pages * page_size;
}

void macos_sample_battery(DeviceInfoState &info) {
  // Desktop Macs (Studio/Mini/iMac) have no battery → leave level=-1 (null).
  // Laptops expose IOPowerSources; sample real capacity rather than inventing 0.
  CFTypeRef blob = IOPSCopyPowerSourcesInfo();
  if (blob == nullptr) {
    return;
  }
  CFArrayRef list = IOPSCopyPowerSourcesList(blob);
  if (list == nullptr) {
    CFRelease(blob);
    return;
  }

  const CFIndex count = CFArrayGetCount(list);
  for (CFIndex i = 0; i < count; ++i) {
    CFTypeRef ps = CFArrayGetValueAtIndex(list, i);
    CFDictionaryRef desc = IOPSGetPowerSourceDescription(blob, ps);
    if (desc == nullptr) {
      continue;
    }
    auto number_for = [&](CFStringRef key) -> double {
      const auto *num =
          static_cast<const CFNumberRef>(CFDictionaryGetValue(desc, key));
      if (num == nullptr) {
        return -1.0;
      }
      double value = -1.0;
      return CFNumberGetValue(num, kCFNumberDoubleType, &value) ? value : -1.0;
    };

    const double current = number_for(CFSTR(kIOPSCurrentCapacityKey));
    const double max_cap = number_for(CFSTR(kIOPSMaxCapacityKey));
    if (current < 0.0) {
      continue;
    }
    // Capacity is usually already a percent (0–100); normalize to 0–1.
    double level = current;
    if (max_cap > 0.0 && max_cap != 100.0) {
      level = (current / max_cap) * 100.0;
    }
    if (level > 1.0) {
      level /= 100.0;
    }
    if (level < 0.0 || level > 1.0) {
      continue;
    }

    info.battery_level = level;
    info.form_factor = "laptop";

    const auto *state = static_cast<const CFStringRef>(
        CFDictionaryGetValue(desc, CFSTR(kIOPSPowerSourceStateKey)));
    const auto *charging = static_cast<const CFBooleanRef>(
        CFDictionaryGetValue(desc, CFSTR(kIOPSIsChargingKey)));
    if (charging != nullptr && CFBooleanGetValue(charging)) {
      info.battery_state = level >= 0.999 ? "full" : "charging";
    } else if (state != nullptr &&
               CFStringCompare(state, CFSTR(kIOPSACPowerValue), 0) ==
                   kCFCompareEqualTo) {
      info.battery_state = level >= 0.999 ? "full" : "charging";
    } else {
      info.battery_state = "unplugged";
    }
    break;
  }

  CFRelease(list);
  CFRelease(blob);
}

void collect_device_info(DeviceInfoState &info) {
  info.platform = "macos";

  info.model = sysctl_string("hw.model");
  if (info.model.empty()) {
    info.model = "Mac";
  }

  char hostname[256] = {};
  info.name = (gethostname(hostname, sizeof(hostname) - 1) == 0 &&
               hostname[0] != '\0')
                  ? hostname
                  : info.model;

  const std::string product_version = sysctl_string("kern.osproductversion");
  info.os_version =
      product_version.empty() ? "macOS" : "macOS " + product_version;

  info.chip = sysctl_string("machdep.cpu.brand_string");
  if (info.chip.empty()) {
    info.chip = "unknown";
  }

  info.total_memory = sysctl_i64("hw.memsize");
  info.available_memory = macos_available_memory_bytes();

  const int64_t ncpu = sysctl_i64("hw.ncpu");
  info.core_count = ncpu > 0 ? static_cast<int32_t>(ncpu) : 1;
  const int64_t perf = sysctl_i64("hw.perflevel0.logicalcpu");
  const int64_t eff = sysctl_i64("hw.perflevel1.logicalcpu");
  if (perf > 0) {
    info.performance_cores = static_cast<int32_t>(perf);
    info.efficiency_cores = eff > 0 ? static_cast<int32_t>(eff) : 0;
  } else {
    info.performance_cores = info.core_count;
    info.efficiency_cores = 0;
  }

  struct utsname uts = {};
  info.architecture = (uname(&uts) == 0 && uts.machine[0] != '\0')
                          ? uts.machine
                          : "unknown";

  info.form_factor =
      info.model.find("Book") != std::string::npos ? "laptop" : "desktop";
#if defined(__arm64__) || defined(__aarch64__)
  info.gpu_family = "apple";
#else
  info.gpu_family = "unknown";
#endif

  macos_sample_battery(info);
}

#else // _WIN32

void collect_device_info(DeviceInfoState &info) {
  info.platform = "windows";

  char computer_name[MAX_COMPUTERNAME_LENGTH + 1] = {};
  DWORD name_len = sizeof(computer_name);
  info.name = GetComputerNameA(computer_name, &name_len) ? computer_name
                                                         : "Windows PC";
  info.model = "Windows PC";
  info.os_version = "Windows";

  char cpu_name[256] = {};
  DWORD cpu_name_size = sizeof(cpu_name);
  if (RegGetValueA(HKEY_LOCAL_MACHINE,
                   "HARDWARE\\DESCRIPTION\\System\\CentralProcessor\\0",
                   "ProcessorNameString", RRF_RT_REG_SZ, nullptr, cpu_name,
                   &cpu_name_size) == ERROR_SUCCESS &&
      cpu_name[0] != '\0') {
    info.chip = trim(cpu_name);
  } else {
    info.chip = "unknown";
  }

  MEMORYSTATUSEX mem = {};
  mem.dwLength = sizeof(mem);
  if (GlobalMemoryStatusEx(&mem)) {
    info.total_memory = static_cast<int64_t>(mem.ullTotalPhys);
    info.available_memory = static_cast<int64_t>(mem.ullAvailPhys);
  }

  SYSTEM_INFO sys = {};
  GetNativeSystemInfo(&sys);
  info.core_count = sys.dwNumberOfProcessors > 0
                        ? static_cast<int32_t>(sys.dwNumberOfProcessors)
                        : 1;
  info.performance_cores = info.core_count;
  info.efficiency_cores = 0;
  switch (sys.wProcessorArchitecture) {
  case PROCESSOR_ARCHITECTURE_AMD64:
    info.architecture = "x86_64";
    break;
  case PROCESSOR_ARCHITECTURE_ARM64:
    info.architecture = "arm64";
    break;
  case PROCESSOR_ARCHITECTURE_INTEL:
    info.architecture = "x86";
    break;
  default:
    info.architecture = "unknown";
    break;
  }

  SYSTEM_POWER_STATUS power = {};
  if (GetSystemPowerStatus(&power) && power.BatteryFlag != 128 &&
      power.BatteryFlag != 255) {
    info.form_factor = "laptop";
    if (power.BatteryLifePercent <= 100) {
      info.battery_level =
          static_cast<double>(power.BatteryLifePercent) / 100.0;
      if (power.ACLineStatus == 1) {
        info.battery_state = power.BatteryLifePercent == 100 ? "full" : "charging";
      } else {
        info.battery_state = "unplugged";
      }
    }
  } else {
    info.form_factor = "desktop";
  }
  info.gpu_family = "unknown";
}

#endif

void device_get_info(rac_device_registration_info_t *out_info,
                     void * /*user_data*/) {
  if (out_info == nullptr) {
    return;
  }
  auto &info = state();
  info.battery_level = -1.0;
  info.battery_state.clear();
  collect_device_info(info);
  info.fingerprint = runanywhere::sha256_hex(
      info.model + "|" + info.chip + "|" + std::to_string(info.total_memory) +
      "|" + std::to_string(info.core_count));

  *out_info = {};
  out_info->device_id = info.device_id.c_str();
  out_info->device_model = info.model.c_str();
  out_info->device_name = info.name.c_str();
  out_info->platform = info.platform.c_str();
  out_info->os_version = info.os_version.c_str();
  out_info->form_factor = info.form_factor.c_str();
  out_info->architecture = info.architecture.c_str();
  out_info->chip_name = info.chip.c_str();
  out_info->total_memory = info.total_memory;
  out_info->available_memory = info.available_memory;
  out_info->has_neural_engine = RAC_FALSE;
  out_info->neural_engine_cores = 0;
  out_info->gpu_family = info.gpu_family.c_str();
  out_info->battery_level = info.battery_level;
  out_info->battery_state =
      info.battery_state.empty() ? nullptr : info.battery_state.c_str();
  out_info->is_low_power_mode = RAC_FALSE;
  out_info->core_count = info.core_count;
  out_info->performance_cores = info.performance_cores;
  out_info->efficiency_cores = info.efficiency_cores;
  out_info->device_fingerprint = info.fingerprint.c_str();
}

const char *device_get_id(void * /*user_data*/) {
  return state().device_id.c_str();
}

rac_bool_t device_is_registered(void * /*user_data*/) {
  return state().registered ? RAC_TRUE : RAC_FALSE;
}

void device_set_registered(rac_bool_t registered, void * /*user_data*/) {
  state().registered = registered == RAC_TRUE;
}

// Same control-plane POST shape as rcli_telemetry_http_callback: commons base
// URL + relative endpoint over the registered desktop HTTP transport, bearer
// token attached when the auth manager holds one.
rac_result_t device_http_post(const char *endpoint, const char *json_body,
                              rac_bool_t requires_auth,
                              rac_device_http_response_t *out_response,
                              void * /*user_data*/) {
  auto &info = state();
  info.http_body.clear();
  info.http_error.clear();

  auto fail = [&](rac_result_t rc, const char *message) {
    info.http_error = message;
    if (out_response != nullptr) {
      out_response->result = rc;
      out_response->status_code = 0;
      out_response->response_body = nullptr;
      out_response->error_message = info.http_error.c_str();
    }
    return rc;
  };

  if (endpoint == nullptr || json_body == nullptr) {
    return fail(RAC_ERROR_INVALID_ARGUMENT, "invalid registration request");
  }

  const char *base_url = rac_state_get_base_url();
  if (base_url == nullptr || base_url[0] == '\0' ||
      rac_http_transport_is_registered() != RAC_TRUE) {
    return fail(RAC_ERROR_NETWORK_ERROR,
                "device registration transport unavailable");
  }

  char url[2048] = {};
  if (rac_build_url(base_url, endpoint, url, sizeof(url)) < 0) {
    return fail(RAC_ERROR_NETWORK_ERROR, "device registration URL build failed");
  }

  std::vector<rac_http_header_kv_t> headers;
  const rac_http_header_kv_t *defaults = nullptr;
  size_t default_count = 0;
  if (rac_http_default_headers(&defaults, &default_count) == RAC_SUCCESS &&
      defaults != nullptr) {
    headers.assign(defaults, defaults + default_count);
  }
  std::string auth_value;
  if (requires_auth == RAC_TRUE) {
    const char *token = rac_auth_get_access_token();
    if (token != nullptr && token[0] != '\0') {
      auth_value = std::string("Bearer ") + token;
      headers.push_back({"Authorization", auth_value.c_str()});
    }
  }

  rac_http_client_t *client = nullptr;
  if (rac_http_client_create(&client) != RAC_SUCCESS) {
    return fail(RAC_ERROR_NETWORK_ERROR,
                "device registration client create failed");
  }

  rac_http_request_t request = {};
  request.method = "POST";
  request.url = url;
  request.headers = headers.empty() ? nullptr : headers.data();
  request.header_count = headers.size();
  request.body_bytes = reinterpret_cast<const uint8_t *>(json_body);
  request.body_len = std::char_traits<char>::length(json_body);
  request.timeout_ms =
      rac_env_default_http_timeout_ms(rac_state_get_environment());
  request.follow_redirects = RAC_FALSE;

  rac_http_response_t response = {};
  const rac_result_t rc = rac_http_request_send(client, &request, &response);
  rac_http_client_destroy(client);

  if (response.body_bytes != nullptr && response.body_len > 0) {
    info.http_body.assign(reinterpret_cast<const char *>(response.body_bytes),
                          response.body_len);
  }
  const int32_t status = response.status;
  rac_http_response_free(&response);

  const bool ok = rc == RAC_SUCCESS && status >= 200 && status < 300;
  if (!ok) {
    info.http_error = "device registration POST failed (http " +
                      std::to_string(status) + ")";
  }
  if (out_response != nullptr) {
    out_response->result = ok ? RAC_SUCCESS : RAC_ERROR_NETWORK_ERROR;
    out_response->status_code = status;
    out_response->response_body =
        info.http_body.empty() ? nullptr : info.http_body.c_str();
    out_response->error_message = ok ? nullptr : info.http_error.c_str();
  }
  return ok ? RAC_SUCCESS : RAC_ERROR_NETWORK_ERROR;
}

} // namespace

rac_result_t install_device_callbacks() {
  auto &info = state();
  char device_id[RAC_DEVICE_ID_BUFFER_MIN_SIZE] = {};
  if (rac_device_get_or_create_persistent_id(device_id, sizeof(device_id)) ==
          RAC_SUCCESS &&
      device_id[0] != '\0') {
    info.device_id = device_id;
  }

  rac_device_callbacks_t callbacks = {};
  callbacks.get_device_info = device_get_info;
  callbacks.get_device_id = device_get_id;
  callbacks.is_registered = device_is_registered;
  callbacks.set_registered = device_set_registered;
  callbacks.http_post = device_http_post;
  callbacks.user_data = nullptr;
  return rac_device_manager_set_callbacks(&callbacks);
}

} // namespace rcli
