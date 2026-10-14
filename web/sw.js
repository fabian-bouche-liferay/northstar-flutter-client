// Offline service worker for the Northstar Knowledge PWA.
// tool/build_pwa.dart replaces the two placeholders below at build time with
// the content hash of the build and the list of every file it produced.
const VERSION = '__BUILD_VERSION__';
const ASSETS = /*__ASSETS__*/[];

const CACHE = `nmg-kb-${VERSION}`;
const RUNTIME = 'nmg-kb-runtime';

self.addEventListener('install', (event) => {
  event.waitUntil(
    caches.open(CACHE)
      .then((cache) => cache.addAll(ASSETS.map((a) => new Request(a, { cache: 'reload' }))))
      .then(() => self.skipWaiting()),
  );
});

self.addEventListener('activate', (event) => {
  event.waitUntil(
    caches.keys()
      .then((keys) => Promise.all(keys
        .filter((k) => k.startsWith('nmg-kb-') && k !== CACHE && k !== RUNTIME)
        .map((k) => caches.delete(k))))
      .then(() => self.clients.claim()),
  );
});

self.addEventListener('fetch', (event) => {
  const request = event.request;
  if (request.method !== 'GET') return;
  const url = new URL(request.url);

  if (url.origin === self.location.origin) {
    // Liferay APIs: the app keeps its own offline copy of the content.
    if (url.pathname.startsWith('/o/')) return;

    // App entry point: network first so new versions are picked up.
    if (request.mode === 'navigate') {
      event.respondWith(
        fetch(request).catch(() =>
          caches.match(new URL('index.html', self.registration.scope).href)),
      );
      return;
    }
    // Versioned build files: cache first.
    event.respondWith(
      caches.match(request, { ignoreSearch: true }).then((hit) => hit || fetch(request)),
    );
    return;
  }

  // Fonts downloaded by the Flutter engine (Roboto, fallback fonts).
  if (url.hostname === 'fonts.gstatic.com' || url.hostname === 'fonts.googleapis.com') {
    event.respondWith(
      caches.open(RUNTIME).then((cache) => cache.match(request).then((hit) =>
        hit || fetch(request).then((response) => {
          if (response.ok || response.type === 'opaque') cache.put(request, response.clone());
          return response;
        }))),
    );
  }
});
