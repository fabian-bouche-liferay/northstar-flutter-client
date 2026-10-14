{{flutter_js}}
{{flutter_build_config}}

// No serviceWorkerSettings: the PWA uses its own service worker (sw.js),
// registered from index.html.
_flutter.loader.load({
  onEntrypointLoaded: async function (engineInitializer) {
    const appRunner = await engineInitializer.initializeEngine();
    document.getElementById('splash')?.remove();
    await appRunner.runApp();
  },
});
