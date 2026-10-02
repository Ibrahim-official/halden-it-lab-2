/**
 * Placeholder gate (AGENTS.md 5.5).
 *
 * Fails (exit 1) when content that would be published still contains unresolved placeholders:
 *   - any [N] or [X] marker, or a bare TODO, in site/src/data/cv.yaml
 *   - the same in a `done` project's showcase.md
 *   - "your-username" anywhere in cv.yaml (broken public links)
 *
 * By default it reports and exits 0 so local development and the `checks` workflow stay useful
 * while a project is in progress. Set PLACEHOLDER_STRICT=1 (the deploy workflow does) to make it
 * block a deploy.
 */
import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join, resolve } from 'node:path';
import { fileURLToPath } from 'node:url';

const strict = process.env.PLACEHOLDER_STRICT === '1';
const siteRoot = resolve(fileURLToPath(new URL('.', import.meta.url)), '..');
const repoRoot = resolve(siteRoot, '..');

const patterns = [/\bTODO\b/g, /\[N\]/g, /\[X\]/g, /your-username/g];
const findings = [];

function check(file, text, { showcase = false } = {}) {
  const lines = text.split('\n');
  lines.forEach((line, index) => {
    const matched = patterns.filter((pattern) => {
      pattern.lastIndex = 0;
      return pattern.test(line);
    });
    if (matched.length > 0) {
      findings.push(`${file}:${index + 1}  ${line.trim()}`);
    }
  });
}

// 1. cv.yaml — always checked (it feeds the public CV page and PDF).
const cvPath = join(siteRoot, 'src', 'data', 'cv.yaml');
check('site/src/data/cv.yaml', readFileSync(cvPath, 'utf8'));

// 2. Showcase files — only `done` projects must be clean.
const projectsDir = join(repoRoot, 'projects');
if (existsSync(projectsDir)) {
  for (const folder of readdirSync(projectsDir)) {
    const showcase = join(projectsDir, folder, 'showcase.md');
    if (!existsSync(showcase)) continue;
    const text = readFileSync(showcase, 'utf8');
    const status = text.match(/^status:\s*(\S+)/m)?.[1]?.replace(/['"]/g, '');
    if (status === 'done') {
      check(`projects/${folder}/showcase.md`, text, { showcase: true });
    }
  }
}

if (findings.length > 0) {
  console.warn(`\nPlaceholder check: ${findings.length} unresolved placeholder(s):\n`);
  for (const finding of findings) console.warn(`  ${finding}`);
  if (strict) {
    console.error('\nPlaceholder check FAILED (strict mode / deploy gate). Fill these in first.');
    process.exit(1);
  }
  console.warn('\n(Not blocking — set PLACEHOLDER_STRICT=1 to enforce, e.g. before deploying.)\n');
} else {
  console.log('Placeholder check: clean.');
}
