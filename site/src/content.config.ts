import { defineCollection } from 'astro:content';
import { glob, file } from 'astro/loaders';
import { z } from 'astro/zod';
import { parse } from 'yaml';

/**
 * One collection entry per project, loaded from `projects/<folder>/showcase.md`
 * (AGENTS.md Section 5.3). `planned` projects publish title, tagline and status only —
 * metrics and evidence are added when the project is Done.
 */
const showcase = defineCollection({
  loader: glob({
    // The project folders live at the repository root, one level above the site/ project.
    base: '../projects',
    pattern: '*/showcase.md',
    // Every folder contains a "showcase.md", so the file name alone is not unique.
    // Use the parent folder name as the entry id (e.g. "p01-core-infrastructure").
    generateId: ({ entry }) => entry.split('/').filter(Boolean).slice(-2, -1)[0] ?? entry,
  }),
  schema: z.object({
    id: z.string().regex(/^p\d{2}$/, 'id must look like p01'),
    order: z.number().int().min(1).max(10),
    title: z.string(),
    tagline: z.string(),
    status: z.enum(['planned', 'in-progress', 'done']),
    started: z.coerce.date().optional(),
    completed: z.coerce.date().optional(),
    roles: z.array(z.enum(['sysadmin', 'it-support'])).default([]),
    skills: z.array(z.string()).default([]),
    jd_bullets: z.array(z.string()).default([]),
    metrics: z
      .array(
        z.object({
          label: z.string(),
          before: z.string(),
          after: z.string(),
          better: z.enum(['lower', 'higher']).optional(),
          // Path to the source file in the project's evidence/public/ folder.
          source: z.string(),
        }),
      )
      .default([]),
    hero: z.string().optional(),
    gallery: z
      .array(
        z.object({
          src: z.string(),
          alt: z.string(),
          caption: z.string().optional(),
        }),
      )
      .default([]),
    documents: z.array(z.object({ title: z.string(), href: z.string() })).default([]),
    repo_path: z.string(),
    video: z.string().optional(),
    cv_bullets: z.array(z.string()).default([]),
    lab_note: z.string(),
  }),
});

/**
 * The CV data file is the single source of truth for the home page, the /cv page and the
 * generated PDF (AGENTS.md Section 5.5). The phone number is deliberately absent here;
 * a private local build can include it (see site/README.md).
 */
const cv = defineCollection({
  loader: file('./src/data/cv.yaml', {
    parser: (text) => [{ id: 'cv', ...parse(text) }],
  }),
  schema: z.object({
    name: z.string(),
    headline: z.string(),
    location: z.string(),
    links: z.object({
      email: z.string(),
      linkedin: z.string(),
      github: z.string(),
      site: z.string().optional().default(''),
    }),
    summary: z.string(),
    skills: z.array(z.object({ group: z.string(), items: z.array(z.string()) })),
    experience: z.array(
      z.object({
        role: z.string(),
        org: z.string(),
        place: z.string().optional(),
        start: z.string(),
        end: z.string().nullable(),
        bullets: z.array(z.string()),
      }),
    ),
    education: z.array(
      z.object({
        degree: z.string(),
        org: z.string(),
        start: z.string(),
        end: z.string(),
        notes: z.string().optional(),
        fyp: z.string().optional(),
      }),
    ),
    certifications: z.array(z.string()).default([]),
    projects_on_cv: z.array(z.string()).default([]),
  }),
});

export const collections = { showcase, cv };
