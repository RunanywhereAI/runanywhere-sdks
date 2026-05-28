// SPDX-License-Identifier: Apache-2.0
//
// URLSessionHttpTransportImpl.inc.mm
//
// Canonical ObjC++ implementation of the URLSession-backed RAC HTTP transport
// adapter, shared across iOS-shipping SDKs. Mirrors the Swift SDK reference
//   sdk/runanywhere-swift/Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift
// but is implemented in ObjC++ because the Flutter / React Native plugin pods
// do NOT ship a `CRACommons` Swift module map, so they cannot import the C
// ABI from Swift directly. Direct `#include "rac/..."` works because each
// consuming pod adds the xcframework's `Headers` path to HEADER_SEARCH_PATHS.
//
// This file is intentionally NOT compiled directly — it is `#include`d from
// per-SDK wrapper .mm files which set:
//
//   - `RAC_URLS_C_PREFIX`     unique C entry-point prefix used to export
//                             `<prefix>_register_urlsession_transport()` and
//                             friends. Required.
//   - `RAC_URLS_OBJC_PREFIX`  unique ObjC class-name prefix for the per-
//                             stream delegate (so two pods can both ship the
//                             ObjC class without symbol collision). Required.
//
// Exposes four C entry points named by the wrapper's prefix:
//   - <prefix>_register_urlsession_transport()        — idempotent; installs
//     the vtable so subsequent rac_http_request_* calls route through
//     URLSession.
//   - <prefix>_unregister_urlsession_transport()      — detaches the vtable
//     and cancels all in-flight streams (useful in tests / shutdown).
//   - <prefix>_set_streaming_session(NSURLSession*)   — host override for the
//     streaming session (`.background(...)` configs, custom retry policies).
//   - <prefix>_cancel_all_streams()                   — abort every live
//     streaming / resume task (used when the SDK is tearing down).
//
// Parity matrix vs the Swift reference:
//   - Per-stream registry + `cancelAllStreams()`                  OK
//   - Host-provided streaming session override                    OK
//   - `X-RAC-Range-Honored` synthetic response header on resume   OK
//   - 24h `timeoutIntervalForResource` on streaming sessions      OK
//   - `resumeFromByte` baked into `didReceiveResponse` totals     OK
//   - `os_log` on com.runanywhere subsystem (visible via
//     `log stream --predicate 'subsystem CONTAINS "com.runanywhere"'`) OK
//   - `waitsForConnectivity=YES` on streaming sessions            OK

#if !defined(RAC_URLS_C_PREFIX) || !defined(RAC_URLS_OBJC_PREFIX)
#  error "URLSessionHttpTransportImpl.inc.mm must be included from a wrapper " \
         "that defines RAC_URLS_C_PREFIX and RAC_URLS_OBJC_PREFIX."
#endif

// Build the exported symbol name `<prefix>_register_urlsession_transport`
// from the caller's RAC_URLS_C_PREFIX. The double indirection is needed so
// the prefix token expands before concatenation.
#define RAC_URLS_CONCAT2(a, b) a##b
#define RAC_URLS_CONCAT(a, b)  RAC_URLS_CONCAT2(a, b)
#define RAC_URLS_CFN(name)     RAC_URLS_CONCAT(RAC_URLS_C_PREFIX, name)
#define RAC_URLS_OBJC(name)    RAC_URLS_CONCAT(RAC_URLS_OBJC_PREFIX, name)

#import <Foundation/Foundation.h>

#include <os/log.h>
#include <time.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <unordered_map>
#include <utility>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

// =============================================================================
// Logging — route through os_log so messages surface via
// `log stream --predicate 'subsystem CONTAINS "com.runanywhere"'`.
// =============================================================================
namespace {

inline os_log_t ra_http_log() {
    static os_log_t logger = nullptr;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        logger = os_log_create("com.runanywhere", "URLSessionHttpTransport");
    });
    return logger;
}

}  // namespace

#define RA_HTTP_LOG_INFO(fmt, ...)  os_log_info(ra_http_log(), fmt, ##__VA_ARGS__)
#define RA_HTTP_LOG_DEBUG(fmt, ...) os_log_debug(ra_http_log(), fmt, ##__VA_ARGS__)
#define RA_HTTP_LOG_ERROR(fmt, ...) os_log_error(ra_http_log(), fmt, ##__VA_ARGS__)

