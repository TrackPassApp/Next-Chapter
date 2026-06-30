// Self-uninstalling service worker.
//
// Earlier Flutter Web builds registered an aggressive service worker that
// cached main.dart.js + assets indefinitely, which meant users were still
// being served the stale Jun-27 bundle long after the redeploy — even after
// a "hard refresh", because Ctrl+Shift+R does not bypass service-worker
// fetch handlers.
//
// We now serve a service worker that, on install, claims all clients,
// deletes every cache, and unregisters itself. After one page navigation
// the old SW is gone and the browser falls back to normal HTTP caching
// (controlled by /app/frontend/serve.js — main.dart.js + bundle now also
// has Cache-Control: no-store).
self.addEventListener('install', (event) => {
  self.skipWaiting();
});

self.addEventListener('activate', (event) => {
  event.waitUntil((async () => {
    try {
      const keys = await caches.keys();
      await Promise.all(keys.map((k) => caches.delete(k)));
      await self.registration.unregister();
      const clients = await self.clients.matchAll({ type: 'window' });
      for (const client of clients) {
        // Force the active tabs to fetch fresh assets, not from any old cache.
        client.navigate(client.url);
      }
    } catch (e) {
      // Swallowed — if anything throws we don't want to keep the old SW alive.
    }
  })());
});

// Don't intercept any fetches — let the network (and serve.js Cache-Control
// headers) decide. This is critical: any fetch handler that returns a cached
// response would re-introduce the original bug.
