import type {ReactNode} from 'react';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';
import SiteAdminPanel from '../theme/authoring/SiteAdminPanel';
import {useDocsAuthoringApi} from '../theme/authoring/api';

export default function SiteSettingsPage(): ReactNode {
  const {requestJson, runtimeAvailable, runtimeReady} = useDocsAuthoringApi();

  return (
    <Layout title="Site Settings" description="Theme, branding, domain, and override controls for the docs site.">
      <main>
        <section className={styles.section}>
          <div className={styles.sectionHeader}>
            <p className={styles.sectionLabel}>Administration</p>
            <Heading as="h1">Site Settings</Heading>
            <p>Manage theme, branding, domains, and suite override policy from a stable dedicated route.</p>
          </div>
          {!runtimeReady ? <p>Checking the local docs runtime...</p> : null}
          {runtimeReady && !runtimeAvailable ? (
            <div className={styles.primaryCard}>
              <Heading as="h3">Local authoring runtime not reachable</Heading>
              <p>Start the docs API host or docs dev server, then refresh this page.</p>
            </div>
          ) : null}
          {runtimeReady && runtimeAvailable ? <SiteAdminPanel requestJson={requestJson} /> : null}
        </section>
      </main>
    </Layout>
  );
}