// Forward decls so the registry can hold references. The
// `cancelFromExternal` selector is declared here too so the helper
// `cancelAllStreams()` (which sits above the @interface) can dispatch it
// through a typed object pointer without needing the full @interface.
@class RAC_URLS_OBJC(URLSessionStreamDelegate);
@protocol RAC_URLS_OBJC(URLSessionStreamDelegateCancellable) <NSObject>
- (void)cancelFromExternal;
@end

// =============================================================================
// State
// =============================================================================
namespace {

static std::atomic<bool> sRegistered{false};
static std::mutex sRegistrationMutex;
static rac_http_transport_ops_t sOps{};

// Caller-provided override for the streaming session. When non-nil,
// `request_stream` / `request_resume` use this session instead of building a
// per-call one. Hosts that want a `.background(...)` session (handled by
// their `AppDelegate handleEventsForBackgroundURLSession`) or custom
// retry/backoff plug it in via `<prefix>_set_streaming_session`.
static std::mutex sStreamingSessionMutex;
static NSURLSession* sStreamingSessionOverride = nil;

// -----------------------------------------------------------------------------
// Stream registry — one entry per in-flight streaming/resume task. Keyed by
// a process-unique uint64 issued by `nextId` rather than
// `URLSessionTask.taskIdentifier`: when a per-call session is constructed
// (the default streaming path), URLSession restarts task identifiers at 1
// per session, so two concurrent streams would collide on key=1 and the
// second insert would silently displace the first — defeating
// `cancelAllStreams()`. Lives only long enough to keep a strong reference
// to the delegate (URLSession holds it weakly via the session's delegate
// property after `finishTasksAndInvalidate`) and to back
// `cancelAllStreams()`.
// -----------------------------------------------------------------------------
struct StreamRegistry {
    std::mutex mutex;
    std::atomic<uint64_t> nextId{1};
    std::unordered_map<uint64_t, RAC_URLS_OBJC(URLSessionStreamDelegate)*> entries;
};

static StreamRegistry& streamRegistry() {
    static StreamRegistry registry;
    return registry;
}

// -----------------------------------------------------------------------------
// Request snapshot — materialize the caller-owned C struct into ObjC types.
// -----------------------------------------------------------------------------
struct RequestSnapshot {
    NSString* method = nil;
    NSURL* url = nil;
    NSString* originalUrlString = nil;
    std::vector<std::pair<std::string, std::string>> headers;
    NSData* body = nil;
    int32_t timeoutMs = 0;
    bool followRedirects = true;
    bool valid = false;

    static RequestSnapshot from(const rac_http_request_t* req) {
        RequestSnapshot snap;
        if (!req || !req->method || !req->url) return snap;
        NSString* methodStr = [NSString stringWithUTF8String:req->method];
        NSString* urlStr = [NSString stringWithUTF8String:req->url];
        if (methodStr.length == 0 || urlStr.length == 0) return snap;
        NSURL* url = [NSURL URLWithString:urlStr];
        if (!url) return snap;

        snap.method = methodStr;
        snap.url = url;
        snap.originalUrlString = urlStr;

        if (req->headers && req->header_count > 0) {
            snap.headers.reserve(req->header_count);
            for (size_t i = 0; i < req->header_count; ++i) {
                const auto& h = req->headers[i];
                if (!h.name || !h.value) continue;
                snap.headers.emplace_back(h.name, h.value);
            }
        }

        if (req->body_bytes && req->body_len > 0) {
            snap.body = [NSData dataWithBytes:req->body_bytes length:req->body_len];
        }

        snap.timeoutMs = req->timeout_ms;
        snap.followRedirects = (req->follow_redirects == RAC_TRUE);
        snap.valid = true;
        return snap;
    }

    NSMutableURLRequest* makeURLRequest(uint64_t resumeFromByte = 0) const {
        NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:url];
        request.HTTPMethod = method;
        for (const auto& h : headers) {
            [request setValue:[NSString stringWithUTF8String:h.second.c_str()]
                forHTTPHeaderField:[NSString stringWithUTF8String:h.first.c_str()]];
        }
        if (body && body.length > 0) {
            request.HTTPBody = body;
        }
        if (timeoutMs > 0) {
            request.timeoutInterval = (NSTimeInterval)timeoutMs / 1000.0;
        }
        if (resumeFromByte > 0) {
            NSString* rangeHeader =
                [NSString stringWithFormat:@"bytes=%llu-", (unsigned long long)resumeFromByte];
            [request setValue:rangeHeader forHTTPHeaderField:@"Range"];
        }
        return request;
    }
};

