#!/usr/bin/env node
/**
 * Normalise every project's `showcase.md` frontmatter and status wording so that all ten pages
 * follow the same model (AGENTS.md Sections 5.3 and 5.4):
 *
 *   - `status: planned` -> `status: in-progress` with `started: 2026-10-02`, because every
 *     project now has a complete build kit. `done` is never set: only a real lab run earns that.
 *   - `hero:` -> the project's own architecture SVG when it exists in `evidence/public/`.
 *   - `documents:` -> one entry per `business/*.md`, pointing at the PDF the site links to.
 *   - `video: ""` -> dropped when empty.
 *   - the body's trailing status note is rewritten to the "in progress" wording.
 *
 * It is deliberately conservative: it rewrites the block for a key and leaves every other field
 * exactly as written, so hand-authored titles and bullets survive. `metrics:` is never touched and
 * never added — publishing a number requires a real measurement and a source file (rule R2,
 * enforced by check-honesty.mjs).
 *
 * Usage (from the site/ folder):  node scripts/normalise-showcases.mjs [--check]
 */
import { existsSync, readdirSync, readFileSync, writeFileSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';
import { parse } from 'yaml';

const check = process.argv.includes('--check');
const siteRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');
const repoRoot = resolve(siteRoot, '..');
const projectsDir = join(repoRoot, 'projects');

const STARTED = '2026-10-02';
const STATUS_NOTE =
  '> Status: **in progress**. The build kit (scripts, configs, runbooks, business artifacts) is\n' +
  '> complete; lab execution runs phase by phase. Metrics, diagrams and evidence are published only\n' +
  '> from real runs (the Definition of Done is in `AGENTS.md`, Section 4.7), and progress is tracked\n' +
  '> in `PROGRESS.md`.';

/** Human-readable document title from a business filename. */
function titleFor(name) {
  const base = name.replace(/\.md$/, '').replace(/^p\d{2}[-_]/, '');
  return base
    .split(/[-_]/)
    .map((word) => word.charAt(0).toUpperCase() + word.slice(1))
    .join(' ');
}

/** Replace a whole top-level `key:` block with new text ("" removes the key). */
function replaceBlock(yamlText, key, newBlock) {
  const lines = yamlText.split('\n');
  const start = lines.findIndex((line) => new RegExp(`^${key}:`).test(line));
  if (start === -1) return newBlock ? `${yamlText.trimEnd()}\n${newBlock}` : yamlText;
  let end = start + 1;
  while (end < lines.length && !/^[A-Za-z_][\w-]*:/.test(lines[end])) end += 1;
  const kept = [
    ...lines.slice(0, start),
    ...(newBlock ? newBlock.split('\n') : []),
    ...lines.slice(end),
  ];
  return kept.join('\n').replace(/\n{3,}/g, '\n\n');
}

const quote = (value) => `"${String(value).replace(/"/g, '\\"')}"`;

let changed = 0;
const problems = [];

for (const folder of readdirSync(projectsDir).sort()) {
  const dir = join(projectsDir, folder);
  const showcasePath = join(dir, 'showcase.md');
  if (!existsSync(showcasePath)) continue;

  const text = readFileSync(showcasePath, 'utf8');
  const match = text.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n([\s\S]*)$/);
  if (!match) {
    problems.push(`${folder}: no frontmatter`);
    continue;
  }
  let front = match[1];
  let body = match[2];

  let data;
  try {
    data = parse(front);
  } catch (error) {
    problems.push(`${folder}: frontmatter is not valid YAML (${String(error.message).split('\n')[0]})`);
    continue;
  }

  if (data.status === 'planned') {
    front = front.replace(/^status:\s*planned\s*$/m, 'status: in-progress');
    data.status = 'in-progress';
  }
  if (data.status !== 'done' && !data.started && !/^started:/m.test(front)) {
    front = front.replace(/^status:.*$/m, (line) => `${line}\nstarted: ${STARTED}`);
  }
  if (data.status === 'done' && !data.started) problems.push(`${folder}: done without a started date`);

  // Hero: the project's own architecture diagram, once it is published.
  const prefix = folder.split('-')[0];
  const heroFile = `${prefix}-architecture.svg`;
  if (existsSync(join(dir, 'evidence', 'public', heroFile))) {
    front = replaceBlock(front, 'hero', `hero: ./evidence/public/${heroFile}`);
  } else if (!/^hero:/m.test(front)) {
    problems.push(`${folder}: no architecture SVG in evidence/public/`);
  }

  // Documents: one PDF link per business artifact.
  const businessDir = join(dir, 'business');
  const artifacts = existsSync(businessDir)
    ? readdirSync(businessDir).filter((f) => f.endsWith('.md')).sort()
    : [];
  if (artifacts.length > 0) {
    const block = [
      'documents:',
      ...artifacts.flatMap((f) => [
        `  - title: ${quote(titleFor(f))}`,
        `    href: ./business/${f.replace(/\.md$/, '.pdf')}`,
      ]),
    ].join('\n');    front = replaceBlock(front, 'documents', block);
  } else {
    problems.push(`${folder}: no business Markdown artifact to link`);
  }

  if (!data.cv_bullets || data.cv_bullets.length === 0) problems.push(`${folder}: no cv_bullets`);
  if (data.metrics && data.metrics.length > 0 && data.status !== 'done') {
    problems.push(`${folder}: metrics present while not done (honesty)`);
  }
  if (!data.repo_path) problems.push(`${folder}: no repo_path`);

  if (data.video === '' || data.video === null) front = replaceBlock(front, 'video', '');
  front = front.replace(/\s+$/, '');

  body = body.replace(/(?:\n*> Status:[\s\S]*?)$/m, '').trimEnd() + '\n\n' + STATUS_NOTE + '\n';

  const next = `---\n${front}\n---\n\n${body.replace(/^\n+/, '')}`;
  if (next !== text) {
    if (!check) writeFileSync(showcasePath, next);
    changed += 1;
  }
}

console.log(
  check
    ? `Showcase normalisation: ${changed} file(s) would change.`
    : `Showcase normalisation: ${changed} file(s) updated.`,
);
if (problems.length > 0) {
  console.log(`\nNeeds attention (${problems.length}):`);
  for (const problem of problems) console.log(`  - ${problem}`);
}
