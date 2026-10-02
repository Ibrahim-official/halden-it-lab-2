#!/usr/bin/env node
/**
 * Render a Markdown business artifact to a clean A4 PDF, so that every document the
 * portfolio website links to exists as a real PDF built from the same Markdown source
 * (AGENTS.md Section 4.7 item 4). Uses the Playwright Chromium already installed for
 * the CV PDF build, so there is no extra dependency.
 *
 * Usage (from the site/ folder):
 *   npm run docs:pdf -- ../projects/p01-core-infrastructure/business/p01-brief.md
 *   npm run docs:pdf -- <input.md> [output.pdf]
 *
 * Supports: front matter (dropped), #..#### headings, tables, ordered/unordered lists,
 * blockquotes, fenced code, rules, **bold**, *italic*, `code`, [text](url).
 */
import { readFileSync, writeFileSync, mkdirSync, existsSync } from 'node:fs';
import { dirname, resolve, basename } from 'node:path';
import { chromium } from 'playwright';

const [inputArg, outArg] = process.argv.slice(2);
if (!inputArg) {
  console.error('Usage: npm run docs:pdf -- <input.md> [output.pdf]');
  process.exit(2);
}
const input = resolve(inputArg);
if (!existsSync(input)) {
  console.error(`Not found: ${input}`);
  process.exit(2);
}
const output = outArg
  ? resolve(outArg)
  : input.replace(/\.md$/i, '') + '.pdf';

const escapeHtml = (s) =>
  s.replace(/&/g, '&amp;').replace(/</g, '&lt;').replace(/>/g, '&gt;');

function inline(text) {
  let s = escapeHtml(text);
  s = s.replace(/`([^`]+)`/g, '<code>$1</code>');
  s = s.replace(/\*\*([^*]+)\*\*/g, '<strong>$1</strong>');
  s = s.replace(/(^|\W)\*([^*]+)\*(?=\W|$)/g, '$1<em>$2</em>');
  s = s.replace(/\[([^\]]+)\]\(([^)]+)\)/g, '<a href="$2">$1</a>');
  return s;
}

function markdownToHtml(md) {
  const lines = md.replace(/^---\n[\s\S]*?\n---\n/, '').replace(/\r\n/g, '\n').split('\n');
  const out = [];
  let i = 0;
  const listStack = [];
  let inCode = false;

  const closeLists = (toDepth = 0) => {
    while (listStack.length > toDepth) out.push(`</${listStack.pop()}>`);
  };

  while (i < lines.length) {
    const line = lines[i];

    if (/^```/.test(line)) {
      if (inCode) {
        out.push('</code></pre>');
        inCode = false;
      } else {
        closeLists();
        out.push('<pre><code>');
        inCode = true;
      }
      i += 1;
      continue;
    }
    if (inCode) {
      out.push(escapeHtml(line));
      i += 1;
      continue;
    }
    if (!line.trim()) {
      closeLists();
      i += 1;
      continue;
    }
    const heading = line.match(/^(#{1,6})\s+(.*)$/);
    if (heading) {
      closeLists();
      const level = heading[1].length;
      out.push(`<h${level}>${inline(heading[2])}</h${level}>`);
      i += 1;
      continue;
    }
    if (/^(---|\*\*\*|___)\s*$/.test(line)) {
      closeLists();
      out.push('<hr />');
      i += 1;
      continue;
    }
    if (/^\|/.test(line)) {
      closeLists();
      const rows = [];
      while (i < lines.length && /^\|/.test(lines[i])) {
        rows.push(lines[i]);
        i += 1;
      }
      const cells = (row) =>
        row.trim().replace(/^\|/, '').replace(/\|$/, '').split('|').map((c) => c.trim());
      const header = cells(rows[0]);
      const body = rows.slice(/^\|[\s:|-]+\|$/.test(rows[1] ?? '') ? 2 : 1);
      out.push('<table>');
      out.push('<thead><tr>' + header.map((c) => `<th>${inline(c)}</th>`).join('') + '</tr></thead>');
      out.push('<tbody>');
      for (const row of body) {
        out.push('<tr>' + cells(row).map((c) => `<td>${inline(c)}</td>`).join('') + '</tr>');
      }
      out.push('</tbody></table>');
      continue;
    }
    const quote = line.match(/^>\s?(.*)$/);
    if (quote) {
      closeLists();
      const body = [];
      while (i < lines.length && /^>\s?/.test(lines[i])) {
        body.push(lines[i].replace(/^>\s?/, ''));
        i += 1;
      }
      out.push(`<blockquote>${body.map((b) => inline(b)).join('<br />')}</blockquote>`);
      continue;
    }
    const bullet = line.match(/^(\s*)[-*+]\s+(.*)$/);
    const ordered = line.match(/^(\s*)\d+[.)]\s+(.*)$/);
    if (bullet || ordered) {
      const indent = Math.floor((bullet ?? ordered)[1].length / 2) + 1;
      const tag = bullet ? 'ul' : 'ol';
      if (listStack.length < indent) {
        out.push(`<${tag}>`);
        listStack.push(tag);
      }
      closeLists(indent);
      out.push(`<li>${inline((bullet ?? ordered)[2])}</li>`);
      i += 1;
      continue;
    }
    closeLists();
    const para = [line];
    i += 1;
    while (i < lines.length && lines[i].trim() && !/^(#|\||>|```|\s*[-*+]\s|\s*\d+[.)]\s)/.test(lines[i])) {
      para.push(lines[i]);
      i += 1;
    }
    out.push(`<p>${para.map(inline).join(' ')}</p>`);
  }
  closeLists();
  if (inCode) out.push('</code></pre>');
  return out.join('\n');
}

