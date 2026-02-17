/*
 * OpenCL runtime loader shim for Android.
 *
 * At build time: provides CL API symbols so ggml-opencl links successfully.
 * At runtime:    uses dlopen to load the device's vendor libOpenCL.so
 *                (e.g. Qualcomm Adreno) and forwards all calls through it.
 *
 * This bypasses Android's linker namespace restriction which prevents apps
 * from directly linking to vendor libraries like libOpenCL.so.
 *
 * Based on the cl_stub pattern (github.com/csarron/cl_stub).
 * Reference: Local-Diffusion uses <uses-native-library> manifest tag.
 */

#include <CL/cl.h>
#include <dlfcn.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>

#if defined(__ANDROID__) || defined(ANDROID)
#include <android/log.h>
#define LOG_TAG "RAC-OpenCL"
#define LOGI(...) __android_log_print(ANDROID_LOG_INFO,  LOG_TAG, __VA_ARGS__)
#define LOGW(...) __android_log_print(ANDROID_LOG_WARN,  LOG_TAG, __VA_ARGS__)
#define LOGE(...) __android_log_print(ANDROID_LOG_ERROR, LOG_TAG, __VA_ARGS__)
#else
#include <stdio.h>
#define LOGI(...) do { printf("[OpenCL] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#define LOGW(...) do { printf("[OpenCL WARN] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#define LOGE(...) do { printf("[OpenCL ERROR] "); printf(__VA_ARGS__); printf("\n"); } while(0)
#endif

/* ========================================================================= */
/* Vendor library search paths                                               */
/* ========================================================================= */

#if defined(__ANDROID__) && defined(__aarch64__)
static const char *opencl_search_paths[] = {
    "/system/vendor/lib64/libOpenCL.so",     /* Qualcomm Adreno (most common) */
    "/vendor/lib64/libOpenCL.so",            /* Vendor partition (symlink) */
    "/system/lib64/libOpenCL.so",            /* System partition */
    "/system/vendor/lib64/egl/libGLES_mali.so", /* ARM Mali GPUs */
    "/system/lib64/egl/libGLES_mali.so",     /* ARM Mali (alt path) */
    "/system/vendor/lib64/libPVROCL.so",     /* Imagination PowerVR */
    "/system/lib64/libPVROCL.so",            /* PowerVR (alt path) */
};
#elif defined(__ANDROID__)
static const char *opencl_search_paths[] = {
    "/system/vendor/lib/libOpenCL.so",
    "/vendor/lib/libOpenCL.so",
    "/system/lib/libOpenCL.so",
    "/system/vendor/lib/egl/libGLES_mali.so",
    "/system/lib/egl/libGLES_mali.so",
};
#else
static const char *opencl_search_paths[] = {
    "/usr/lib/x86_64-linux-gnu/libOpenCL.so",
    "/usr/lib/libOpenCL.so",
};
#endif

#define NUM_SEARCH_PATHS (sizeof(opencl_search_paths) / sizeof(opencl_search_paths[0]))

/* ========================================================================= */
/* Library handle                                                            */
/* ========================================================================= */

static void *g_opencl_handle = NULL;
static int   g_opencl_tried  = 0;
static int   g_opencl_disabled = 0; /* Set to 1 to force-disable OpenCL */

static int file_exists(const char *path) {
    struct stat buf;
    return (stat(path, &buf) == 0);
}

static void load_opencl_library(void) {
    if (g_opencl_tried) return;
    g_opencl_tried = 1;

    /* 1. Try environment override */
    const char *env = getenv("LIBOPENCL_SO_PATH");
    if (env && file_exists(env)) {
        g_opencl_handle = dlopen(env, RTLD_LAZY);
        if (g_opencl_handle) {
            LOGI("Loaded OpenCL from env: %s", env);
            return;
        }
    }

    /* 2. Try vendor paths (absolute only — bare names would find our own shim) */
    for (size_t i = 0; i < NUM_SEARCH_PATHS; i++) {
        if (!file_exists(opencl_search_paths[i])) continue;
        void *h = dlopen(opencl_search_paths[i], RTLD_LAZY);
        if (!h) continue;
        /* Guard: make sure we didn't load ourselves (same SONAME "libOpenCL.so") */
        if (dlsym(h, "opencl_stub_is_available")) {
            LOGW("Skipping %s (resolved to our own shim)", opencl_search_paths[i]);
            dlclose(h);
            continue;
        }
        g_opencl_handle = h;
        LOGI("Loaded vendor OpenCL from: %s", opencl_search_paths[i]);
        return;
    }

    LOGW("No vendor OpenCL library found - GPU acceleration unavailable, falling back to CPU");
}

/* Public: check if vendor OpenCL is available (callable from JNI/Kotlin) */
int opencl_stub_is_available(void) {
    load_opencl_library();
    return (g_opencl_handle != NULL && !g_opencl_disabled) ? 1 : 0;
}

