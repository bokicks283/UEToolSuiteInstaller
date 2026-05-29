import { themes as prismThemes } from 'prism-react-renderer';
import type { Config } from '@docusaurus/types';
import type * as Preset from '@docusaurus/preset-classic';

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
    hooks: {
      onBrokenMarkdownLinks: 'throw',
    },
  },

  i18n: {
    defaultLocale: 'en',
    locales: ['en'],
  },

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
        {
          to: '/docs/',
          position: 'left',
          label: 'Overview',
        },
        {
          type: 'doc',
          docId: 'Pipeline/README',
          position: 'left',
          label: 'Workflow',
        },
        {
          type: 'doc',
          docId: 'Setup',
          position: 'left',
          label: 'Setup',
        },
      ],
    },
    footer: {
      style: 'dark',
      links: [
        {
          title: 'Start',
          items: [
            {
              label: 'Overview',
              to: '/docs/',
            },
            {
              label: 'Setup',
              to: '/docs/setup',
            },
          ],
        },
        {
          title: 'Build',
          items: [
            {
              label: 'Workflow',
              to: '/docs/workflow',
            },
            {
              label: 'Testing',
              to: '/docs/testing',
            },
          ],
        },
        {
          title: 'Reference',
          items: [
            {
              label: 'Coding Standards',
              to: '/docs/coding-standards',
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
  } satisfies Preset.ThemeConfig,
};

export default config;
