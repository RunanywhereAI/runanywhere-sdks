/**
 * URLSessionHttpTransport.mm
 *
 * Objective-C++ implementation of the URLSession-backed RAC HTTP transport
 * adapter. Mirrors the Swift SDK reference at
 *   sdk/runanywhere-swift/Sources/RunAnywhere/HttpTransport/URLSessionHttpTransport.swift
 * but is implemented in ObjC++ because the RN core pod does not ship a
 * `CRACommons` Swift module map — so we cannot import the C ABI from Swift
 * directly.
 *
 * Exposes two C entry points:
 *   - rn_register_urlsession_transport()   — idempotent, installs the
 *     vtable so subsequent rac_http_request_* calls route through
 *     URLSession instead of libcurl.
 *   - rn_unregister_urlsession_transport() — restores libcurl.
 *
 * Call sites:
 *   - Swift façade in URLSessionHttpTransport.swift
 *   - C++ HybridRunAnywhereCore::initialize(...) — via
 *     rn_register_urlsession_transport() BEFORE any HTTP request fires.
 */

#import <Foundation/Foundation.h>

#include <mach/clock.h>
#include <mach/mach.h>

#include <atomic>
#include <cstdint>
#include <cstdlib>
#include <cstring>
#include <mutex>
#include <vector>

#include "rac/core/rac_error.h"
#include "rac/core/rac_types.h"
#include "rac/infrastructure/http/rac_http_client.h"
#include "rac/infrastructure/http/rac_http_transport.h"

// =============================================================================
// State
// =============================================================================
namespace {

static std::atomic<bool> sRegistered{false};
static std::mutex sRegistrationMutex;
static rac_http_transport_ops_t sOps{};

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

static uint64_t elapsedMsSince(uint64_t startNs) {
    clock_serv_t clockServ;
    mach_timespec_t ts;
    host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &clockServ);
    clock_get_time(clockServ, &ts);
    mach_port_deallocate(mach_task_self(), clockServ);
    uint64_t nowNs = static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL +
                     static_cast<uint64_t>(ts.tv_nsec);
    if (nowNs <= startNs) return 0;
    return (nowNs - startNs) / 1000000ULL;
}

static uint64_t monotonicNs() {
    clock_serv_t clockServ;
    mach_timespec_t ts;
    host_get_clock_service(mach_host_self(), SYSTEM_CLOCK, &clockServ);
    clock_get_time(clockServ, &ts);
    mach_port_deallocate(mach_task_self(), clockServ);
    return static_cast<uint64_t>(ts.tv_sec) * 1000000000ULL +
           static_cast<uint64_t>(ts.tv_nsec);
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
// Shared session (for request_send) and streaming delegate (per-call).
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

}  // namespace

// -----------------------------------------------------------------------------
// StreamDelegate — proxies didReceive into the C chunk callback.
// -----------------------------------------------------------------------------
@interface RAURLSessionStreamDelegate : NSObject <NSURLSessionDataDelegate>
@property(nonatomic, assign) rac_http_body_chunk_fn chunkFn;
@property(nonatomic, assign) void* chunkUserData;
@property(nonatomic, strong) dispatch_semaphore_t completion;
@property(nonatomic, strong, nullable) NSHTTPURLResponse* response;
@property(nonatomic, strong, nullable) NSError* error;
@property(nonatomic, assign) uint64_t totalBytesReceived;
@property(nonatomic, assign) uint64_t contentLength;
@property(nonatomic, assign) BOOL cancelled;
@end

@implementation RAURLSessionStreamDelegate

- (instancetype)initWithChunkFn:(rac_http_body_chunk_fn)fn userData:(void*)data {
    self = [super init];
    if (self) {
        _chunkFn = fn;
        _chunkUserData = data;
        _completion = dispatch_semaphore_create(0);
        _totalBytesReceived = 0;
        _contentLength = 0;
        _cancelled = NO;
    }
    return self;
}

- (void)URLSession:(NSURLSession*)session
          dataTask:(NSURLSessionDataTask*)dataTask
didReceiveResponse:(NSURLResponse*)response
 completionHandler:(void (^)(NSURLSessionResponseDisposition))completionHandler {
    if ([response isKindOfClass:[NSHTTPURLResponse class]]) {
        self.response = (NSHTTPURLResponse*)response;
        if (response.expectedContentLength > 0) {
            self.contentLength = (uint64_t)response.expectedContentLength;
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

    NSURLSessionConfiguration* config = [NSURLSessionConfiguration defaultSessionConfiguration];
    config.timeoutIntervalForRequest = snap.timeoutMs > 0
        ? (NSTimeInterval)snap.timeoutMs / 1000.0
        : 60;
    config.timeoutIntervalForResource = MAX(config.timeoutIntervalForRequest, 600);
    config.URLCache = nil;
    config.requestCachePolicy = NSURLRequestReloadIgnoringLocalAndRemoteCacheData;

    RAURLSessionStreamDelegate* delegate =
        [[RAURLSessionStreamDelegate alloc] initWithChunkFn:cb userData:cb_user_data];
    NSURLSession* session = [NSURLSession sessionWithConfiguration:config
                                                          delegate:delegate
                                                     delegateQueue:nil];
    NSURLSessionDataTask* task = [session dataTaskWithRequest:urlRequest];
    [task resume];
    dispatch_semaphore_wait(delegate.completion, DISPATCH_TIME_FOREVER);
    [session finishTasksAndInvalidate];

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
// Public C entry points (called from Swift façade + C++ init)
// =============================================================================
extern "C" {

void rn_register_urlsession_transport(void) {
    std::lock_guard<std::mutex> lock(sRegistrationMutex);
    bool expected = false;
    if (!sRegistered.compare_exchange_strong(expected, true)) {
        NSLog(@"[URLSessionHttpTransport] already registered (skipping)");
        return;
    }
    sOps.request_send = urlsession_request_send;
    sOps.request_stream = urlsession_request_stream;
    sOps.request_resume = urlsession_request_resume;
    sOps.init = nullptr;
    sOps.destroy = nullptr;

    rac_result_t rc = rac_http_transport_register(&sOps, nullptr);
    if (rc == RAC_SUCCESS) {
        NSLog(@"[URLSessionHttpTransport] URLSession HTTP transport registered");
    } else {
        sRegistered.store(false);
        NSLog(@"[URLSessionHttpTransport] failed to register (rc=%d)", rc);
    }
}

void rn_unregister_urlsession_transport(void) {
    std::lock_guard<std::mutex> lock(sRegistrationMutex);
    bool expected = true;
    if (!sRegistered.compare_exchange_strong(expected, false)) {
        return;
    }
    rac_http_transport_register(nullptr, nullptr);
    NSLog(@"[URLSessionHttpTransport] URLSession HTTP transport unregistered");
}

}  // extern "C"
