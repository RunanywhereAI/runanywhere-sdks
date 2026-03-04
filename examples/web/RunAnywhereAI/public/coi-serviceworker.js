/**
 * Cross-Origin Isolation Service Worker
 *
 * Enables SharedArrayBuffer on browsers that don't support COEP: credentialless
 * (Safari/WebKit). This is required for multi-threaded WASM (pthreads).
 *
 * How it works:
 * - Intercepts navigation responses and injects COOP + COEP headers
 * - Intercepts cross-origin responses and injects CORP header
 * - On first install, claims all clients so it activates immediately
 */

self.addEventListener('install', () => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil(self.clients.claim());
});

self.addEventListener('fetch', (event) => {
  const { request } = event;

  // Only handle GET requests
  if (request.method !== 'GET') return;

  if (request.mode === 'navigate') {
    // Navigation requests (HTML pages): inject COOP + COEP headers
    event.respondWith(
      fetch(request).then((response) => {
        const headers = new Headers(response.headers);
        headers.set('Cross-Origin-Opener-Policy', 'same-origin');
        headers.set('Cross-Origin-Embedder-Policy', 'require-corp');
        return new Response(response.body, {
          status: response.status,
          statusText: response.statusText,
          headers,
        });
      })
    );
  } else if (request.url.startsWith(self.location.origin)) {
    // Same-origin requests: pass through unchanged
    return;
  } else {
    // Cross-origin requests: re-fetch and inject CORP header
    event.respondWith(
      fetch(request.url, { mode: 'cors', credentials: 'omit' })
        .then((response) => {
          const headers = new Headers(response.headers);
          headers.set('Cross-Origin-Resource-Policy', 'cross-origin');
          return new Response(response.body, {
            status: response.status,
            statusText: response.statusText,
            headers,
          });
        })
        .catch(() => fetch(request))
    );
  }
});
