/**
 * Dev utility: capture screenshots of the local preview for review.
 *
 *   1. npm run build
 *   2. npm run preview          (serves http://localhost:4321)
 *   3. node scripts/dev-screenshot.mjs [outDir]
 *
 * Uses the system Chrome (channel: 'chrome') or the bundled Chromium if PLAYWRIGHT_CHROMIUM=1.
 * Not part of CI; safe to delete if unused.
 */
import { mkdirSync } from 'node:fs';
import { chromium } from 'playwright';

const base = process.env.PREVIEW_URL ?? 'http://localhost:4321';
const outDir = process.argv[2] ?? 'screenshots';
mkdirSync(outDir, { recursive: true });

const pages = [
  { path: '/', name: 'home', fullPage: true },
  { path: '/projects/', name: 'projects', fullPage: true },
  { path: '/projects/p01/', name: 'project-p01', fullPage: true },
  { path: '/cv/', name: 'cv', fullPage: true },
  { path: '/skills/', name: 'skills', fullPage: true },
  { path: '/coverage/', name: 'coverage', fullPage: true },
  { path: '/lab/', name: 'lab', fullPage: true },
  { path: '/contact/', name: 'contact', fullPage: false },
  { path: '/', name: 'home-mobile', fullPage: true, viewport: { width: 390, height: 844 } },
];

const browser = await chromium.launch(
  process.env.PLAYWRIGHT_CHROMIUM === '1' ? {} : { channel: 'chrome' },
);

for (const p of pages) {
  const page = await browser.newPage({
    viewport: p.viewport ?? { width: 1280, height: 900 },
  });
  await page.goto(`${base}${p.path}`, { waitUntil: 'networkidle' });
  await page.screenshot({ path: `${outDir}/${p.name}.png`, fullPage: p.fullPage });
  console.log(`captured ${p.name}.png`);
  await page.close();
}

await browser.close();
console.log('done');
