#!/usr/bin/env node
/**
 * Build every business artifact Markdown file into a PDF beside it, so that all documents
 * the website links to (AGENTS.md Section 4.7 item 4) exist as real PDFs.
 *
 * Usage (from the site/ folder):  npm run docs:pdf:all
 * Renders projects/<project>/business/**\/*.md -> same path with .pdf
 */
import { readdirSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { execFileSync } from 'node:child_process';

const repoRoot = process.cwd().replace(/\/site$/, '');
const projectsDir = join(repoRoot, 'projects');
const here = new URL('.', import.meta.url).pathname;
const renderer = join(here, 'md-to-pdf.mjs');

function walk(dir, acc = []) {
  for (const name of readdirSync(dir)) {
    const full = join(dir, name);
    if (statSync(full).isDirectory()) {
      if (name === 'node_modules' || name === '.git') continue;
      walk(full, acc);
    } else if (name.endsWith('.md') && /[\\/]business[\\/]/.test(full)) {
      acc.push(full);
    }
  }
  return acc;
}

const files = walk(projectsDir);
if (files.length === 0) {
  console.log('No business artifacts found.');
  process.exit(0);
}
for (const file of files) {
  execFileSync(process.execPath, [renderer, file], { stdio: 'inherit' });
}
console.log(`\n${files.length} business artifact PDF(s) built.`);