// -----------------------------------------------------------------------------
// Response writer — fill out_resp with heap-allocated buffers that the C core
// can release via rac_http_response_free / rac_free (malloc / strdup).
// -----------------------------------------------------------------------------
static std::vector<std::pair<std::string, std::string>> extractHeaders(NSHTTPURLResponse* resp) {
    std::vector<std::pair<std::string, std::string>> out;
    NSDictionary* fields = resp.allHeaderFields;
    out.reserve(fields.count);
    for (id key in fields) {
        if (![key isKindOfClass:[NSString class]]) continue;
        id value = fields[key];
        NSString* valueStr = nil;
        if ([value isKindOfClass:[NSString class]]) {
            valueStr = (NSString*)value;
        } else {
            valueStr = [value description];
        }
        const char* kC = [(NSString*)key UTF8String];
        const char* vC = [valueStr UTF8String];
        if (!kC || !vC) continue;
        out.emplace_back(kC, vC);
    }
    return out;
}

static void writeResponse(int32_t status,
                          NSData* bodyBytes,
                          const std::vector<std::pair<std::string, std::string>>& headers,
                          NSString* redirectedURL,
                          uint64_t elapsedMs,
                          rac_http_response_t* out) {
    std::memset(out, 0, sizeof(*out));
    out->status = status;
    out->elapsed_ms = elapsedMs;

    if (bodyBytes && bodyBytes.length > 0) {
        void* buf = std::malloc(bodyBytes.length);
        if (buf) {
            std::memcpy(buf, bodyBytes.bytes, bodyBytes.length);
            out->body_bytes = reinterpret_cast<uint8_t*>(buf);
            out->body_len = bodyBytes.length;
        }
    }

    if (!headers.empty()) {
        size_t count = headers.size();
        size_t bytes = count * sizeof(rac_http_header_kv_t);
        auto* kvs = static_cast<rac_http_header_kv_t*>(std::malloc(bytes));
        if (kvs) {
            std::memset(kvs, 0, bytes);
            for (size_t i = 0; i < count; ++i) {
                kvs[i].name = strdup(headers[i].first.c_str());
                kvs[i].value = strdup(headers[i].second.c_str());
            }
            out->headers = kvs;
            out->header_count = count;
        }
    }

    if (redirectedURL && redirectedURL.length > 0) {
        out->redirected_url = strdup([redirectedURL UTF8String]);
    }
}

static uint64_t monotonicNs() {
    // CLOCK_UPTIME_RAW matches `mach_absolute_time` / Swift's
    // `DispatchTime.now().uptimeNanoseconds` (uptime that does not advance
    // during sleep) without the Mach IPC round-trip and unchecked
    // `kern_return_t` of `host_get_clock_service`.
    return clock_gettime_nsec_np(CLOCK_UPTIME_RAW);
}

static uint64_t elapsedMsSince(uint64_t startNs) {
    uint64_t nowNs = monotonicNs();
    if (nowNs <= startNs) return 0;
    return (nowNs - startNs) / 1000000ULL;
}

static rac_result_t mapTransportError(NSError* error) {
    if (![error.domain isEqualToString:NSURLErrorDomain]) {
        return RAC_ERROR_NETWORK_ERROR;
    }
    switch (error.code) {
        case NSURLErrorTimedOut:
            return RAC_ERROR_TIMEOUT;
        case NSURLErrorCancelled:
            return RAC_ERROR_CANCELLED;
        default:
            return RAC_ERROR_NETWORK_ERROR;
    }
}

// -----------------------------------------------------------------------------
// Shared session (for request_send). Single-shot calls reuse one tuned session.
// -----------------------------------------------------------------------------
static NSURLSession* sharedSession() {
    static NSURLSession* session = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = 60;
        config.timeoutIntervalForResource = 600;
        config.URLCache = nil;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        config.HTTPAdditionalHeaders = nil;
        config.waitsForConnectivity = NO;
        session = [NSURLSession sessionWithConfiguration:config];
    });
    return session;
}

