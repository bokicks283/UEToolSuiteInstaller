import React, {useEffect, useMemo, useState} from 'react';

import styles from '../DocItem/Layout/ueAuthoring.module.css';
import {getSidebarIdFromDomainPath, type DocsDomainsPayload} from './api';

type RequestJsonFn = <T>(path: string, init?: RequestInit) => Promise<T>;

type ThemeCatalogResponse = {
  ok: true;
  catalog: {
    defaultTheme: string;
    themes: Array<{id: string; label: string; description?: string}>;
  };
};

type SiteConfigResponse = {
  ok: true;
  config: {
    ownership?: {installMode?: string} | null;
    knownOverridablePaths: string[];
    overrides: {
      theme: {
        themeId?: string;
        logoPath?: string;
        faviconPath?: string;
        socialCardPath?: string;
      };
      fileOverrides: Array<{path: string; mode: 'suite' | 'project'}>;
    };
  };
};

type SiteMutationResponse = {ok: true; result?: unknown};

type Props = {
  open: boolean;
  onClose: () => void;
  requestJson: RequestJsonFn;
};

export default function SiteAdminPanel({open, onClose, requestJson}: Props): React.JSX.Element | null {
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [errorText, setErrorText] = useState('');
  const [themeOptions, setThemeOptions] = useState<Array<{id: string; label: string; description?: string}>>([]);
  const [knownPaths, setKnownPaths] = useState<string[]>([]);
  const [themeId, setThemeId] = useState('neutral');
  const [logoPath, setLogoPath] = useState('');
  const [faviconPath, setFaviconPath] = useState('');
  const [socialCardPath, setSocialCardPath] = useState('');
  const [overrideMap, setOverrideMap] = useState<Record<string, '' | 'suite' | 'project'>>({});
  const [domains, setDomains] = useState<DocsDomainsPayload['domains']>([]);
  const [domainName, setDomainName] = useState('');
  const [domainTitle, setDomainTitle] = useState('');
  const [domainDescription, setDomainDescription] = useState('');
  const nextSidebarId = useMemo(() => {
    const trimmedDomainName = domainName.trim();
    return trimmedDomainName ? getSidebarIdFromDomainPath(trimmedDomainName) : '';
  }, [domainName]);

  useEffect(() => {
    if (!open) {
      return;
    }

    let cancelled = false;
    async function load() {
      setLoading(true);
      setErrorText('');
      try {
        const [catalogPayload, configPayload] = await Promise.all([
          requestJson<ThemeCatalogResponse>('/api/site/theme-catalog'),
          requestJson<SiteConfigResponse>('/api/site/config'),
        ]);
        const domainsPayload = await requestJson<{ok: true; domains: DocsDomainsPayload}>('/api/domains');
        if (cancelled) {
          return;
        }

        setThemeOptions(catalogPayload.catalog.themes ?? []);
        setKnownPaths(configPayload.config.knownOverridablePaths ?? []);
        setThemeId(configPayload.config.overrides.theme.themeId || catalogPayload.catalog.defaultTheme || 'neutral');
        setLogoPath(configPayload.config.overrides.theme.logoPath || '');
        setFaviconPath(configPayload.config.overrides.theme.faviconPath || '');
        setSocialCardPath(configPayload.config.overrides.theme.socialCardPath || '');

        const nextMap: Record<string, '' | 'suite' | 'project'> = {};
        for (const candidate of configPayload.config.knownOverridablePaths ?? []) {
          nextMap[candidate] = '';
        }
        for (const entry of configPayload.config.overrides.fileOverrides ?? []) {
          nextMap[entry.path] = entry.mode;
        }
        setOverrideMap(nextMap);
        setDomains(domainsPayload.domains.domains ?? []);
      } catch (error) {
        if (!cancelled) {
          setErrorText(error instanceof Error ? error.message : 'Failed to load site settings.');
        }
      } finally {
        if (!cancelled) {
          setLoading(false);
        }
      }
    }

    void load();
    return () => {
      cancelled = true;
    };
  }, [open, requestJson]);

  const overrideRows = useMemo(() => {
    return knownPaths.map((path) => ({
      path,
      mode: overrideMap[path] ?? '',
    }));
  }, [knownPaths, overrideMap]);

  async function applyTheme(): Promise<void> {
    setSaving(true);
    setErrorText('');
    try {
      await requestJson<SiteMutationResponse>('/api/site/theme', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          themeId,
          logoPath,
          faviconPath,
          socialCardPath,
        }),
      });
      window.location.reload();
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to apply site theme.');
    } finally {
      setSaving(false);
    }
  }

  async function applyBranding(): Promise<void> {
    setSaving(true);
    setErrorText('');
    try {
      await requestJson<SiteMutationResponse>('/api/site/branding', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          logoPath,
          faviconPath,
          socialCardPath,
        }),
      });
      window.location.reload();
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to apply site branding.');
    } finally {
      setSaving(false);
    }
  }

  async function applyOverrides(): Promise<void> {
    setSaving(true);
    setErrorText('');
    try {
      const entries = Object.entries(overrideMap)
        .filter(([, mode]) => mode === 'suite' || mode === 'project')
        .map(([path, mode]) => ({path, mode}));
      await requestJson<SiteMutationResponse>('/api/site/overrides', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({entries}),
      });
      window.location.reload();
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to update site overrides.');
    } finally {
      setSaving(false);
    }
  }

  async function createDomain(): Promise<void> {
    const trimmedDomainName = domainName.trim();
    if (!trimmedDomainName) {
      return;
    }
    setSaving(true);
    setErrorText('');
    try {
      await requestJson<SiteMutationResponse>('/api/create/domain', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          domainName: trimmedDomainName,
          title: domainTitle.trim(),
          description: domainDescription.trim(),
        }),
      });
      window.location.reload();
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to create domain.');
    } finally {
      setSaving(false);
    }
  }

  if (!open) {
    return null;
  }

  return (
    <div className={styles.siteAdminBackdrop} role="presentation" onClick={onClose}>
      <div
        className={styles.siteAdminPanel}
        role="dialog"
        aria-modal="true"
        aria-label="Site settings"
        onClick={(event) => event.stopPropagation()}
      >
        <div className={styles.siteAdminHeader}>
          <div>
            <h2>Site Settings</h2>
            <p>Theme, branding, and managed override policy.</p>
          </div>
          <button type="button" className={styles.secondaryButton} onClick={onClose} disabled={saving}>
            Close
          </button>
        </div>

        {loading ? <p className={styles.statusText}>Loading site settings...</p> : null}
        {errorText ? <p className={styles.errorText}>{errorText}</p> : null}

        <div className={styles.siteAdminSection}>
          <label className={styles.siteAdminField}>
            <span>Theme preset</span>
            <select value={themeId} onChange={(event) => setThemeId(event.target.value)} disabled={saving || loading}>
              {themeOptions.map((option) => (
                <option key={option.id} value={option.id}>
                  {option.label} ({option.id})
                </option>
              ))}
            </select>
          </label>
          <div className={styles.siteAdminActionRow}>
            <button type="button" className={styles.primaryButton} onClick={() => void applyTheme()} disabled={saving || loading}>
              Apply Theme
            </button>
          </div>
        </div>

        <div className={styles.siteAdminSection}>
          <label className={styles.siteAdminField}>
            <span>Logo path</span>
            <input type="text" value={logoPath} onChange={(event) => setLogoPath(event.target.value)} disabled={saving || loading} />
          </label>
          <label className={styles.siteAdminField}>
            <span>Favicon path</span>
            <input type="text" value={faviconPath} onChange={(event) => setFaviconPath(event.target.value)} disabled={saving || loading} />
          </label>
          <label className={styles.siteAdminField}>
            <span>Social card path</span>
            <input type="text" value={socialCardPath} onChange={(event) => setSocialCardPath(event.target.value)} disabled={saving || loading} />
          </label>
          <div className={styles.siteAdminActionRow}>
            <button type="button" className={styles.primaryButton} onClick={() => void applyBranding()} disabled={saving || loading}>
              Apply Branding
            </button>
          </div>
        </div>

        <div className={styles.siteAdminSection}>
          <div className={styles.siteAdminOverridesHeader}>
            <strong>Domains</strong>
            <span>Top-level docs containers that each get their own sidebar.</span>
          </div>
          <div className={styles.siteAdminOverrideTable}>
            {domains.map((domain) => (
              <div key={domain.path} className={styles.siteAdminOverrideRow}>
                <span>
                  <strong>{domain.label}</strong>
                  <br />
                  <small>{domain.path} · {domain.sidebarId}</small>
                </span>
              </div>
            ))}
          </div>
          <label className={styles.siteAdminField}>
            <span>New domain folder</span>
            <input
              type="text"
              value={domainName}
              onChange={(event) => {
                const nextName = event.target.value;
                setDomainName(nextName);
                if (!domainTitle.trim()) {
                  setDomainTitle(nextName);
                }
              }}
              placeholder="ProjectDocs"
              disabled={saving || loading}
            />
          </label>
          <label className={styles.siteAdminField}>
            <span>Domain title</span>
            <input type="text" value={domainTitle} onChange={(event) => setDomainTitle(event.target.value)} placeholder="Project Docs" disabled={saving || loading} />
          </label>
          <label className={styles.siteAdminField}>
            <span>Domain description</span>
            <input type="text" value={domainDescription} onChange={(event) => setDomainDescription(event.target.value)} placeholder="Optional summary for the domain landing page" disabled={saving || loading} />
          </label>
          {nextSidebarId ? <p className={styles.statusText}>New domain sidebar id: {nextSidebarId}</p> : null}
          <div className={styles.siteAdminActionRow}>
            <button type="button" className={styles.primaryButton} onClick={() => void createDomain()} disabled={saving || loading || !domainName.trim()}>
              Create Domain
            </button>
          </div>
        </div>

        <div className={styles.siteAdminSection}>
          <div className={styles.siteAdminOverridesHeader}>
            <strong>Managed overrides</strong>
            <span>Blank uses suite defaults.</span>
          </div>
          <div className={styles.siteAdminOverrideTable}>
            {overrideRows.map((row) => (
              <label key={row.path} className={styles.siteAdminOverrideRow}>
                <span>{row.path}</span>
                <select
                  value={row.mode}
                  onChange={(event) =>
                    setOverrideMap((current) => ({
                      ...current,
                      [row.path]: event.target.value as '' | 'suite' | 'project',
                    }))
                  }
                  disabled={saving || loading}
                >
                  <option value="">Auto</option>
                  <option value="suite">Suite</option>
                  <option value="project">Project</option>
                </select>
              </label>
            ))}
          </div>
          <div className={styles.siteAdminActionRow}>
            <button type="button" className={styles.primaryButton} onClick={() => void applyOverrides()} disabled={saving || loading}>
              Save Overrides
            </button>
          </div>
        </div>
      </div>
    </div>
  );
}
