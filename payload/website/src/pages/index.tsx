import type {ReactNode} from 'react';
import Link from '@docusaurus/Link';
import useBaseUrl from '@docusaurus/useBaseUrl';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';

const primaryActions = [
  {
    title: 'Start Setup',
    body: 'Bootstrap the repo, verify the tools, and get back into Unreal quickly.',
    to: '/docs/setup',
  },
  {
    title: 'Ship Safely',
    body: 'Use the repo workflow, guarded binary tooling, and testing notes without letting process take over the project.',
    to: '/docs/workflow',
  },
  {
    title: 'Get Running',
    body: 'Bootstrap the repo, sync the project, and get back into Unreal quickly.',
    to: '/docs/setup',
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
  'Build the project first. Tooling exists to remove friction, not create it.',
  'Keep docs in the repo so workflow, validation, and code stay in the same review loop.',
  'Use the documented Unreal-safe flows for project-file regeneration and validation.',
];

const metrics = [
  {value: 'UE 5', label: 'Engine target'},
  {value: '1', label: 'Docs site'},
  {value: '1', label: 'Tooling suite'},
];

export default function Home(): ReactNode {
  const logoSrc = useBaseUrl('/img/logo.svg');

  return (
    <Layout
      title="UE Project Docs"
      description="Repo tooling, Unreal workflow, and project documentation.">
      <header className={styles.hero}>
        <div className={styles.heroBackdrop} />
        <div className={styles.heroGrid}>
          <div className={styles.heroCopy}>
            <div className={styles.brandLockup}>
              <img className={styles.brandMark} src={logoSrc} alt="UE project mark" />
              <p className={styles.eyebrow}>Unreal project overview</p>
            </div>
            <Heading as="h1" className={styles.title}>
              UE Project
            </Heading>
            <p className={styles.subtitle}>
              A lean project overview for Unreal workflow, repo tooling, and
              the rules that actually matter during development.
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
            <p className={styles.panelEyebrow}>Recommended Read Order</p>
            <Heading as="h2">Start building the game, not wrestling the tooling.</Heading>
            <ol className={styles.readOrder}>
              {readOrder.map((item) => (
                <li key={item.label}>
                  <Link to={item.to}>{item.label}</Link>
                </li>
              ))}
            </ol>
          </aside>
        </div>
      </header>
      <main>
        <section className={styles.section}>
          <div className={styles.sectionHeader}>
            <p className={styles.sectionLabel}>Build Tonight</p>
            <Heading as="h2">Use the docs like a production handbook.</Heading>
            <p>
              The goal is not to document everything. The goal is to keep the
              next important decision obvious.
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
            <p className={styles.sectionLabel}>Core Sections</p>
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
              <p className={styles.sectionLabel}>Ground Rules</p>
              <Heading as="h2">Keep the docs sharp. Keep the process lean.</Heading>
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
            <Heading as="h2">Docs belong next to the work.</Heading>
            <p>
              This project does not need a sprawling wiki. It needs a readable
              workflow, trustworthy setup notes, and enough structure to help
              the team ship.
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