// Helper used by the unregister path AND by external callers via
// `<prefix>_cancel_all_streams`. Defined here so it can sit before the
// concrete @interface — we route through the cancel protocol so the
// forward-declared @class is enough for the compiler.
static void cancelAllStreams() {
    std::vector<id<RAC_URLS_OBJC(URLSessionStreamDelegateCancellable)>> snapshot;
    {
        std::lock_guard<std::mutex> lock(streamRegistry().mutex);
        snapshot.reserve(streamRegistry().entries.size());
        for (auto& kv : streamRegistry().entries) {
            snapshot.push_back(
                (id<RAC_URLS_OBJC(URLSessionStreamDelegateCancellable)>)kv.second);
        }
    }
    // Cancel outside the lock — `URLSessionTask.cancel()` races back through
    // didCompleteWithError on the delegate queue, which removes the entry.
    for (id<RAC_URLS_OBJC(URLSessionStreamDelegateCancellable)> delegate : snapshot) {
        [delegate cancelFromExternal];
    }
}

}  // namespace

// -----------------------------------------------------------------------------
// StreamDelegate — proxies didReceive into the C chunk callback.
//
// Hosts a strong reference to its `task` while live so `cancelAllStreams()`
// can drive `[task cancel]` regardless of where in the URLSession state
// machine we are.
// -----------------------------------------------------------------------------
@interface RAC_URLS_OBJC(URLSessionStreamDelegate) :
    NSObject <NSURLSessionDataDelegate,
              RAC_URLS_OBJC(URLSessionStreamDelegateCancellable)>
@property(nonatomic, assign) rac_http_body_chunk_fn chunkFn;
@property(nonatomic, assign) void* chunkUserData;
@property(nonatomic, strong) dispatch_semaphore_t completion;
@property(nonatomic, strong, nullable) NSHTTPURLResponse* response;
@property(nonatomic, strong, nullable) NSError* error;
@property(nonatomic, assign) uint64_t totalBytesReceived;
@property(nonatomic, assign) uint64_t contentLength;
@property(nonatomic, assign) BOOL cancelled;
@property(nonatomic, assign) uint64_t resumeFromByte;
@property(nonatomic, assign) uint64_t streamId;
@property(nonatomic, weak, nullable) NSURLSessionTask* task;
- (void)cancelFromExternal;
@end

@implementation RAC_URLS_OBJC(URLSessionStreamDelegate)

- (instancetype)initWithChunkFn:(rac_http_body_chunk_fn)fn
                       userData:(void*)data
                 resumeFromByte:(uint64_t)resumeFromByte {
    self = [super init];
    if (self) {
        _chunkFn = fn;
        _chunkUserData = data;
        _completion = dispatch_semaphore_create(0);
        _totalBytesReceived = 0;
        _contentLength = 0;
        _cancelled = NO;
        _resumeFromByte = resumeFromByte;
        _streamId = 0;
    }
    return self;
}

- (void)URLSession:(NSURLSession*)session
          dataTask:(NSURLSessionDataTask*)dataTask
didReceiveResponse:(NSURLResponse*)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        NSHTTPURLResponse* httpResp = (NSHTTPURLResponse*)response;
        self.response = httpResp;
        if (response.expectedContentLength > 0) {
            self.contentLength = (uint64_t)response.expectedContentLength;
        }
        // Resume accounting: when the server actually honored the Range (206),
        // `expectedContentLength` is only the *remaining* bytes — add the
        // resume offset so the chunk callback sees a monotonic
        // `total_written` that tracks absolute file position. For 200
        // responses the server ignored the range and is replaying the full
        // file, so we leave the counter at 0 (the caller will truncate).
        if (httpResp.statusCode == 206 && self.resumeFromByte > 0) {
            self.totalBytesReceived = self.resumeFromByte;
            if (self.contentLength > 0) {
                self.contentLength += self.resumeFromByte;
            }
        }
    }
    completionHandler(NSURLSessionResponseAllow);
}

