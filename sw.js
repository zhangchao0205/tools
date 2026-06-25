// Service Worker for 壁纸制作器 PWA
var CACHE = 'wallpaper-maker-v1';
var FILES = [
  './',
  './wallpaper-maker.html'
];

self.addEventListener('install', function(e) {
  e.waitUntil(
    caches.open(CACHE).then(function(cache) {
      return cache.addAll(FILES);
    })
  );
  self.skipWaiting();
});

self.addEventListener('activate', function(e) {
  e.waitUntil(
    caches.keys().then(function(keys) {
      return Promise.all(keys.filter(function(k){return k!==CACHE}).map(function(k){return caches.delete(k)}));
    })
  );
  self.clients.claim();
});

self.addEventListener('fetch', function(e) {
  e.respondWith(
    caches.match(e.request).then(function(r) {
      return r || fetch(e.request).then(function(resp) {
        if(resp.ok && resp.type==='basic' && !/sockjs|hot-update|browser-sync/.test(e.request.url)){
          var clone = resp.clone();
          caches.open(CACHE).then(function(cache){cache.put(e.request, clone)});
        }
        return resp;
      });
    })
  );
});
