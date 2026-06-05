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
      items: navbarDomainItems,
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Docs',
          items: [
            {
              label: 'Home',
              to: '/docs/',
            },
          ],
        },
        {
          title: 'Domains',
          items: [
            {
              label: 'Docs Home',
              to: '/docs/',
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
