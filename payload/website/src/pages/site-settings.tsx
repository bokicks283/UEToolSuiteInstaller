import type {ReactNode} from 'react';
import Layout from '@theme/Layout';
import Heading from '@theme/Heading';

import styles from './index.module.css';
import AuthoringConnectionStatusCard from '../theme/authoring/AuthoringConnectionStatusCard';
import SiteAdminPanel from '../theme/authoring/SiteAdminPanel';
import {useDocsAuthoringApi} from '../theme/authoring/api';

export default function SiteSettingsPage(): ReactNode {
  const {connectionStatus, requestJson, retryConnection, runtimeAvailable, runtimeReady} = useDocsAuthoringApi();
  const showRuntimeError =
    runtimeReady && !runtimeAvailable && connectionStatus.kind !== 'checking' && connectionStatus.kind !== 'connected';

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
          {showRuntimeError ? (
            <div className={styles.primaryCard}>
              <AuthoringConnectionStatusCard status={connectionStatus} onRetry={retryConnection} />
            </div>
          ) : null}
          {runtimeReady && runtimeAvailable ? <SiteAdminPanel requestJson={requestJson} /> : null}
        </section>
      </main>
    </Layout>
  );
}