const title = basename(input).replace(/\.md$/i, '').replace(/[-_]/g, ' ');
const html = `<!doctype html>
<html lang="en"><head><meta charset="utf-8" /><title>${escapeHtml(title)}</title>
<style>
  :root { color-scheme: light; }
  @page { size: A4; margin: 16mm 15mm; }
  * { box-sizing: border-box; }
  body { font-family: "Segoe UI", system-ui, -apple-system, "Helvetica Neue", Arial, sans-serif;
         font-size: 10.5pt; line-height: 1.45; color: #0f172a; margin: 0; }
  h1 { font-size: 19pt; margin: 0 0 2mm; color: #0f172a; }
  h2 { font-size: 13pt; margin: 7mm 0 2mm; padding-bottom: 1mm; border-bottom: 1px solid #cbd5e1; }
  h3 { font-size: 11.5pt; margin: 5mm 0 1.5mm; }
  h4 { font-size: 10.5pt; margin: 4mm 0 1mm; }
  p { margin: 0 0 2.5mm; }
  ul, ol { margin: 0 0 2.5mm; padding-left: 6mm; }
  li { margin: 0.6mm 0; }
  table { width: 100%; border-collapse: collapse; margin: 2mm 0 4mm; font-size: 9.5pt; }
  th, td { border: 1px solid #cbd5e1; padding: 1.4mm 2mm; text-align: left; vertical-align: top; }
  th { background: #f1f5f9; font-weight: 600; }
  code { font-family: "Cascadia Mono", Consolas, "SF Mono", monospace; font-size: 9pt;
         background: #f1f5f9; padding: 0.3mm 1mm; border-radius: 1mm; }
  pre { background: #f8fafc; border: 1px solid #e2e8f0; border-radius: 1.5mm;
        padding: 2.5mm; overflow-wrap: anywhere; white-space: pre-wrap; }
  pre code { background: none; padding: 0; }
  blockquote { margin: 2mm 0; padding: 1.5mm 3mm; border-left: 3px solid #0f766e;
               background: #f0fdfa; color: #134e4a; }
  hr { border: none; border-top: 1px solid #e2e8f0; margin: 5mm 0; }
  a { color: #0f766e; text-decoration: none; }
  .doc-footer { margin-top: 8mm; padding-top: 2mm; border-top: 1px solid #e2e8f0;
                font-size: 8.5pt; color: #64748b; }
</style></head>
<body>
${markdownToHtml(readFileSync(input, 'utf8'))}
<div class="doc-footer">Halden Distribution Ltd. — home-lab portfolio artifact (fictional company, real configurations). Generated from ${escapeHtml(basename(input))} on ${new Date().toISOString().slice(0, 10)}.</div>
</body></html>`;

const browser = await chromium.launch();
const page = await browser.newPage();
await page.setContent(html, { waitUntil: 'load' });
mkdirSync(dirname(output), { recursive: true });
await page.pdf({ path: output, format: 'A4', printBackground: true, displayHeaderFooter: false });
await browser.close();
console.log(`Wrote ${output}`);
