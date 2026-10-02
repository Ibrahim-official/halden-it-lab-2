// @ts-check
import { defineConfig } from 'astro/config';
import sitemap from '@astrojs/sitemap';

// The public URL of the site. CHANGE THIS before the first deploy
// (GitHub Pages: https://<username>.github.io/<repo> · Cloudflare Pages: https://<project>.pages.dev).
// It can also be set with the SITE_URL environment variable at build time.
const SITE = process.env.SITE_URL ?? 'https://ibrahim-official.github.io/halden-it-lab';

export default defineConfig({
  site: SITE,
  integrations: [sitemap()],
  trailingSlash: 'ignore',
  build: {
    format: 'directory',
  },
});
