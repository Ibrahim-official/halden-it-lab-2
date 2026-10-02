/**
 * Copies sanitized showcase assets from the project folders into the site's public directory.
 *
 *   projects/<folder>/evidence/public/**  ->  site/public/projects/<folder>/**
 *   projects/<folder>/business/*.pdf      ->  site/public/projects/<folder>/
 *
 * The site's showcase frontmatter references evidence and business documents with paths relative
 * to the project folder (e.g. "./evidence/public/p03-hero.svg", "./business/p03-brief.pdf").
 * Those files are never committed under site/public — they are copied at dev/build time from the
 * single source of truth.
 *
 * Runs automatically via the `predev` and `prebuild` npm scripts.
 */
import { cpSync, existsSync, mkdirSync, readdirSync, rmSync, statSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const siteRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');
const repoRoot = resolve(siteRoot, '..');
const projectsDir = join(repoRoot, 'projects');
const targetRoot = join(siteRoot, 'public', 'projects');

if (!existsSync(projectsDir)) {
  console.warn(`[assets] No projects directory at ${projectsDir} — skipping.`);
  process.exit(0);
}

// Rebuild the target from scratch so removed evidence disappears from the site too.
rmSync(targetRoot, { recursive: true, force: true });
mkdirSync(targetRoot, { recursive: true });

let copied = 0;
for (const entry of readdirSync(projectsDir)) {
  const sources = [];
  const evidence = join(projectsDir, entry, 'evidence', 'public');
  if (existsSync(evidence) && statSync(evidence).isDirectory()) sources.push(evidence);
  const business = join(projectsDir, entry, 'business');
  if (existsSync(business) && statSync(business).isDirectory()) sources.push(business);

  const files = [];
  for (const source of sources) {
    for (const f of readdirSync(source, { recursive: true })) {
      const full = join(source, String(f));
      if (!statSync(full).isFile()) continue;
      // Only the sanitized, publishable artifact types leave the repository.
      if (source === business && !/\.pdf$/i.test(String(f))) continue;
      files.push(String(f));
    }
  }
  if (files.length === 0) continue;

  const target = join(targetRoot, entry);
  mkdirSync(target, { recursive: true });
  for (const source of sources) {
    cpSync(source, target, { recursive: true, filter: (src) => source !== business || /\.pdf$/i.test(src) || statSync(src).isDirectory() });
  }
  copied += files.length;
  console.log(`[assets] ${entry}: ${files.length} file(s)`);
}

console.log(`[assets] Done — ${copied} file(s) copied to public/projects/.`);