- (void)URLSession:(NSURLSession*)session
          dataTask:(NSURLSessionDataTask*)dataTask
    didReceiveData:(NSData*)data {
    if (self.cancelled || self.chunkFn == nullptr) return;
    self.totalBytesReceived += data.length;
    rac_bool_t keepGoing = self.chunkFn(
        reinterpret_cast<const uint8_t*>(data.bytes),
        data.length,
        self.totalBytesReceived,
        self.contentLength,
        self.chunkUserData);
    if (keepGoing != RAC_TRUE) {
        self.cancelled = YES;
        [dataTask cancel];
    }
}

- (void)URLSession:(NSURLSession*)session
              task:(NSURLSessionTask*)task
didCompleteWithError:(NSError*)error {
    if (error && !self.cancelled) {
        self.error = error;
    }
    dispatch_semaphore_signal(self.completion);
}

- (void)cancelFromExternal {
    self.cancelled = YES;
    [self.task cancel];
}

@end

// =============================================================================
// Vtable callbacks
// =============================================================================
namespace {

rac_result_t urlsession_request_send(void* /*user_data*/,
                                     const rac_http_request_t* req,
                                     rac_http_response_t* out_resp) {
    if (!req || !out_resp) return RAC_ERROR_INVALID_ARGUMENT;
    RequestSnapshot snap = RequestSnapshot::from(req);
    if (!snap.valid) return RAC_ERROR_INVALID_ARGUMENT;

    NSMutableURLRequest* urlRequest = snap.makeURLRequest(/*resumeFromByte=*/0);
    uint64_t startNs = monotonicNs();

    dispatch_semaphore_t sema = dispatch_semaphore_create(0);
    __block NSData* capturedData = nil;
    __block NSURLResponse* capturedResponse = nil;
    __block NSError* capturedError = nil;

    NSURLSessionDataTask* task = [sharedSession()
        dataTaskWithRequest:urlRequest
          completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
              capturedData = data;
              capturedResponse = response;
              capturedError = error;
              dispatch_semaphore_signal(sema);
          }];
    [task resume];
    dispatch_semaphore_wait(sema, DISPATCH_TIME_FOREVER);

