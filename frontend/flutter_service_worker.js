self.addEventListener('install',function(){self.skipWaiting();});
self.addEventListener('activate',function(e){e.waitUntil((async()=>{var rs=self.registration?[self.registration]:[];for(var r of rs){try{await r.unregister();}catch(_){}};var ks=await caches.keys();for(var k of ks){try{await caches.delete(k);}catch(_){}}}());});
self.addEventListener('fetch',function(){});
