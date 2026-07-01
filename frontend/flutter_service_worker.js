// Neutered service worker — self-uninstalls, never caches anything.
self.addEventListener('install', function () { self.skipWaiting(); });
self.addEventListener('activate', function (e) {
  e.waitUntil((async () => {
    var regs = await self.registration ? [self.registration] : [];
    for (var r of regs) { try { await r.unregister(); } catch (_) {} }
    var ks = await caches.keys();
    for (var k of ks) { try { await caches.delete(k); } catch (_) {} }
  })());
});
self.addEventListener('fetch', function () {});