    uint64_t elapsed = elapsedMsSince(startNs);
    if (capturedError) {
        return mapTransportError(capturedError);
    }
    if (![capturedResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        return RAC_ERROR_NETWORK_ERROR;
    }
    NSHTTPURLResponse* httpResp = (NSHTTPURLResponse*)capturedResponse;
    auto headers = extractHeaders(httpResp);
    NSString* finalURL = httpResp.URL.absoluteString;
    NSString* redirected = nil;
    if (finalURL && ![finalURL isEqualToString:snap.originalUrlString]) {
        redirected = finalURL;
    }

    writeResponse((int32_t)httpResp.statusCode, capturedData, headers, redirected, elapsed,
                  out_resp);
    return RAC_SUCCESS;
}

rac_result_t urlsession_request_stream_impl(const rac_http_request_t* req,
                                            rac_http_body_chunk_fn cb,
                                            void* cb_user_data,
                                            rac_http_response_t* out_resp,
                                            uint64_t resumeFromByte) {
    if (!req || !cb || !out_resp) return RAC_ERROR_INVALID_ARGUMENT;
    RequestSnapshot snap = RequestSnapshot::from(req);
    if (!snap.valid) return RAC_ERROR_INVALID_ARGUMENT;

    NSMutableURLRequest* urlRequest = snap.makeURLRequest(resumeFromByte);
    uint64_t startNs = monotonicNs();

    RAC_URLS_OBJC(URLSessionStreamDelegate)* delegate =
        [[RAC_URLS_OBJC(URLSessionStreamDelegate) alloc]
            initWithChunkFn:cb
                   userData:cb_user_data
             resumeFromByte:resumeFromByte];

    // Prefer a host-provided streaming session (useful for apps that need
    // `.background(...)` or custom retry policy); fall back to a per-call
    // session tuned for multi-GB transfers.
    NSURLSession* session = nil;
    BOOL ownsSession = NO;
    {
        std::lock_guard<std::mutex> lock(sStreamingSessionMutex);
        if (sStreamingSessionOverride != nil) {
            session = sStreamingSessionOverride;
            ownsSession = NO;
        }
    }
    if (session == nil) {
        NSURLSessionConfiguration* config =
            [NSURLSessionConfiguration defaultSessionConfiguration];
        config.timeoutIntervalForRequest = snap.timeoutMs > 0
            ? (NSTimeInterval)snap.timeoutMs / 1000.0
            : 60;
        // Resource timeout covers the whole transfer; a 10 GB GGUF over a
        // slow cellular link can legitimately run for hours. Matches the
        // Swift reference (24h ceiling rather than 600s).
        config.timeoutIntervalForResource = 24 * 60 * 60;
        config.URLCache = nil;
        config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;
        // Streaming downloads benefit from NSURLSession queuing a retry when
        // connectivity returns rather than failing fast.
        config.waitsForConnectivity = YES;
        session = [NSURLSession sessionWithConfiguration:config
                                                delegate:delegate
                                           delegateQueue:nil];
        ownsSession = YES;
    }

    NSURLSessionDataTask* task = [session dataTaskWithRequest:urlRequest];
    if (!ownsSession) {
        // Host-provided sessions carry their own delegate. Bind the
        // callbacks directly onto the task via the task-delegate API (iOS
        // 15+). Assign BEFORE we publish the task anywhere (registry,
        // delegate.task backref, [task resume]) — `task.delegate` is a weak
        // property and host-provided sessions can have an active
        // delegateQueue from unrelated in-flight work, so we must guarantee
        // the per-task delegate is wired before any code path
        // (cancelAllStreams via the registry, URLSession's own dispatch on
        // resume) can observe the task. Mirrors the Swift reference's
        // `task.delegate = delegate; task.resume()` ordering in
        // `sdk/runanywhere-swift/Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift`.
        task.delegate = delegate;
    }
    delegate.task = task;
    // Issue a process-unique key so concurrent per-call sessions (each of
    // which restarts `taskIdentifier` at 1) don't displace each other.
    delegate.streamId = streamRegistry().nextId.fetch_add(1, std::memory_order_relaxed);
    {
        std::lock_guard<std::mutex> lock(streamRegistry().mutex);
        streamRegistry().entries[delegate.streamId] = delegate;
    }

    [task resume];
    dispatch_semaphore_wait(delegate.completion, DISPATCH_TIME_FOREVER);

    // Tear down per-call sessions so URLSession releases the delegate
    // reference and flushes pending sockets. Host-owned sessions are left
    // untouched.
    if (ownsSession) {
        [session finishTasksAndInvalidate];
    }
    {
        std::lock_guard<std::mutex> lock(streamRegistry().mutex);
        streamRegistry().entries.erase(delegate.streamId);
    }

    uint64_t elapsed = elapsedMsSince(startNs);
    if (delegate.cancelled) return RAC_ERROR_CANCELLED;
    if (delegate.error) return mapTransportError(delegate.error);
    if (!delegate.response) return RAC_ERROR_NETWORK_ERROR;

    auto headers = extractHeaders(delegate.response);
    NSString* finalURL = delegate.response.URL.absoluteString;
    NSString* redirected = nil;
    if (finalURL && ![finalURL isEqualToString:snap.originalUrlString]) {
        redirected = finalURL;
    }

    // Range-honored disclosure: when the caller asked for a partial
    // (`resumeFromByte > 0`) but the server answered with 200 (full file)
    // instead of 206, the C++ download manager needs to know so it can
    // truncate the destination before replaying bytes. libcurl surfaced
    // this by reporting the HTTP status directly; we mirror that and add
    // an explicit marker header to save the caller a second status-code
    // check.
    if (resumeFromByte > 0) {
        bool honored = (delegate.response.statusCode == 206);
        headers.emplace_back("X-RAC-Range-Honored", honored ? "true" : "false");
    }

    writeResponse((int32_t)delegate.response.statusCode, /*bodyBytes=*/nil, headers, redirected,
                  elapsed, out_resp);
    return RAC_SUCCESS;
}

rac_result_t urlsession_request_stream(void* /*user_data*/,
                                       const rac_http_request_t* req,
                                       rac_http_body_chunk_fn cb,
                                       void* cb_user_data,
                                       rac_http_response_t* out_resp) {
    return urlsession_request_stream_impl(req, cb, cb_user_data, out_resp,
                                          /*resumeFromByte=*/0);
}

rac_result_t urlsession_request_resume(void* /*user_data*/,
                                       const rac_http_request_t* req,
                                       uint64_t resume_from_byte,
                                       rac_http_body_chunk_fn cb,
                                       void* cb_user_data,
                                       rac_http_response_t* out_resp) {
    return urlsession_request_stream_impl(req, cb, cb_user_data, out_resp, resume_from_byte);
}

}  // namespace

