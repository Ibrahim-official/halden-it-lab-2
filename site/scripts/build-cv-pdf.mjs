/**
 * Generates the CV PDF from the built site (AGENTS.md 5.5).
 *
 *   1. Build the site first:            npm run build
 *   2. Generate the PDF:                npm run build:cv
 *   3. Private variant with the phone:  CV_PHONE="+92 3XX XXXXXXX" npm run build && npm run build:cv
 *
 * It serves dist/ with a tiny built-in static server (no daemon, CI-safe), loads /cv in headless
 * Chromium and prints it to A4 using the page's print stylesheet. The output lands in dist/cv/
 * so it deploys with the rest of the site. The public build never contains the phone number.
 */
import { createServer } from 'node:http';
import { existsSync, mkdirSync, statSync } from 'node:fs';
import { readFile } from 'node:fs/promises';
import { extname, join, normalize, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { chromium } from 'playwright';

const siteRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');
const dist = join(siteRoot, 'dist');
const outDir = join(dist, 'cv');
const outFile = join(outDir, 'Muhammad-Ibrahim-Akmal-CV.pdf');

if (!existsSync(join(dist, 'index.html'))) {
  console.error('No build found in dist/. Run `npm run build` first.');
  process.exit(1);
}
mkdirSync(outDir, { recursive: true });

const MIME = {
  '.html': 'text/html; charset=utf-8',
  '.css': 'text/css',
  '.js': 'text/javascript',
  '.mjs': 'text/javascript',
  '.svg': 'image/svg+xml',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
  '.webp': 'image/webp',
  '.avif': 'image/avif',
  '.gif': 'image/gif',
  '.ico': 'image/x-icon',
  '.pdf': 'application/pdf',
  '.xml': 'application/xml',
  '.txt': 'text/plain; charset=utf-8',
  '.json': 'application/json',
  '.webmanifest': 'application/manifest+json',
  '.woff': 'font/woff',
  '.woff2': 'font/woff2',
};

function resolveFile(pathname) {
  const clean = normalize(decodeURIComponent(pathname)).replace(/^([/\\]|\.\.[/\\])+/, '');
  const candidate = join(dist, clean);
  if (!candidate.startsWith(dist)) return null;
  if (existsSync(candidate)) {
    const stats = statSync(candidate);
    if (stats.isFile()) return candidate;
    const index = join(candidate, 'index.html');
    if (existsSync(index)) return index;
  }
  return null;
}

const server = createServer(async (req, res) => {
  const file = resolveFile(new URL(req.url ?? '/', 'http://localhost').pathname);
  if (!file) {
    res.writeHead(404, { 'content-type': 'text/plain' });
    res.end('Not found');
    return;
  }
  try {
    const body = await readFile(file);
    res.writeHead(200, { 'content-type': MIME[extname(file)] ?? 'application/octet-stream' });
    res.end(body);
  } catch (error) {
    res.writeHead(500, { 'content-type': 'text/plain' });
    res.end(String(error));
  }
});

await new Promise((resolveListen) => server.listen(0, '127.0.0.1', resolveListen));
const port = server.address().port;
console.log(`[cv] static server on http://127.0.0.1:${port}`);

let browser;
try {
  // Bundled Chromium (installed by `npx playwright install chromium`, as CI does).
  browser = await chromium.launch();
} catch {
  // Local fallback: system Chrome.
  browser = await chromium.launch({ channel: 'chrome' });
}

try {
  const page = await browser.newPage();
  await page.goto(`http://127.0.0.1:${port}/cv/`, { waitUntil: 'networkidle' });
  await page.emulateMedia({ media: 'print' });
  await page.pdf({
    path: outFile,
    format: 'A4',
    printBackground: true,
    preferCSSPageSize: true,
  });
  console.log(`[cv] wrote ${outFile}`);
  if (process.env.CV_PHONE) {
    console.log('[cv] private variant: phone number WAS included (do not commit or deploy this file).');
    console.log('[cv] remember: the deployed site must be rebuilt WITHOUT CV_PHONE.');
  }
} finally {
  await browser.close();
  server.close();
}
