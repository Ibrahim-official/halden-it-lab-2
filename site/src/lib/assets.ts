/**
 * Helpers for showcase assets.
 *
 * `showcase.md` files reference evidence and documents with paths relative to their project folder,
 * e.g. "./evidence/public/p03-bloodhound-after.png" or "./business/p03-exec-summary.pdf". A prebuild
 * script copies those publishable files into `site/public/projects/<folder>/`, so the public URLs
 * for the examples above are "/projects/p03-ad-security/p03-bloodhound-after.png" and
 * "/projects/p03-ad-security/p03-exec-summary.pdf".
 */

export function projectFolder(repoPath: string): string {
  return repoPath.split('/').filter(Boolean).pop() ?? '';
}

export function assetUrl(repoPath: string, src: string): string {
  if (!src) return '';
  if (src.startsWith('/') || src.startsWith('http')) return src;
  const clean = src
    .replace(/^\.\//, '')
    .replace(/^evidence\/public\//, '')
    .replace(/^business\//, '');
  return `/projects/${projectFolder(repoPath)}/${clean}`;
}

import { GITHUB_REPO } from '../consts';

export function repoUrl(repoPath: string): string {
  // Link into the public GitHub repository.
  return `${GITHUB_REPO}/tree/main/${repoPath}`;
}

export function planUrl(planFile: string): string {
  return `${GITHUB_REPO}/blob/main/docs/plan/${planFile}`;
}

export function sortByOrder<T extends { data: { order: number } }>(entries: T[]): T[] {
  return [...entries].sort((a, b) => a.data.order - b.data.order);
}