/* Public: force-disable OpenCL so all subsequent CL calls fail gracefully.
 * Call this when the GPU is detected but unsupported (e.g. Mali on ggml-opencl
 * which only supports Adreno/Intel). Closes the vendor library handle so
 * all subsequent dlsym resolutions return NULL, causing ggml-opencl to see
 * "no OpenCL available" and fall back to CPU without aborting. */
void opencl_stub_disable(void) {
    LOGI("OpenCL explicitly disabled — closing vendor library handle");
    g_opencl_disabled = 1;
    if (g_opencl_handle) {
        dlclose(g_opencl_handle);
        g_opencl_handle = NULL;
    }
}

/* Public: probe the GPU and check if it's supported by ggml-opencl.
 * ggml-opencl only supports Adreno (Qualcomm) and Intel GPUs.
 * Returns 1 if supported, 0 if unsupported or unavailable. */
int opencl_stub_is_gpu_supported(void) {
    load_opencl_library();
    if (!g_opencl_handle) return 0;

    /* Resolve the CL functions we need */
    typedef cl_int (*PFN_clGetPlatformIDs)(cl_uint, cl_platform_id *, cl_uint *);
    typedef cl_int (*PFN_clGetDeviceIDs)(cl_platform_id, cl_device_type, cl_uint, cl_device_id *, cl_uint *);
    typedef cl_int (*PFN_clGetDeviceInfo)(cl_device_id, cl_device_info, size_t, void *, size_t *);

    PFN_clGetPlatformIDs fn_getPlatformIDs = (PFN_clGetPlatformIDs)dlsym(g_opencl_handle, "clGetPlatformIDs");
    PFN_clGetDeviceIDs fn_getDeviceIDs = (PFN_clGetDeviceIDs)dlsym(g_opencl_handle, "clGetDeviceIDs");
    PFN_clGetDeviceInfo fn_getDeviceInfo = (PFN_clGetDeviceInfo)dlsym(g_opencl_handle, "clGetDeviceInfo");

    if (!fn_getPlatformIDs || !fn_getDeviceIDs || !fn_getDeviceInfo) {
        LOGW("Cannot probe GPU: missing CL functions");
        return 0;
    }

    /* Get first platform */
    cl_platform_id platform;
    cl_uint num_platforms = 0;
    if (fn_getPlatformIDs(1, &platform, &num_platforms) != CL_SUCCESS || num_platforms == 0) {
        LOGW("No OpenCL platforms found");
        return 0;
    }

    /* Get first GPU device */
    cl_device_id device;
    cl_uint num_devices = 0;
    if (fn_getDeviceIDs(platform, CL_DEVICE_TYPE_GPU, 1, &device, &num_devices) != CL_SUCCESS || num_devices == 0) {
        LOGW("No OpenCL GPU devices found");
        return 0;
    }

    /* Get device name */
    char device_name[256] = {0};
    fn_getDeviceInfo(device, CL_DEVICE_NAME, sizeof(device_name) - 1, device_name, NULL);

    LOGI("OpenCL GPU detected: %s", device_name);

    /* ggml-opencl supports Adreno (Qualcomm) and Intel only */
    if (strstr(device_name, "Adreno") || strstr(device_name, "QUALCOMM") ||
        strstr(device_name, "Intel") || strstr(device_name, "INTEL")) {
        LOGI("GPU is supported by ggml-opencl");
        return 1;
    }

    LOGW("GPU '%s' is NOT supported by ggml-opencl (only Adreno/Intel). Will use CPU.", device_name);
    return 0;
}

/* ========================================================================= */
/* Helper: resolve a CL function via dlsym                                   */
/* ========================================================================= */

static void *resolve(const char *name) {
    if (g_opencl_disabled) return NULL;
    load_opencl_library();
    if (!g_opencl_handle) return NULL;
    return dlsym(g_opencl_handle, name);
}

/* ========================================================================= */
/* OpenCL API forwarding wrappers                                            */
/*                                                                           */
/* Each function: resolve via dlsym, forward if found, return error if not.  */
/* ========================================================================= */

/* --- Platform & Device --- */

cl_int clGetPlatformIDs(cl_uint n, cl_platform_id *p, cl_uint *np) {
    /* When OpenCL is disabled (unsupported GPU), return "0 platforms found"
     * instead of an error. This makes ggml-opencl fall back to CPU gracefully
     * instead of aborting on CL_INVALID_PLATFORM. */
    if (g_opencl_disabled) {
        if (np) *np = 0;
        return CL_SUCCESS;
    }
    typedef cl_int (*F)(cl_uint, cl_platform_id *, cl_uint *);
    F f = (F)resolve("clGetPlatformIDs");
    return f ? f(n, p, np) : CL_INVALID_PLATFORM;
}

cl_int clGetPlatformInfo(cl_platform_id p, cl_platform_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_platform_id, cl_platform_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetPlatformInfo");
    return f ? f(p, i, s, v, rs) : CL_INVALID_PLATFORM;
}

