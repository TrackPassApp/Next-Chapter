// Minimal static server for the Next Chapter Flutter web build.
// Serves files from this directory, with SPA fallback to index.html.
// Listens on PORT (default 3000) so supervisor's existing 'yarn start' just works.

const http = require('http');
const fs = require('fs');
const path = require('path');

const PORT = parseInt(process.env.PORT || '3000', 10);
const HOST = process.env.HOST || '0.0.0.0';
const ROOT = __dirname;

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.js':   'application/javascript; charset=utf-8',
  '.mjs':  'application/javascript; charset=utf-8',
  '.css':  'text/css; charset=utf-8',
  '.json': 'application/json; charset=utf-8',
  '.wasm': 'application/wasm',
  '.png':  'image/png',
  '.jpg':  'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.svg':  'image/svg+xml',
  '.gif':  'image/gif',
  '.ico':  'image/x-icon',
  '.webp': 'image/webp',
  '.ttf':  'font/ttf',
  '.otf':  'font/otf',
  '.woff': 'font/woff',
  '.woff2':'font/woff2',
  '.map':  'application/json; charset=utf-8',
  '.txt':  'text/plain; charset=utf-8',
};

function sendFile(res, abs, status = 200) {
  fs.stat(abs, (err, stat) => {
    if (err || !stat.isFile()) {
      res.writeHead(404, { 'Content-Type': 'text/plain' });
      res.end('Not found');
      return;
    }
    const ext = path.extname(abs).toLowerCase();
    const type = MIME[ext] || 'application/octet-stream';
    // Never cache HTML, JS, or the service worker — these change on every
    // redeploy and we cannot afford the browser/SW to keep the old bundle.
    // Static assets (images, fonts, wasm) can be cached briefly.
    const noStore =
      ext === '.html' ||
      ext === '.js' ||
      ext === '.mjs' ||
      ext === '.json';
    res.writeHead(status, {
      'Content-Type': type,
      'Content-Length': stat.size,
      'Cache-Control': noStore ? 'no-store, no-cache, must-revalidate' : 'public, max-age=300',
      'X-Content-Type-Options': 'nosniff',
    });
    fs.createReadStream(abs).pipe(res);
  });
}

const server = http.createServer((req, res) => {
  // Reject path traversal
  let urlPath;
  try {
    urlPath = decodeURIComponent(new URL(req.url, 'http://x').pathname);
  } catch (_) {
    res.writeHead(400);
    res.end('Bad request');
    return;
  }
  if (urlPath.includes('\0')) {
    res.writeHead(400);
    res.end('Bad request');
    return;
  }

  let rel = urlPath.replace(/^\/+/, '');
  if (rel === '' || rel === '/') rel = 'index.html';

  const abs = path.join(ROOT, rel);
  if (!abs.startsWith(ROOT)) {
    res.writeHead(403);
    res.end('Forbidden');
    return;
  }

  fs.stat(abs, (err, stat) => {
    if (!err && stat.isFile()) {
      sendFile(res, abs);
      return;
    }
    // SPA fallback for client-side routes like /admin, /browse, /diagnostics
    if (req.method === 'GET' && !path.extname(rel)) {
      sendFile(res, path.join(ROOT, 'index.html'));
      return;
    }
    res.writeHead(404, { 'Content-Type': 'text/plain' });
    res.end('Not found');
  });
});

server.listen(PORT, HOST, () => {
  console.log(`Next Chapter static server listening on ${HOST}:${PORT}`);
  console.log(`Serving from: ${ROOT}`);
});
