/**
 * Site-wide constants. Update GITHUB_REPO and LINKEDIN before the first deploy.
 */

// The public repository for this portfolio (used for "view the code" links).
export const GITHUB_REPO = 'https://github.com/ibrahim-official/halden-it-lab';

export const SITE_TITLE = 'Muhammad Ibrahim Akmal — IT Support & Systems';

export const SITE_DESCRIPTION =
  'IT Support and junior System Administration portfolio: a documented home lab (Windows Server, ' +
  'Active Directory, Entra ID, hardening, patching, networking, SIEM, backup/DR, ITSM and IT ' +
  'governance) built around one simulated 85-user company, with evidence behind every number.';

export const NAV_LINKS = [
  { href: '/', label: 'Home' },
  { href: '/projects', label: 'Projects' },
  { href: '/skills', label: 'Skills' },
  { href: '/coverage', label: 'Job-ad coverage' },
  { href: '/lab', label: 'The lab' },
  { href: '/cv', label: 'CV' },
  { href: '/contact', label: 'Contact' },
];

export const STATUS_LABEL: Record<string, string> = {
  planned: 'planned',
  'in-progress': 'in progress',
  done: 'done',
};