// =============================================================================
// Public C entry points (called from the per-SDK Swift façade during init)
// =============================================================================
extern "C" {

void RAC_URLS_CFN(_register_urlsession_transport)(void) {
    std::lock_guard<std::mutex> lock(sRegistrationMutex);
    bool expected = false;
    if (!sRegistered.compare_exchange_strong(expected, true)) {
        RA_HTTP_LOG_DEBUG("URLSession HTTP transport already registered (skipping)");
        return;
    }
    sOps.request_send = urlsession_request_send;
    sOps.request_stream = urlsession_request_stream;
    sOps.request_resume = urlsession_request_resume;
    sOps.init = nullptr;
    sOps.destroy = nullptr;

    rac_result_t rc = rac_http_transport_register(&sOps, nullptr);
    if (rc == RAC_SUCCESS) {
        RA_HTTP_LOG_INFO("URLSession HTTP transport registered");
    } else {
        sRegistered.store(false);
        RA_HTTP_LOG_ERROR("Failed to register URLSession HTTP transport (rc=%{public}d)", rc);
    }
}

void RAC_URLS_CFN(_unregister_urlsession_transport)(void) {
    std::lock_guard<std::mutex> lock(sRegistrationMutex);
    bool expected = true;
    if (!sRegistered.compare_exchange_strong(expected, false)) {
        return;
    }
    rac_http_transport_register(nullptr, nullptr);
    // Cancel every in-flight stream BEFORE clearing — otherwise live
    // delegates would survive past unregister and could still fire chunk
    // callbacks into a host runtime that's been torn down.
    cancelAllStreams();
    {
        std::lock_guard<std::mutex> sessionLock(sStreamingSessionMutex);
        sStreamingSessionOverride = nil;
    }
    RA_HTTP_LOG_INFO("URLSession HTTP transport unregistered");
}

/// Install a custom NSURLSession for streaming downloads (model GGUFs,
/// resume). Passing nil restores the built-in per-call session. Hosts that
/// need a true iOS background session — `URLSessionConfiguration.background(...)`
/// — supply one here and wire `handleEventsForBackgroundURLSession` in
/// their `AppDelegate`, since that hook can only live in the application
/// layer.
///
/// The override is consulted per call; there is no ownership transfer.
/// Thread-safe.
///
/// Exposed as a plain C function so the per-SDK Swift façade can forward
/// `URLSessionHttpTransport.register(streamingSession:)` without needing a
/// module-mapped header.
void RAC_URLS_CFN(_set_streaming_session)(void* session) {
    std::lock_guard<std::mutex> lock(sStreamingSessionMutex);
    sStreamingSessionOverride = (__bridge NSURLSession*)session;
    if (sStreamingSessionOverride != nil) {
        NSString* identifier =
            sStreamingSessionOverride.configuration.identifier ?: @"<default-config>";
        RA_HTTP_LOG_INFO("Streaming session override installed (config=%{public}s)",
                         identifier.UTF8String);
    } else {
        RA_HTTP_LOG_INFO("Streaming session override cleared");
    }
}

/// Cancel every in-flight streaming / resume task. Each pending chunk
/// callback returns to its caller with `RAC_ERROR_CANCELLED` (because
/// `URLSessionTask.cancel()` surfaces as an `NSURLErrorCancelled` which
/// `mapTransportError` maps accordingly). Complements the per-callback
/// `return RAC_FALSE` cancel contract — use this when the SDK is tearing
/// down and there is no callback on the stack to signal.
void RAC_URLS_CFN(_cancel_all_streams)(void) {
    cancelAllStreams();
}

}  // extern "C"

#undef RAC_URLS_CONCAT2
#undef RAC_URLS_CONCAT
#undef RAC_URLS_CFN
#undef RAC_URLS_OBJC
#undef RA_HTTP_LOG_INFO
#undef RA_HTTP_LOG_DEBUG
#undef RA_HTTP_LOG_ERROR
