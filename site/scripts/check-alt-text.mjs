/**
 * Alt-text check (AGENTS.md 5.6): every <img> in the built site must have a non-empty alt.
 * Runs after `npm run build`; skips silently if there is no dist yet.
 */
import { existsSync, readFileSync, readdirSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const siteRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');
const dist = join(siteRoot, 'dist');

if (!existsSync(dist)) {
  console.log('Alt-text check: no dist/ yet — run `npm run build` first (skipping).');
  process.exit(0);
}

const files = readdirSync(dist, { recursive: true })
  .map(String)
  .filter((f) => f.endsWith('.html'));

let problems = 0;
for (const file of files) {
  const html = readFileSync(join(dist, file), 'utf8');
  for (const match of html.matchAll(/<img\b[^>]*>/gi)) {
    const tag = match[0];
    const alt = tag.match(/\balt="([^"]*)"/i);
    if (!alt || alt[1].trim() === '') {
      problems += 1;
      console.warn(`Missing/empty alt: dist/${file}  ${tag.slice(0, 120)}`);
    }
  }
}

if (problems > 0) {
  console.error(`\nAlt-text check FAILED: ${problems} image(s) without alt text.`);
  process.exit(1);
}
console.log(`Alt-text check: clean (${files.length} HTML page(s)).`);