cl_int clGetDeviceIDs(cl_platform_id p, cl_device_type t, cl_uint n, cl_device_id *d, cl_uint *nd) {
    typedef cl_int (*F)(cl_platform_id, cl_device_type, cl_uint, cl_device_id *, cl_uint *);
    F f = (F)resolve("clGetDeviceIDs");
    return f ? f(p, t, n, d, nd) : CL_INVALID_PLATFORM;
}

cl_int clGetDeviceInfo(cl_device_id d, cl_device_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_device_id, cl_device_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetDeviceInfo");
    return f ? f(d, i, s, v, rs) : CL_INVALID_DEVICE;
}

cl_int clRetainDevice(cl_device_id d) {
    typedef cl_int (*F)(cl_device_id);
    F f = (F)resolve("clRetainDevice");
    return f ? f(d) : CL_INVALID_DEVICE;
}

cl_int clReleaseDevice(cl_device_id d) {
    typedef cl_int (*F)(cl_device_id);
    F f = (F)resolve("clReleaseDevice");
    return f ? f(d) : CL_INVALID_DEVICE;
}

cl_int clCreateSubDevices(cl_device_id d, const cl_device_partition_property *p, cl_uint n, cl_device_id *od, cl_uint *nd) {
    typedef cl_int (*F)(cl_device_id, const cl_device_partition_property *, cl_uint, cl_device_id *, cl_uint *);
    F f = (F)resolve("clCreateSubDevices");
    return f ? f(d, p, n, od, nd) : CL_INVALID_DEVICE;
}

/* --- Context --- */

cl_context clCreateContext(const cl_context_properties *p, cl_uint n, const cl_device_id *d, void (CL_CALLBACK *pf)(const char *, const void *, size_t, void *), void *ud, cl_int *e) {
    typedef cl_context (*F)(const cl_context_properties *, cl_uint, const cl_device_id *, void (CL_CALLBACK *)(const char *, const void *, size_t, void *), void *, cl_int *);
    F f = (F)resolve("clCreateContext");
    if (f) return f(p, n, d, pf, ud, e);
    if (e) *e = CL_INVALID_PLATFORM;
    return 0;
}

cl_context clCreateContextFromType(const cl_context_properties *p, cl_device_type t, void (CL_CALLBACK *pf)(const char *, const void *, size_t, void *), void *ud, cl_int *e) {
    typedef cl_context (*F)(const cl_context_properties *, cl_device_type, void (CL_CALLBACK *)(const char *, const void *, size_t, void *), void *, cl_int *);
    F f = (F)resolve("clCreateContextFromType");
    if (f) return f(p, t, pf, ud, e);
    if (e) *e = CL_INVALID_PLATFORM;
    return 0;
}

cl_int clRetainContext(cl_context c) {
    typedef cl_int (*F)(cl_context);
    F f = (F)resolve("clRetainContext");
    return f ? f(c) : CL_INVALID_CONTEXT;
}

cl_int clReleaseContext(cl_context c) {
    typedef cl_int (*F)(cl_context);
    F f = (F)resolve("clReleaseContext");
    return f ? f(c) : CL_INVALID_CONTEXT;
}

cl_int clGetContextInfo(cl_context c, cl_context_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_context, cl_context_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetContextInfo");
    return f ? f(c, i, s, v, rs) : CL_INVALID_CONTEXT;
}

/* --- Command Queue --- */

