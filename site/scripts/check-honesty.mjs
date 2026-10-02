/**
 * Honesty gate (AGENTS.md rule R2 and Sections 4.5 / 5.3).
 *
 * This check exists because the easiest way to ruin an honest portfolio is to publish a number
 * that was never measured. It is deliberately a hard failure (exit 1) — it is not a style check.
 *
 * It enforces:
 *  1. A project whose showcase `status` is not `done` must NOT declare a `metrics:` array.
 *     Metrics are only published from real, completed lab runs.
 *  2. Every `metrics[].source` for a `done` project must resolve to a file that actually exists
 *     in that project's folder (rule 4.5: every metric needs a source file).
 *  3. Every `documents[].href` must resolve to an existing business artifact (the PDF that the
 *     site links to, next to its Markdown source).
 *  4. Every `hero` and `gallery[].src` must resolve to an existing file (otherwise the page
 *     ships broken images).
 *
 * Run with `npm run check` (the `checks` workflow does).
 */
import { existsSync, readdirSync, readFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const siteRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');
const repoRoot = resolve(siteRoot, '..');
const projectsDir = join(repoRoot, 'projects');

const errors = [];

function frontmatter(text) {
  const match = text.match(/^---\n([\s\S]*?)\n---/);
  if (!match) return null;
  try {
    return parse(match[1]);
  } catch (error) {
    return { __parseError: String(error) };
  }
}

/** Resolve a showcase path (relative to the project folder) to a repository path. */
function projectFile(folder, ref) {
  return join(projectsDir, folder, ref.replace(/^\.\//, ''));
}

for (const folder of readdirSync(projectsDir)) {
  const showcasePath = join(projectsDir, folder, 'showcase.md');
  if (!existsSync(showcasePath)) continue;
  const data = frontmatter(readFileSync(showcasePath, 'utf8'));
  if (!data) {
    errors.push(`${folder}/showcase.md: no YAML frontmatter found.`);
    continue;
  }
  if (data.__parseError) {
    errors.push(`${folder}/showcase.md: frontmatter is not valid YAML — ${data.__parseError}`);
    continue;
  }

  const status = data.status;
  const metrics = Array.isArray(data.metrics) ? data.metrics : [];

  // 1. No metrics before the project is done.
  if (status !== 'done' && metrics.length > 0) {
    errors.push(
      `${folder}/showcase.md: status is "${status}" but ${metrics.length} metric(s) are declared. ` +
        `Metrics may only be published for a project whose status is "done" (AGENTS.md R2).`,
    );
  }

  // 2. Every metric needs a real source file.
  metrics.forEach((metric, index) => {
    const label = metric?.label ?? `#${index + 1}`;
    const source = metric?.source;
    if (!source) {
      errors.push(`${folder}/showcase.md: metric "${label}" has no source file (AGENTS.md 4.5).`);
      return;
    }
    if (/^(https?:|\/)/.test(source)) return;
    if (!existsSync(projectFile(folder, source))) {
      errors.push(`${folder}/showcase.md: metric "${label}" cites a missing source: ${source}`);
    }
  });

  // 3. Business documents must exist (the site links to the PDF).
  for (const doc of Array.isArray(data.documents) ? data.documents : []) {
    const href = doc?.href;
    if (!href || /^(https?:|\/)/.test(href)) continue;
    if (!existsSync(projectFile(folder, href))) {
      errors.push(`${folder}/showcase.md: document "${doc?.title ?? href}" links to a missing file: ${href}`);
    }
  }

  // 4. Images must exist.
  const images = [
    ...(data.hero ? [{ ref: data.hero, what: 'hero' }] : []),
    ...(Array.isArray(data.gallery) ? data.gallery : []).map((item) => ({
      ref: item?.src,
      what: `gallery image "${item?.alt ?? ''}"`,
    })),
  ];
  for (const { ref, what } of images) {
    if (!ref || /^(https?:|\/)/.test(ref)) continue;
    if (!existsSync(projectFile(folder, ref))) {
      errors.push(`${folder}/showcase.md: ${what} points at a missing file: ${ref}`);
    }
  }
}

if (errors.length > 0) {
  console.error(`\nHonesty check FAILED — ${errors.length} problem(s):\n`);
  for (const error of errors) console.error(`  ✗ ${error}`);
  console.error('\nFix these before the site is built or deployed. Never publish an unmeasured number.\n');
  process.exit(1);
}

console.log('Honesty check: clean (no unmeasured metrics, no broken evidence or document links).');
