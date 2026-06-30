// Cache-busted bootstrap for build 20260630160418. No service worker.
if (!window._flutter) { window._flutter = {}; }
_flutter.buildConfig = {"engineRevision":"a10d8ac38de835021c8d2f920dbf50a920ccc030","builds":[{"compileTarget":"dart2js","renderer":"canvaskit","mainJsPath":"main.20260630160418.dart.js"}]};

// Load the official Flutter loader (flutter.js) first so window._flutter.loader exists.
(function() {
  var s = document.createElement('script');
  s.src = 'flutter.js?v=20260630160418';
  s.onload = function() {
    _flutter.loader.load({});  // no serviceWorkerSettings → no SW registration
  };
  document.head.appendChild(s);
})();