cl_command_queue clCreateCommandQueue(cl_context c, cl_device_id d, cl_command_queue_properties p, cl_int *e) {
    typedef cl_command_queue (*F)(cl_context, cl_device_id, cl_command_queue_properties, cl_int *);
    F f = (F)resolve("clCreateCommandQueue");
    if (f) return f(c, d, p, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_command_queue clCreateCommandQueueWithProperties(cl_context c, cl_device_id d, const cl_queue_properties *p, cl_int *e) {
    typedef cl_command_queue (*F)(cl_context, cl_device_id, const cl_queue_properties *, cl_int *);
    F f = (F)resolve("clCreateCommandQueueWithProperties");
    if (f) return f(c, d, p, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clRetainCommandQueue(cl_command_queue q) {
    typedef cl_int (*F)(cl_command_queue);
    F f = (F)resolve("clRetainCommandQueue");
    return f ? f(q) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clReleaseCommandQueue(cl_command_queue q) {
    typedef cl_int (*F)(cl_command_queue);
    F f = (F)resolve("clReleaseCommandQueue");
    return f ? f(q) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clGetCommandQueueInfo(cl_command_queue q, cl_command_queue_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_command_queue, cl_command_queue_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetCommandQueueInfo");
    return f ? f(q, i, s, v, rs) : CL_INVALID_COMMAND_QUEUE;
}

/* --- Memory Objects --- */

cl_mem clCreateBuffer(cl_context c, cl_mem_flags fl, size_t s, void *h, cl_int *e) {
    typedef cl_mem (*F)(cl_context, cl_mem_flags, size_t, void *, cl_int *);
    F f = (F)resolve("clCreateBuffer");
    if (f) return f(c, fl, s, h, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_mem clCreateSubBuffer(cl_mem b, cl_mem_flags fl, cl_buffer_create_type t, const void *i, cl_int *e) {
    typedef cl_mem (*F)(cl_mem, cl_mem_flags, cl_buffer_create_type, const void *, cl_int *);
    F f = (F)resolve("clCreateSubBuffer");
    if (f) return f(b, fl, t, i, e);
    if (e) *e = CL_INVALID_MEM_OBJECT;
    return 0;
}

cl_mem clCreateImage(cl_context c, cl_mem_flags fl, const cl_image_format *fmt, const cl_image_desc *desc, void *h, cl_int *e) {
    typedef cl_mem (*F)(cl_context, cl_mem_flags, const cl_image_format *, const cl_image_desc *, void *, cl_int *);
    F f = (F)resolve("clCreateImage");
    if (f) return f(c, fl, fmt, desc, h, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clRetainMemObject(cl_mem m) {
    typedef cl_int (*F)(cl_mem);
    F f = (F)resolve("clRetainMemObject");
    return f ? f(m) : CL_INVALID_MEM_OBJECT;
}

cl_int clReleaseMemObject(cl_mem m) {
    typedef cl_int (*F)(cl_mem);
    F f = (F)resolve("clReleaseMemObject");
    return f ? f(m) : CL_INVALID_MEM_OBJECT;
}

cl_int clGetMemObjectInfo(cl_mem m, cl_mem_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_mem, cl_mem_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetMemObjectInfo");
    return f ? f(m, i, s, v, rs) : CL_INVALID_MEM_OBJECT;
}

cl_int clGetImageInfo(cl_mem m, cl_image_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_mem, cl_image_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetImageInfo");
    return f ? f(m, i, s, v, rs) : CL_INVALID_MEM_OBJECT;
}

cl_int clSetMemObjectDestructorCallback(cl_mem m, void (CL_CALLBACK *pf)(cl_mem, void *), void *ud) {
    typedef cl_int (*F)(cl_mem, void (CL_CALLBACK *)(cl_mem, void *), void *);
    F f = (F)resolve("clSetMemObjectDestructorCallback");
    return f ? f(m, pf, ud) : CL_INVALID_MEM_OBJECT;
}

cl_int clGetSupportedImageFormats(cl_context c, cl_mem_flags fl, cl_mem_object_type t, cl_uint n, cl_image_format *fmt, cl_uint *nf) {
    typedef cl_int (*F)(cl_context, cl_mem_flags, cl_mem_object_type, cl_uint, cl_image_format *, cl_uint *);
    F f = (F)resolve("clGetSupportedImageFormats");
    return f ? f(c, fl, t, n, fmt, nf) : CL_INVALID_CONTEXT;
}

/* --- Program --- */

cl_program clCreateProgramWithSource(cl_context c, cl_uint count, const char **strings, const size_t *lengths, cl_int *e) {
    typedef cl_program (*F)(cl_context, cl_uint, const char **, const size_t *, cl_int *);
    F f = (F)resolve("clCreateProgramWithSource");
    if (f) return f(c, count, strings, lengths, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_program clCreateProgramWithBinary(cl_context c, cl_uint n, const cl_device_id *dl, const size_t *lengths, const unsigned char **bins, cl_int *bs, cl_int *e) {
    typedef cl_program (*F)(cl_context, cl_uint, const cl_device_id *, const size_t *, const unsigned char **, cl_int *, cl_int *);
    F f = (F)resolve("clCreateProgramWithBinary");
    if (f) return f(c, n, dl, lengths, bins, bs, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_program clCreateProgramWithBuiltInKernels(cl_context c, cl_uint n, const cl_device_id *dl, const char *kn, cl_int *e) {
    typedef cl_program (*F)(cl_context, cl_uint, const cl_device_id *, const char *, cl_int *);
    F f = (F)resolve("clCreateProgramWithBuiltInKernels");
    if (f) return f(c, n, dl, kn, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clRetainProgram(cl_program p) {
    typedef cl_int (*F)(cl_program);
    F f = (F)resolve("clRetainProgram");
    return f ? f(p) : CL_INVALID_PROGRAM;
}

cl_int clReleaseProgram(cl_program p) {
    typedef cl_int (*F)(cl_program);
    F f = (F)resolve("clReleaseProgram");
    return f ? f(p) : CL_INVALID_PROGRAM;
}

cl_int clBuildProgram(cl_program p, cl_uint n, const cl_device_id *dl, const char *opts, void (CL_CALLBACK *pf)(cl_program, void *), void *ud) {
    typedef cl_int (*F)(cl_program, cl_uint, const cl_device_id *, const char *, void (CL_CALLBACK *)(cl_program, void *), void *);
    F f = (F)resolve("clBuildProgram");
    return f ? f(p, n, dl, opts, pf, ud) : CL_INVALID_PROGRAM;
}

cl_int clCompileProgram(cl_program p, cl_uint n, const cl_device_id *dl, const char *opts, cl_uint ni, const cl_program *ih, const char **hn, void (CL_CALLBACK *pf)(cl_program, void *), void *ud) {
    typedef cl_int (*F)(cl_program, cl_uint, const cl_device_id *, const char *, cl_uint, const cl_program *, const char **, void (CL_CALLBACK *)(cl_program, void *), void *);
    F f = (F)resolve("clCompileProgram");
    return f ? f(p, n, dl, opts, ni, ih, hn, pf, ud) : CL_INVALID_PROGRAM;
}

cl_program clLinkProgram(cl_context c, cl_uint n, const cl_device_id *dl, const char *opts, cl_uint ni, const cl_program *ip, void (CL_CALLBACK *pf)(cl_program, void *), void *ud, cl_int *e) {
    typedef cl_program (*F)(cl_context, cl_uint, const cl_device_id *, const char *, cl_uint, const cl_program *, void (CL_CALLBACK *)(cl_program, void *), void *, cl_int *);
    F f = (F)resolve("clLinkProgram");
    if (f) return f(c, n, dl, opts, ni, ip, pf, ud, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clGetProgramInfo(cl_program p, cl_program_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_program, cl_program_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetProgramInfo");
    return f ? f(p, i, s, v, rs) : CL_INVALID_PROGRAM;
}

cl_int clGetProgramBuildInfo(cl_program p, cl_device_id d, cl_program_build_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_program, cl_device_id, cl_program_build_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetProgramBuildInfo");
    return f ? f(p, d, i, s, v, rs) : CL_INVALID_PROGRAM;
}

cl_int clUnloadPlatformCompiler(cl_platform_id p) {
    typedef cl_int (*F)(cl_platform_id);
    F f = (F)resolve("clUnloadPlatformCompiler");
    return f ? f(p) : CL_SUCCESS;
}

/* --- Kernel --- */

cl_kernel clCreateKernel(cl_program p, const char *name, cl_int *e) {
    typedef cl_kernel (*F)(cl_program, const char *, cl_int *);
    F f = (F)resolve("clCreateKernel");
    if (f) return f(p, name, e);
    if (e) *e = CL_INVALID_PROGRAM;
    return 0;
}

cl_int clCreateKernelsInProgram(cl_program p, cl_uint n, cl_kernel *k, cl_uint *nk) {
    typedef cl_int (*F)(cl_program, cl_uint, cl_kernel *, cl_uint *);
    F f = (F)resolve("clCreateKernelsInProgram");
    return f ? f(p, n, k, nk) : CL_INVALID_PROGRAM;
}

cl_int clRetainKernel(cl_kernel k) {
    typedef cl_int (*F)(cl_kernel);
    F f = (F)resolve("clRetainKernel");
    return f ? f(k) : CL_INVALID_KERNEL;
}

cl_int clReleaseKernel(cl_kernel k) {
    typedef cl_int (*F)(cl_kernel);
    F f = (F)resolve("clReleaseKernel");
    return f ? f(k) : CL_INVALID_KERNEL;
}

cl_int clSetKernelArg(cl_kernel k, cl_uint i, size_t s, const void *v) {
    typedef cl_int (*F)(cl_kernel, cl_uint, size_t, const void *);
    F f = (F)resolve("clSetKernelArg");
    return f ? f(k, i, s, v) : CL_INVALID_KERNEL;
}

cl_int clGetKernelInfo(cl_kernel k, cl_kernel_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_kernel, cl_kernel_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetKernelInfo");
    return f ? f(k, i, s, v, rs) : CL_INVALID_KERNEL;
}

cl_int clGetKernelWorkGroupInfo(cl_kernel k, cl_device_id d, cl_kernel_work_group_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_kernel, cl_device_id, cl_kernel_work_group_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetKernelWorkGroupInfo");
    return f ? f(k, d, i, s, v, rs) : CL_INVALID_KERNEL;
}

cl_int clGetKernelArgInfo(cl_kernel k, cl_uint i, cl_kernel_arg_info pi, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_kernel, cl_uint, cl_kernel_arg_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetKernelArgInfo");
    return f ? f(k, i, pi, s, v, rs) : CL_INVALID_KERNEL;
}

/* --- Enqueue --- */

cl_int clEnqueueReadBuffer(cl_command_queue q, cl_mem b, cl_bool bl, size_t o, size_t s, void *p, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_bool, size_t, size_t, void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueReadBuffer");
    return f ? f(q, b, bl, o, s, p, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueWriteBuffer(cl_command_queue q, cl_mem b, cl_bool bl, size_t o, size_t s, const void *p, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_bool, size_t, size_t, const void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueWriteBuffer");
    return f ? f(q, b, bl, o, s, p, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueReadBufferRect(cl_command_queue q, cl_mem b, cl_bool bl, const size_t *bo, const size_t *ho, const size_t *r, size_t brp, size_t bsp, size_t hrp, size_t hsp, void *p, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_bool, const size_t *, const size_t *, const size_t *, size_t, size_t, size_t, size_t, void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueReadBufferRect");
    return f ? f(q, b, bl, bo, ho, r, brp, bsp, hrp, hsp, p, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueWriteBufferRect(cl_command_queue q, cl_mem b, cl_bool bl, const size_t *bo, const size_t *ho, const size_t *r, size_t brp, size_t bsp, size_t hrp, size_t hsp, const void *p, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_bool, const size_t *, const size_t *, const size_t *, size_t, size_t, size_t, size_t, const void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueWriteBufferRect");
    return f ? f(q, b, bl, bo, ho, r, brp, bsp, hrp, hsp, p, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueCopyBuffer(cl_command_queue q, cl_mem s, cl_mem d, size_t so, size_t do2, size_t sz, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_mem, size_t, size_t, size_t, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueCopyBuffer");
    return f ? f(q, s, d, so, do2, sz, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueCopyBufferRect(cl_command_queue q, cl_mem s, cl_mem d, const size_t *so, const size_t *do2, const size_t *r, size_t srp, size_t ssp, size_t drp, size_t dsp, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_mem, const size_t *, const size_t *, const size_t *, size_t, size_t, size_t, size_t, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueCopyBufferRect");
    return f ? f(q, s, d, so, do2, r, srp, ssp, drp, dsp, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueFillBuffer(cl_command_queue q, cl_mem b, const void *p, size_t ps, size_t o, size_t s, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, const void *, size_t, size_t, size_t, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueFillBuffer");
    return f ? f(q, b, p, ps, o, s, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueReadImage(cl_command_queue q, cl_mem i, cl_bool bl, const size_t *o, const size_t *r, size_t rp, size_t sp, void *p, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_bool, const size_t *, const size_t *, size_t, size_t, void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueReadImage");
    return f ? f(q, i, bl, o, r, rp, sp, p, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueWriteImage(cl_command_queue q, cl_mem i, cl_bool bl, const size_t *o, const size_t *r, size_t rp, size_t sp, const void *p, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_bool, const size_t *, const size_t *, size_t, size_t, const void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueWriteImage");
    return f ? f(q, i, bl, o, r, rp, sp, p, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueCopyImage(cl_command_queue q, cl_mem s, cl_mem d, const size_t *so, const size_t *do2, const size_t *r, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_mem, const size_t *, const size_t *, const size_t *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueCopyImage");
    return f ? f(q, s, d, so, do2, r, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueCopyImageToBuffer(cl_command_queue q, cl_mem s, cl_mem d, const size_t *so, const size_t *r, size_t do2, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_mem, const size_t *, const size_t *, size_t, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueCopyImageToBuffer");
    return f ? f(q, s, d, so, r, do2, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueCopyBufferToImage(cl_command_queue q, cl_mem s, cl_mem d, size_t so, const size_t *do2, const size_t *r, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, cl_mem, size_t, const size_t *, const size_t *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueCopyBufferToImage");
    return f ? f(q, s, d, so, do2, r, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueFillImage(cl_command_queue q, cl_mem i, const void *fc, const size_t *o, const size_t *r, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, const void *, const size_t *, const size_t *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueFillImage");
    return f ? f(q, i, fc, o, r, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

void * clEnqueueMapBuffer(cl_command_queue q, cl_mem b, cl_bool bl, cl_map_flags fl, size_t o, size_t s, cl_uint nw, const cl_event *wl, cl_event *ev, cl_int *e) {
    typedef void * (*F)(cl_command_queue, cl_mem, cl_bool, cl_map_flags, size_t, size_t, cl_uint, const cl_event *, cl_event *, cl_int *);
    F f = (F)resolve("clEnqueueMapBuffer");
    if (f) return f(q, b, bl, fl, o, s, nw, wl, ev, e);
    if (e) *e = CL_INVALID_COMMAND_QUEUE;
    return 0;
}

void * clEnqueueMapImage(cl_command_queue q, cl_mem i, cl_bool bl, cl_map_flags fl, const size_t *o, const size_t *r, size_t *rp, size_t *sp, cl_uint nw, const cl_event *wl, cl_event *ev, cl_int *e) {
    typedef void * (*F)(cl_command_queue, cl_mem, cl_bool, cl_map_flags, const size_t *, const size_t *, size_t *, size_t *, cl_uint, const cl_event *, cl_event *, cl_int *);
    F f = (F)resolve("clEnqueueMapImage");
    if (f) return f(q, i, bl, fl, o, r, rp, sp, nw, wl, ev, e);
    if (e) *e = CL_INVALID_COMMAND_QUEUE;
    return 0;
}

cl_int clEnqueueUnmapMemObject(cl_command_queue q, cl_mem m, void *p, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_mem, void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueUnmapMemObject");
    return f ? f(q, m, p, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueNDRangeKernel(cl_command_queue q, cl_kernel k, cl_uint wd, const size_t *go, const size_t *gs, const size_t *ls, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_kernel, cl_uint, const size_t *, const size_t *, const size_t *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueNDRangeKernel");
    return f ? f(q, k, wd, go, gs, ls, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueNativeKernel(cl_command_queue q, void (CL_CALLBACK *uf)(void *), void *a, size_t s, cl_uint n, const cl_mem *ml, const void **al, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, void (CL_CALLBACK *)(void *), void *, size_t, cl_uint, const cl_mem *, const void **, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueNativeKernel");
    return f ? f(q, uf, a, s, n, ml, al, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueMigrateMemObjects(cl_command_queue q, cl_uint n, const cl_mem *mo, cl_mem_migration_flags fl, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_uint, const cl_mem *, cl_mem_migration_flags, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueMigrateMemObjects");
    return f ? f(q, n, mo, fl, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueMarkerWithWaitList(cl_command_queue q, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueMarkerWithWaitList");
    return f ? f(q, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueBarrierWithWaitList(cl_command_queue q, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueBarrierWithWaitList");
    return f ? f(q, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

/* --- Events --- */

cl_int clWaitForEvents(cl_uint n, const cl_event *el) {
    typedef cl_int (*F)(cl_uint, const cl_event *);
    F f = (F)resolve("clWaitForEvents");
    return f ? f(n, el) : CL_INVALID_EVENT;
}

cl_int clGetEventInfo(cl_event e, cl_event_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_event, cl_event_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetEventInfo");
    return f ? f(e, i, s, v, rs) : CL_INVALID_EVENT;
}

cl_int clRetainEvent(cl_event e) {
    typedef cl_int (*F)(cl_event);
    F f = (F)resolve("clRetainEvent");
    return f ? f(e) : CL_INVALID_EVENT;
}

cl_int clReleaseEvent(cl_event e) {
    typedef cl_int (*F)(cl_event);
    F f = (F)resolve("clReleaseEvent");
    return f ? f(e) : CL_INVALID_EVENT;
}

cl_int clSetEventCallback(cl_event e, cl_int t, void (CL_CALLBACK *pf)(cl_event, cl_int, void *), void *ud) {
    typedef cl_int (*F)(cl_event, cl_int, void (CL_CALLBACK *)(cl_event, cl_int, void *), void *);
    F f = (F)resolve("clSetEventCallback");
    return f ? f(e, t, pf, ud) : CL_INVALID_EVENT;
}

cl_int clGetEventProfilingInfo(cl_event e, cl_profiling_info i, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_event, cl_profiling_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetEventProfilingInfo");
    return f ? f(e, i, s, v, rs) : CL_INVALID_EVENT;
}

cl_event clCreateUserEvent(cl_context c, cl_int *e) {
    typedef cl_event (*F)(cl_context, cl_int *);
    F f = (F)resolve("clCreateUserEvent");
    if (f) return f(c, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clSetUserEventStatus(cl_event e, cl_int s) {
    typedef cl_int (*F)(cl_event, cl_int);
    F f = (F)resolve("clSetUserEventStatus");
    return f ? f(e, s) : CL_INVALID_EVENT;
}

/* --- Flush / Finish --- */

cl_int clFlush(cl_command_queue q) {
    typedef cl_int (*F)(cl_command_queue);
    F f = (F)resolve("clFlush");
    return f ? f(q) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clFinish(cl_command_queue q) {
    typedef cl_int (*F)(cl_command_queue);
    F f = (F)resolve("clFinish");
    return f ? f(q) : CL_INVALID_COMMAND_QUEUE;
}

/* --- Sampler --- */

cl_sampler clCreateSampler(cl_context c, cl_bool ncoords, cl_addressing_mode am, cl_filter_mode fm, cl_int *e) {
    typedef cl_sampler (*F)(cl_context, cl_bool, cl_addressing_mode, cl_filter_mode, cl_int *);
    F f = (F)resolve("clCreateSampler");
    if (f) return f(c, ncoords, am, fm, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_sampler clCreateSamplerWithProperties(cl_context c, const cl_sampler_properties *p, cl_int *e) {
    typedef cl_sampler (*F)(cl_context, const cl_sampler_properties *, cl_int *);
    F f = (F)resolve("clCreateSamplerWithProperties");
    if (f) return f(c, p, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clRetainSampler(cl_sampler s) {
    typedef cl_int (*F)(cl_sampler);
    F f = (F)resolve("clRetainSampler");
    return f ? f(s) : CL_INVALID_SAMPLER;
}

cl_int clReleaseSampler(cl_sampler s) {
    typedef cl_int (*F)(cl_sampler);
    F f = (F)resolve("clReleaseSampler");
    return f ? f(s) : CL_INVALID_SAMPLER;
}

cl_int clGetSamplerInfo(cl_sampler s, cl_sampler_info i, size_t sz, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_sampler, cl_sampler_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetSamplerInfo");
    return f ? f(s, i, sz, v, rs) : CL_INVALID_SAMPLER;
}

/* --- SVM (OpenCL 2.0) --- */

void * clSVMAlloc(cl_context c, cl_svm_mem_flags fl, size_t s, cl_uint a) {
    typedef void * (*F)(cl_context, cl_svm_mem_flags, size_t, cl_uint);
    F f = (F)resolve("clSVMAlloc");
    return f ? f(c, fl, s, a) : 0;
}

void clSVMFree(cl_context c, void *p) {
    typedef void (*F)(cl_context, void *);
    F f = (F)resolve("clSVMFree");
    if (f) f(c, p);
}

cl_int clEnqueueSVMFree(cl_command_queue q, cl_uint n, void *sv[], void (CL_CALLBACK *pf)(cl_command_queue, cl_uint, void *[], void *), void *ud, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_uint, void *[], void (CL_CALLBACK *)(cl_command_queue, cl_uint, void *[], void *), void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueSVMFree");
    return f ? f(q, n, sv, pf, ud, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueSVMMemcpy(cl_command_queue q, cl_bool bl, void *dp, const void *sp, size_t s, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_bool, void *, const void *, size_t, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueSVMMemcpy");
    return f ? f(q, bl, dp, sp, s, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueSVMMemFill(cl_command_queue q, void *sv, const void *p, size_t ps, size_t s, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, void *, const void *, size_t, size_t, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueSVMMemFill");
    return f ? f(q, sv, p, ps, s, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueSVMMap(cl_command_queue q, cl_bool bl, cl_map_flags fl, void *sv, size_t s, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, cl_bool, cl_map_flags, void *, size_t, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueSVMMap");
    return f ? f(q, bl, fl, sv, s, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clEnqueueSVMUnmap(cl_command_queue q, void *sv, cl_uint nw, const cl_event *wl, cl_event *ev) {
    typedef cl_int (*F)(cl_command_queue, void *, cl_uint, const cl_event *, cl_event *);
    F f = (F)resolve("clEnqueueSVMUnmap");
    return f ? f(q, sv, nw, wl, ev) : CL_INVALID_COMMAND_QUEUE;
}

cl_int clSetKernelArgSVMPointer(cl_kernel k, cl_uint i, const void *v) {
    typedef cl_int (*F)(cl_kernel, cl_uint, const void *);
    F f = (F)resolve("clSetKernelArgSVMPointer");
    return f ? f(k, i, v) : CL_INVALID_KERNEL;
}

cl_int clSetKernelExecInfo(cl_kernel k, cl_kernel_exec_info pi, size_t s, const void *v) {
    typedef cl_int (*F)(cl_kernel, cl_kernel_exec_info, size_t, const void *);
    F f = (F)resolve("clSetKernelExecInfo");
    return f ? f(k, pi, s, v) : CL_INVALID_KERNEL;
}

/* --- Pipe (OpenCL 2.0) --- */

cl_mem clCreatePipe(cl_context c, cl_mem_flags fl, cl_uint ps, cl_uint mp, const cl_pipe_properties *p, cl_int *e) {
    typedef cl_mem (*F)(cl_context, cl_mem_flags, cl_uint, cl_uint, const cl_pipe_properties *, cl_int *);
    F f = (F)resolve("clCreatePipe");
    if (f) return f(c, fl, ps, mp, p, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clGetPipeInfo(cl_mem p, cl_pipe_info pi, size_t s, void *v, size_t *rs) {
    typedef cl_int (*F)(cl_mem, cl_pipe_info, size_t, void *, size_t *);
    F f = (F)resolve("clGetPipeInfo");
    return f ? f(p, pi, s, v, rs) : CL_INVALID_MEM_OBJECT;
}

/* --- OpenCL 3.0 --- */

cl_mem clCreateBufferWithProperties(cl_context c, const cl_mem_properties *p, cl_mem_flags fl, size_t s, void *h, cl_int *e) {
    typedef cl_mem (*F)(cl_context, const cl_mem_properties *, cl_mem_flags, size_t, void *, cl_int *);
    F f = (F)resolve("clCreateBufferWithProperties");
    if (f) return f(c, p, fl, s, h, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_mem clCreateImageWithProperties(cl_context c, const cl_mem_properties *p, cl_mem_flags fl, const cl_image_format *fmt, const cl_image_desc *desc, void *h, cl_int *e) {
    typedef cl_mem (*F)(cl_context, const cl_mem_properties *, cl_mem_flags, const cl_image_format *, const cl_image_desc *, void *, cl_int *);
    F f = (F)resolve("clCreateImageWithProperties");
    if (f) return f(c, p, fl, fmt, desc, h, e);
    if (e) *e = CL_INVALID_CONTEXT;
    return 0;
}

cl_int clSetContextDestructorCallback(cl_context c, void (CL_CALLBACK *pf)(cl_context, void *), void *ud) {
    typedef cl_int (*F)(cl_context, void (CL_CALLBACK *)(cl_context, void *), void *);
    F f = (F)resolve("clSetContextDestructorCallback");
    return f ? f(c, pf, ud) : CL_INVALID_CONTEXT;
}

/* --- Extension --- */

void * clGetExtensionFunctionAddressForPlatform(cl_platform_id p, const char *fn) {
    typedef void * (*F)(cl_platform_id, const char *);
    F f = (F)resolve("clGetExtensionFunctionAddressForPlatform");
    return f ? f(p, fn) : 0;
}
