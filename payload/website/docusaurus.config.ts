import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';
import {getDocsDomainCatalog} from './domainCatalog';

const docsDomainCatalog = getDocsDomainCatalog();
const docsAuthoringProxyPath = '/__ue_docs_api__';
const docsAuthoringProxyPlugin = () => ({
  name: 'ue-docs-authoring-proxy',
  configureWebpack() {
    return {
      devServer: {
        proxy: [
          {
            context: [docsAuthoringProxyPath],
            target: 'http://127.0.0.1:38473',
            changeOrigin: true,
            secure: false,
            pathRewrite: {
              [`^${docsAuthoringProxyPath}`]: '',
            },
          },
        ],
      },
    } as any;
  },
});

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
  plugins: [docsAuthoringProxyPlugin],

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
            '<a class="navbar__item navbar__link ue-navbar-settings-link clean-btn" href="/site-settings" aria-label="Site settings" title="Site settings"><svg class="ue-navbar-settings-link__icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.9" stroke-linecap="round" stroke-linejoin="round" aria-hidden="true"><circle cx="12" cy="12" r="3"></circle><path d="M19.4 15a1.65 1.65 0 0 0 .33 1.82l.06.06a2 2 0 1 1-2.83 2.83l-.06-.06a1.65 1.65 0 0 0-1.82-.33a1.65 1.65 0 0 0-1 1.51V21a2 2 0 1 1-4 0v-.09a1.65 1.65 0 0 0-1-1.51a1.65 1.65 0 0 0-1.82.33l-.06.06a2 2 0 1 1-2.83-2.83l.06-.06a1.65 1.65 0 0 0 .33-1.82a1.65 1.65 0 0 0-1.51-1H3a2 2 0 1 1 0-4h.09a1.65 1.65 0 0 0 1.51-1a1.65 1.65 0 0 0-.33-1.82l-.06-.06a2 2 0 1 1 2.83-2.83l.06.06a1.65 1.65 0 0 0 1.82.33h.01a1.65 1.65 0 0 0 .99-1.51V3a2 2 0 1 1 4 0v.09a1.65 1.65 0 0 0 .99 1.51h.01a1.65 1.65 0 0 0 1.82-.33l.06-.06a2 2 0 1 1 2.83 2.83l-.06.06a1.65 1.65 0 0 0-.33 1.82v.01a1.65 1.65 0 0 0 1.51.99H21a2 2 0 1 1 0 4h-.09a1.65 1.65 0 0 0-1.51.99z"></path></svg></a>',
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
