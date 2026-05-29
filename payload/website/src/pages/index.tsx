import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import useDocusaurusContext from '@docusaurus/useDocusaurusContext';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';

type SuiteBrandingFields = {
  suiteProjectName?: string;
  suiteDocsTitle?: string;
  suiteTagline?: string;
  suiteThemeId?: string;
};

type NavbarLogoConfig = {
  src?: string;
  alt?: string;
};

const primaryActions = [
  {
    title: 'Setup',
    body: 'Bootstrap the repo, verify suite prerequisites, and align local tooling in one pass.',
    to: '/docs/setup',
  },
  {
    title: 'Workflow',
    body: 'Use the documented branch, hook, and validation flows without adding unnecessary process overhead.',
    to: '/docs/workflow',
  },
  {
    title: 'Testing',
    body: 'Run suite tests and branch-mutating validations with clear expectations and recovery guidance.',
    to: '/docs/testing',
  },
];

const sectionCards = [
  {
    title: 'Workflow',
    body: 'Branch discipline, binary safety, repo hygiene, and daily development flow.',
    to: '/docs/workflow',
    badge: 'Process',
  },
  {
    title: 'Testing',
    body: 'What the automation covers, what must stay green, and how to validate safely.',
    to: '/docs/testing',
    badge: 'Validation',
  },
  {
    title: 'Coding Standards',
    body: 'The current Unreal C++ guidance and the local snapshot workflow that backs it.',
    to: '/docs/coding-standards',
    badge: 'Code',
  },
];

const readOrder = [
  {label: 'Setup', to: '/docs/setup'},
  {label: 'Workflow', to: '/docs/workflow'},
  {label: 'Testing', to: '/docs/testing'},
  {label: 'Coding Standards', to: '/docs/coding-standards'},
];

const principles = [
  'Keep tooling predictable across fresh installs and updater runs.',
  'Keep docs in-repo so workflow and code review stay aligned.',
  'Automate what can regress, and keep manual checks focused on true edge cases.',
];

const metrics = [
  {value: 'UE 5', label: 'Engine target'},
  {value: '14', label: 'Theme presets'},
  {value: '1', label: 'Unified installer'},
];

export default function Home(): ReactNode {
  const {siteConfig} = useDocusaurusContext();
  const customFields = (siteConfig.customFields ?? {}) as SuiteBrandingFields;
  const projectName = customFields.suiteProjectName?.trim() || 'UE Project';
  const docsTitle = customFields.suiteDocsTitle?.trim() || `${projectName} Docs`;
  const siteTagline =
    customFields.suiteTagline?.trim() ||
    'Repo tooling, Unreal workflow, and living project documentation.';
  const activeTheme = customFields.suiteThemeId?.trim() || 'neutral';

  const navbarLogo = (((siteConfig.themeConfig as {navbar?: {logo?: NavbarLogoConfig}} | undefined)?.navbar)?.logo);
  const logoSrc = useBaseUrl(navbarLogo?.src ?? '/img/logo.svg');
  const logoAlt = navbarLogo?.alt ?? `${docsTitle} logo`;

  return (
    <Layout title={docsTitle} description={siteTagline}>
      <header className={styles.hero}>
        <div className={styles.heroBackdrop} />
        <div className={styles.heroGrid}>
          <div className={styles.heroCopy}>
            <div className={styles.brandLockup}>
              <img className={styles.brandMark} src={logoSrc} alt={logoAlt} />
              <p className={styles.eyebrow}>Project documentation hub</p>
            </div>
            <Heading as="h1" className={styles.title}>
              {projectName}
            </Heading>
            <p className={styles.subtitle}>
              {siteTagline}
            </p>
            <div className={styles.actions}>
              <Link className="button button--primary button--lg" to="/docs/">
                Open Overview
              </Link>
              <Link className={styles.ghostButton} to="/docs/workflow">
                Read Workflow
              </Link>
            </div>
            <div className={styles.metrics}>
              {metrics.map((item) => (
                <div key={item.label} className={styles.metric}>
                  <strong>{item.value}</strong>
                  <span>{item.label}</span>
                </div>
              ))}
            </div>
          </div>
          <aside className={styles.heroPanel}>
            <p className={styles.panelEyebrow}>Recommended read order</p>
            <Heading as="h2">Get setup and workflow aligned first.</Heading>
            <ol className={styles.readOrder}>
              {readOrder.map((item) => (
                <li key={item.label}>
                  <Link to={item.to}>{item.label}</Link>
                </li>
              ))}
            </ol>
            <p className={styles.themeNote}>Active theme preset: {activeTheme}</p>
          </aside>
        </div>
      </header>
      <main>
        <section className={styles.section}>
          <div className={styles.sectionHeader}>
            <p className={styles.sectionLabel}>Daily execution</p>
            <Heading as="h2">Use docs as an operational reference.</Heading>
            <p>
              Keep the next important decision obvious instead of documenting everything.
            </p>
          </div>
          <div className={styles.grid}>
            {primaryActions.map((item) => (
              <Link key={item.title} className={styles.primaryCard} to={item.to}>
                <Heading as="h3">{item.title}</Heading>
                <p>{item.body}</p>
                <span>Open</span>
              </Link>
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <div className={styles.sectionHeader}>
            <p className={styles.sectionLabel}>Core sections</p>
            <Heading as="h2">Keep the important pages close.</Heading>
          </div>
          <div className={styles.cardGrid}>
            {sectionCards.map((item) => (
              <Link key={item.title} className={styles.card} to={item.to}>
                <span className={styles.cardBadge}>{item.badge}</span>
                <Heading as="h3">{item.title}</Heading>
                <p>{item.body}</p>
                <span className={styles.cardLink}>Open section</span>
              </Link>
            ))}
          </div>
        </section>

        <section className={styles.section}>
          <div className={styles.principles}>
            <div className={styles.principlesCopy}>
              <p className={styles.sectionLabel}>Operating principles</p>
              <Heading as="h2">Keep docs clear, current, and actionable.</Heading>
            </div>
            <div className={styles.principlesList}>
              {principles.map((item) => (
                <div key={item} className={styles.principle}>
                  <span className={styles.principleMark} />
                  <p>{item}</p>
                </div>
              ))}
            </div>
          </div>
        </section>

        <section className={styles.section}>
          <div className={styles.closingPanel}>
            <Heading as="h2">Documentation should support delivery.</Heading>
            <p>
              Keep the workflow readable, setup trustworthy, and validation repeatable across installs.
            </p>
            <div className={styles.actions}>
              <Link className="button button--primary button--lg" to="/docs/workflow">
                Workflow
              </Link>
              <Link className={styles.ghostButton} to="/docs/testing">
                Validation
              </Link>
            </div>
          </div>
        </section>
      </main>
    </Layout>
  );
}
