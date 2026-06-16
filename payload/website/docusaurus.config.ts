import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import {getDocsDomainCatalog} from './domainCatalog';

const docsDomainCatalog = getDocsDomainCatalog();
const navbarDomainItems = [
  ...(docsDomainCatalog.generalDocs
    ? [
        {
          type: 'docSidebar' as const,
          sidebarId: docsDomainCatalog.generalDocs.sidebarId,
          position: 'left' as const,
          label: docsDomainCatalog.generalDocs.label,
        },
      ]
    : []),
  ...docsDomainCatalog.domains.map((domain) =>
    domain.docId
      ? {
          type: 'doc' as const,
          docId: domain.docId,
          position: 'left' as const,
          label: domain.label,
        }
      : {
          type: 'docSidebar' as const,
          sidebarId: domain.sidebarId,
          position: 'left' as const,
          label: domain.label,
        },
  ),
];

const config: Config = {
  title: 'UE Project Docs',
  tagline: 'Repo tooling, Unreal workflow, and living project documentation for UE projects.',
  favicon: 'img/themes/neutral/favicon.svg',

  future: {
    v4: true,
  },

  url: 'https://example.com',
  baseUrl: '/',
  organizationName: 'ue-project',
  projectName: 'ue-project-docs',

  onBrokenLinks: 'throw',
  markdown: {
    mermaid: true,
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

  clientModules: ['./src/clientModules/lucideShortcodes.ts'],
  themes: ['@docusaurus/theme-mermaid'],

  presets: [
    [
      'classic',
      {
        docs: {
          path: '../Docs',
          routeBasePath: 'docs',
          sidebarPath: './sidebars.ts',
          exclude: ['**/Current/**', '**/Templates/**'],
        },
        blog: false,
        theme: {
          customCss: './src/css/custom.css',
        },
      } satisfies Preset.Options,
    ],
  ],

  customFields: {
    suiteProjectName: 'UE Project',
    suiteDocsTitle: 'UE Project Docs',
    suiteTagline: 'Repo tooling, Unreal workflow, and living project documentation for UE projects.',
    suiteThemeId: 'neutral',
  },

  themeConfig: {
    image: 'img/themes/neutral/social-card.svg',
    announcementBar: {
      id: 'lean-docs',
      content: 'Living repo docs. Keep setup and workflow clear, lean, and project-focused.',
      backgroundColor: '#1f4f7f',
      textColor: '#f2f7fc',
      isCloseable: true,
    },
    colorMode: {
      defaultMode: 'light',
      respectPrefersColorScheme: true,
    },
    navbar: {
      title: 'UE Project',
      logo: {
        alt: 'UE Project Docs',
        src: 'img/themes/neutral/logo.svg',
      },
      items: [
        ...navbarDomainItems,
        {
          type: 'html',
          position: 'right',
          value:
            '<a class="navbar__item navbar__link ue-navbar-settings-link clean-btn" href="/site-settings" aria-label="Site settings" title="Site settings"><svg class="ue-navbar-settings-link__icon" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 8.75a3.25 3.25 0 1 0 0 6.5a3.25 3.25 0 0 0 0-6.5Zm8.15 2.32l-1.52-.25a6.95 6.95 0 0 0-.64-1.54l.9-1.25a1 1 0 0 0-.1-1.29l-1.78-1.78a1 1 0 0 0-1.29-.1l-1.25.9a6.95 6.95 0 0 0-1.54-.64l-.25-1.52A1 1 0 0 0 11.7 2h-2.4a1 1 0 0 0-.98.83l-.25 1.52a6.95 6.95 0 0 0-1.54.64l-1.25-.9a1 1 0 0 0-1.29.1L2.21 5.97a1 1 0 0 0-.1 1.29l.9 1.25c-.28.49-.5 1-.64 1.54l-1.52.25a1 1 0 0 0-.83.98v2.4a1 1 0 0 0 .83.98l1.52.25c.14.54.36 1.05.64 1.54l-.9 1.25a1 1 0 0 0 .1 1.29l1.78 1.78a1 1 0 0 0 1.29.1l1.25-.9c.49.28 1 .5 1.54.64l.25 1.52a1 1 0 0 0 .98.83h2.4a1 1 0 0 0 .98-.83l.25-1.52c.54-.14 1.05-.36 1.54-.64l1.25.9a1 1 0 0 0 1.29-.1l1.78-1.78a1 1 0 0 0 .1-1.29l-.9-1.25c.28-.49.5-1 .64-1.54l1.52-.25a1 1 0 0 0 .83-.98v-2.4a1 1 0 0 0-.83-.98Z"></path></svg></a>',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Home',
              to: '/',
            },
          ],
        },
        {
          title: 'Domains',
          items: [
            {
              label: 'Workflow & Standards',
              to: '/docs/workflow-standards',
            },
            {
              label: 'Project Docs',
              to: '/docs/project-docs',
            },
          ],
        },
      ],
      copyright: `UE project documentation for the current project state. ${new Date().getFullYear()}.`,
    },
    prism: {
      theme: prismThemes.github,
      darkTheme: prismThemes.dracula,
    },
    mermaid: {
      theme: {light: 'neutral', dark: 'dark'},
    },
  } satisfies Preset.ThemeConfig,
};

export default config;
