import React, {useCallback, useEffect, useMemo, useState} from 'react';

import styles from '../DocItem/Layout/ueAuthoring.module.css';
import {broadcastDocsStructureChanged, getSidebarIdFromDomainPath, type DocsDomain, type DocsDomainsPayload, type DocsTreeNode, type DocsTreePayload} from './api';

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
type TreeResponse = {ok: true; tree: DocsTreePayload};

type Props = {
  requestJson: RequestJsonFn;
};

type StructureRowContext = {
  depth: number;
  parentPath: string;
  siblingIndex: number;
  siblingCount: number;
};

type SectionCreateConfig = {
  sectionName: string;
  title: string;
  linkType: 'doc' | 'generated-index' | 'none';
  generatedIndexTitle?: string;
  generatedIndexSlug?: string;
  generatedIndexDescription?: string;
};

async function pause(milliseconds: number): Promise<void> {
  await new Promise((resolve) => globalThis.setTimeout(resolve, milliseconds));
}

function normalizeFilter(value: string): string {
  return value.trim().toLowerCase();
}

function treeNodeMatchesFilter(node: DocsTreeNode, filter: string): boolean {
  if (!filter) {
    return true;
  }

  const haystack = `${node.name} ${node.path} ${node.type}`.toLowerCase();
  if (haystack.includes(filter)) {
    return true;
  }

  return (node.children ?? []).some((child) => treeNodeMatchesFilter(child, filter));
}

function seedExpandedState(trees: Record<string, DocsTreePayload>, current: Record<string, boolean>): Record<string, boolean> {
  const next = {...current};
  for (const tree of Object.values(trees)) {
    for (const node of tree.children ?? []) {
      if (node.type === 'section' && !(node.path in next)) {
        next[node.path] = true;
      }
    }
  }
  return next;
}

function reorderInArray<T>(items: T[], fromIndex: number, toIndex: number): T[] {
  const next = [...items];
  const [moved] = next.splice(fromIndex, 1);
  next.splice(Math.max(0, Math.min(toIndex, next.length)), 0, moved);
  return next;
}

function cloneNode(node: DocsTreeNode): DocsTreeNode {
  return {
    ...node,
    children: node.children ? node.children.map(cloneNode) : undefined,
  };
}

function removeTreeNode(nodes: DocsTreeNode[], sourcePath: string): {nodes: DocsTreeNode[]; removed: DocsTreeNode | null} {
  let removed: DocsTreeNode | null = null;
  const nextNodes: DocsTreeNode[] = [];

  for (const node of nodes) {
    if (node.path === sourcePath) {
      removed = cloneNode(node);
      continue;
    }

    if (node.children?.length) {
      const result = removeTreeNode(node.children, sourcePath);
      if (result.removed) {
        removed = result.removed;
        nextNodes.push({...node, children: result.nodes});
        continue;
      }
    }

    nextNodes.push(cloneNode(node));
  }

  return {nodes: nextNodes, removed};
}

function insertTreeNode(
  nodes: DocsTreeNode[],
  destinationParentPath: string,
  insertIndex: number,
  nodeToInsert: DocsTreeNode,
  rootParentPath: string,
): DocsTreeNode[] {
  if (!destinationParentPath || destinationParentPath === rootParentPath) {
    const next = [...nodes];
    next.splice(Math.max(0, Math.min(insertIndex, next.length)), 0, nodeToInsert);
    return next;
  }

  return nodes.map((node) => {
    if (node.path === destinationParentPath) {
      const children = [...(node.children ?? [])];
      children.splice(Math.max(0, Math.min(insertIndex, children.length)), 0, nodeToInsert);
      return {...node, children};
    }

    if (node.children?.length) {
      return {...node, children: insertTreeNode(node.children, destinationParentPath, insertIndex, nodeToInsert, rootParentPath)};
    }

    return node;
  });
}

function moveTreeNodeLocally(tree: DocsTreePayload | undefined, sourcePath: string, destinationParentPath: string, insertIndex: number): DocsTreePayload | null {
  if (!tree) {
    return null;
  }

  const removal = removeTreeNode(tree.children ?? [], sourcePath);
  if (!removal.removed) {
    return null;
  }

  return {
    ...tree,
    children: insertTreeNode(removal.nodes, destinationParentPath, insertIndex, removal.removed, tree.domainPath ?? ''),
  };
}

function formatHiddenState(hidden: boolean): string {
  return hidden ? 'Show In Site' : 'Hide From Site';
}

export default function SiteAdminPanel({requestJson}: Props): React.JSX.Element {
  const [loading, setLoading] = useState(false);
  const [structureLoading, setStructureLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [errorText, setErrorText] = useState('');
  const [successText, setSuccessText] = useState('');
  const [themeOptions, setThemeOptions] = useState<Array<{id: string; label: string; description?: string}>>([]);
  const [knownPaths, setKnownPaths] = useState<string[]>([]);
  const [themeId, setThemeId] = useState('neutral');
  const [logoPath, setLogoPath] = useState('');
  const [faviconPath, setFaviconPath] = useState('');
  const [socialCardPath, setSocialCardPath] = useState('');
  const [overrideMap, setOverrideMap] = useState<Record<string, '' | 'suite' | 'project'>>({});
  const [domains, setDomains] = useState<DocsDomainsPayload['domains']>([]);
  const [domainTrees, setDomainTrees] = useState<Record<string, DocsTreePayload>>({});
  const [domainName, setDomainName] = useState('');
  const [domainTitle, setDomainTitle] = useState('');
  const [domainDescription, setDomainDescription] = useState('');
  const [createDomainLandingPage, setCreateDomainLandingPage] = useState(true);
  const [structureFilters, setStructureFilters] = useState<Record<string, string>>({});
  const [expandedPaths, setExpandedPaths] = useState<Record<string, boolean>>({});
  const nextSidebarId = useMemo(() => {
    const trimmedDomainName = domainName.trim();
    return trimmedDomainName ? getSidebarIdFromDomainPath(trimmedDomainName) : '';
  }, [domainName]);

  const load = useCallback(async () => {
    setLoading(true);
    setErrorText('');
    try {
      const [catalogPayload, configPayload, domainsPayload] = await Promise.all([
        requestJson<ThemeCatalogResponse>('/api/site/theme-catalog'),
        requestJson<SiteConfigResponse>('/api/site/config'),
        requestJson<{ok: true; domains: DocsDomainsPayload}>('/api/domains'),
      ]);

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
      const loadedDomains = domainsPayload.domains.domains ?? [];
      setDomains(loadedDomains);
      setLoading(false);
      setStructureLoading(true);
      const treeEntries = await Promise.all(
        loadedDomains.map(async (domain) => {
          const treePayload = await requestJson<TreeResponse>(`/api/tree?sidebarId=${encodeURIComponent(domain.sidebarId)}`);
          return [domain.path, treePayload.tree] as const;
        }),
      );
      const nextTrees = Object.fromEntries(treeEntries);
      setDomainTrees(nextTrees);
      setExpandedPaths((current) => seedExpandedState(nextTrees, current));
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to load site settings.');
    } finally {
      setLoading(false);
      setStructureLoading(false);
    }
  }, [requestJson]);

  useEffect(() => {
    let cancelled = false;
    void (async () => {
      if (cancelled) {
        return;
      }
      await load();
    })();

    return () => {
      cancelled = true;
    };
  }, [load]);

  const overrideRows = useMemo(() => {
    return knownPaths.map((path) => ({
      path,
      mode: overrideMap[path] ?? '',
    }));
  }, [knownPaths, overrideMap]);

  const reloadWhenReady = useCallback(async () => {
    if (typeof window === 'undefined') {
      return;
    }

    const targetUrl = `${window.location.origin}${window.location.pathname}`;
    const deadline = Date.now() + 20000;
    await pause(800);

    while (Date.now() < deadline) {
      try {
        const response = await fetch(`${targetUrl}?ue-refresh=${Date.now()}`, {cache: 'no-store'});
        if (response.ok) {
          window.location.reload();
          return;
        }
      } catch {
        // Wait for the dev server to settle.
      }
      await pause(700);
    }

    window.location.reload();
  }, []);

  const applyMutation = useCallback(
    async (request: () => Promise<void>, successMessage: string, reloadSite: boolean = true): Promise<void> => {
      setSaving(true);
      setErrorText('');
      setSuccessText('');
      try {
        await request();
        setSuccessText(successMessage);
        if (reloadSite) {
          await reloadWhenReady();
          return;
        }
        await load();
      } catch (error) {
        setErrorText(error instanceof Error ? error.message : successMessage);
      } finally {
        setSaving(false);
      }
    },
    [load, reloadWhenReady],
  );

  async function applyTheme(): Promise<void> {
    await applyMutation(async () => {
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
    }, 'Theme updated. Waiting for the site to rebuild.');
  }

  async function applyBranding(): Promise<void> {
    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/site/branding', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          logoPath,
          faviconPath,
          socialCardPath,
        }),
      });
    }, 'Branding updated. Waiting for the site to rebuild.');
  }

  async function applyOverrides(): Promise<void> {
    await applyMutation(async () => {
      const entries = Object.entries(overrideMap)
        .filter(([, mode]) => mode === 'suite' || mode === 'project')
        .map(([path, mode]) => ({path, mode}));
      await requestJson<SiteMutationResponse>('/api/site/overrides', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({entries}),
      });
    }, 'Override policy updated. Waiting for the site to rebuild.');
  }

  async function createDomain(): Promise<void> {
    const trimmedDomainName = domainName.trim();
    if (!trimmedDomainName) {
      return;
    }

    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/create/domain', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          domainName: trimmedDomainName,
          title: domainTitle.trim(),
          description: domainDescription.trim(),
          createLandingPage: createDomainLandingPage,
        }),
      });
      broadcastDocsStructureChanged({sidebarId: nextSidebarId});
      setDomainName('');
      setDomainTitle('');
      setDomainDescription('');
      setCreateDomainLandingPage(true);
    }, 'Domain created. Waiting for the site to rebuild.', false);
  }

  async function moveDomain(domainPath: string, direction: 'up' | 'down'): Promise<void> {
    const currentIndex = domains.findIndex((domain) => domain.path === domainPath);
    if (currentIndex < 0) {
      return;
    }

    const targetIndex = direction === 'up' ? currentIndex - 1 : currentIndex + 1;
    if (targetIndex < 0 || targetIndex >= domains.length) {
      return;
    }

    setDomains((current) => reorderInArray(current, currentIndex, targetIndex));
    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/domains/reorder', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          domainPath,
          direction,
        }),
      });
      broadcastDocsStructureChanged();
    }, 'Domain order updated.', false);
  }

  async function updateDomain(domain: DocsDomain, changes: {label?: string; newPath?: string; showLandingInSidebar?: boolean}): Promise<void> {
    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/domains/update', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          domainPath: domain.path,
          label: changes.label ?? domain.label,
          newPath: changes.newPath ?? domain.path,
          showLandingInSidebar: changes.showLandingInSidebar ?? (domain.showLandingInSidebar === true),
        }),
      });
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, 'Domain updated.', false);
  }

  async function renameDomain(domain: DocsDomain): Promise<void> {
    if (typeof window === 'undefined') {
      return;
    }

    const nextLabel = window.prompt('Domain display name', domain.label)?.trim();
    if (!nextLabel || nextLabel === domain.label) {
      return;
    }

    await updateDomain(domain, {label: nextLabel});
  }

  async function deleteDomain(domain: DocsDomain): Promise<void> {
    if (typeof window === 'undefined') {
      return;
    }

    const accepted = window.confirm(`Delete the "${domain.label}" domain? This deletes every page and section inside "${domain.path}". This cannot be undone from the browser.`);
    if (!accepted) {
      return;
    }

    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/domains/delete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          domainPath: domain.path,
        }),
      });
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, 'Domain deleted.', false);
  }

  async function refreshDomainTree(domain: DocsDomain): Promise<void> {
    const treePayload = await requestJson<TreeResponse>(`/api/tree?sidebarId=${encodeURIComponent(domain.sidebarId)}`);
    setDomainTrees((current) => ({...current, [domain.path]: treePayload.tree}));
    setExpandedPaths((current) => seedExpandedState({[domain.path]: treePayload.tree}, current));
  }

  function promptForSectionConfig(defaultName: string): SectionCreateConfig | null {
    if (typeof window === 'undefined') {
      return null;
    }

    const sectionName = window.prompt('Section folder/name', defaultName)?.trim();
    if (!sectionName) {
      return null;
    }

    const title = window.prompt('Section title', sectionName)?.trim() || sectionName;
    const linkTypeInput = window.prompt('Section landing type: doc, generated-index, or none', 'doc')?.trim().toLowerCase();
    const linkType = linkTypeInput === 'generated-index' || linkTypeInput === 'none' ? linkTypeInput : 'doc';
    if (linkType === 'generated-index') {
      const generatedIndexTitle = window.prompt('Generated index title', title)?.trim() || title;
      const generatedIndexSlug = window.prompt('Generated index slug (optional)', '')?.trim() || '';
      const generatedIndexDescription = window.prompt('Generated index description (optional)', '')?.trim() || '';
      return {
        sectionName,
        title,
        linkType,
        generatedIndexTitle,
        generatedIndexSlug,
        generatedIndexDescription,
      };
    }

    return {
      sectionName,
      title,
      linkType,
    };
  }

  async function createPageInSection(domain: DocsDomain, sectionPath: string): Promise<void> {
    if (typeof window === 'undefined') {
      return;
    }

    const pageName = window.prompt('Page file/name', '')?.trim();
    if (!pageName) {
      return;
    }

    const title = window.prompt('Page title', pageName)?.trim() || pageName;
    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/create/page', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          sectionPath,
          pageName,
          title,
        }),
      });
      await refreshDomainTree(domain);
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, 'Page created.', false);
  }

  async function createSectionInSection(domain: DocsDomain, parentPath: string): Promise<void> {
    const sectionConfig = promptForSectionConfig('');
    if (!sectionConfig) {
      return;
    }

    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/create/section', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          parentPath,
          sectionName: sectionConfig.sectionName,
          title: sectionConfig.title,
          linkType: sectionConfig.linkType,
          generatedIndexTitle: sectionConfig.generatedIndexTitle ?? '',
          generatedIndexSlug: sectionConfig.generatedIndexSlug ?? '',
          generatedIndexDescription: sectionConfig.generatedIndexDescription ?? '',
        }),
      });
      await refreshDomainTree(domain);
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, 'Section created.', false);
  }

  async function toggleNodeVisibility(domain: DocsDomain, node: DocsTreeNode, hidden: boolean): Promise<void> {
    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/visibility', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          path: node.path,
          hidden,
        }),
      });
      await refreshDomainTree(domain);
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, hidden ? 'Page hidden from site.' : 'Page shown in site.', false);
  }

  async function moveTreeNode(domain: DocsDomain, sourcePath: string, destinationParentPath: string, insertIndex: number): Promise<void> {
    const previousTree = domainTrees[domain.path];
    const optimisticTree = moveTreeNodeLocally(previousTree, sourcePath, destinationParentPath, insertIndex);
    if (optimisticTree) {
      setDomainTrees((current) => ({...current, [domain.path]: optimisticTree}));
    }

    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/move', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          sourcePath,
          destinationParentPath,
          insertIndex,
        }),
      });
      await refreshDomainTree(domain);
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, 'Structure order updated.', false);
  }

  async function renameTreeNode(domain: DocsDomain, node: DocsTreeNode): Promise<void> {
    if (typeof window === 'undefined') {
      return;
    }

    const nextName = window.prompt(`Rename ${node.type}`, node.name)?.trim();
    if (!nextName || nextName === node.name) {
      return;
    }

    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/rename', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          sourcePath: node.path,
          newName: nextName,
        }),
      });
      await refreshDomainTree(domain);
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, `${node.type === 'section' ? 'Section' : 'Page'} renamed.`, false);
  }

  async function deleteTreeNode(domain: DocsDomain, node: DocsTreeNode): Promise<void> {
    if (typeof window === 'undefined') {
      return;
    }

    const accepted = window.confirm(
      node.type === 'section'
        ? `Delete "${node.name}"? This deletes every page and subsection inside "${node.path}". This cannot be undone from the browser.`
        : `Delete "${node.name}"? This cannot be undone from the browser.`,
    );
    if (!accepted) {
      return;
    }

    await applyMutation(async () => {
      await requestJson<SiteMutationResponse>('/api/delete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          path: node.path,
        }),
      });
      await refreshDomainTree(domain);
      broadcastDocsStructureChanged({sidebarId: domain.sidebarId});
    }, `${node.type === 'section' ? 'Section' : 'Page'} deleted.`, false);
  }

  const renderStructureNode = useCallback((domain: DocsDomain, node: DocsTreeNode, context: StructureRowContext): React.JSX.Element | null => {
    const filter = normalizeFilter(structureFilters[domain.path] ?? '');
    if (!treeNodeMatchesFilter(node, filter)) {
      return null;
    }

    const hasChildren = Boolean(node.children?.length);
    const expanded = filter ? true : (expandedPaths[node.path] ?? context.depth === 0);

    return (
      <li key={node.path} className={styles.siteAdminTreeItem}>
        <div className={styles.siteAdminTreeRow}>
          <div className={styles.siteAdminTreeLabel} style={{paddingLeft: `${context.depth * 1.1}rem`}}>
            {hasChildren ? (
              <button
                type="button"
                className={styles.siteAdminTreeToggle}
                onClick={() =>
                  setExpandedPaths((current) => ({
                    ...current,
                    [node.path]: !expanded,
                  }))
                }
                aria-label={expanded ? `Collapse ${node.name}` : `Expand ${node.name}`}
              >
                {expanded ? '▾' : '▸'}
              </button>
            ) : (
              <span className={styles.siteAdminTreeToggleSpacer} />
            )}
            <span>
              <strong>{node.name}</strong>
              {node.unlisted ? <em className={styles.siteAdminMutedPill}>Hidden</em> : null}
              <br />
              <small>{node.type} · {node.path}</small>
            </span>
          </div>
          <div className={styles.siteAdminInlineActions}>
            {node.type === 'section' ? (
              <>
                <button
                  type="button"
                  className={styles.secondaryButton}
                  onClick={() => void createPageInSection(domain, node.path)}
                  disabled={saving || loading}
                >
                  New Page
                </button>
                <button
                  type="button"
                  className={styles.secondaryButton}
                  onClick={() => void createSectionInSection(domain, node.path)}
                  disabled={saving || loading}
                >
                  New Section
                </button>
              </>
            ) : null}
            <button
              type="button"
              className={styles.secondaryButton}
              onClick={() => void renameTreeNode(domain, node)}
              disabled={saving || loading}
            >
              Rename
            </button>
            {node.type === 'page' ? (
              <button
                type="button"
                className={styles.secondaryButton}
                onClick={() => void toggleNodeVisibility(domain, node, node.unlisted !== true)}
                disabled={saving || loading}
              >
                {formatHiddenState(node.unlisted === true)}
              </button>
            ) : null}
            <button
              type="button"
              className={styles.secondaryButton}
              onClick={() => void moveTreeNode(domain, node.path, context.parentPath, context.siblingIndex - 1)}
              disabled={saving || loading || context.siblingIndex === 0}
            >
              Up
            </button>
            <button
              type="button"
              className={styles.secondaryButton}
              onClick={() => void moveTreeNode(domain, node.path, context.parentPath, context.siblingIndex + 2)}
              disabled={saving || loading || context.siblingIndex >= context.siblingCount - 1}
            >
              Down
            </button>
            <button
              type="button"
              className={styles.secondaryButton}
              onClick={() => void deleteTreeNode(domain, node)}
              disabled={saving || loading}
            >
              Delete
            </button>
          </div>
        </div>
        {hasChildren && expanded ? (
          <ul className={styles.siteAdminTreeList}>
            {node.children!.map((child, siblingIndex) =>
              renderStructureNode(domain, child, {
                depth: context.depth + 1,
                parentPath: node.path,
                siblingIndex,
                siblingCount: node.children!.length,
              }),
            )}
          </ul>
        ) : null}
      </li>
    );
  }, [expandedPaths, loading, saving, structureFilters]);

  return (
    <div className={styles.siteAdminPage}>
      <div className={styles.siteAdminHeader}>
        <div>
          <h2>Site Settings</h2>
          <p>Theme, branding, domains, and managed override policy.</p>
        </div>
      </div>

      {loading ? <p className={styles.statusText}>Loading site settings...</p> : null}
      {errorText ? <p className={styles.errorText}>{errorText}</p> : null}
      {successText ? <p className={styles.statusText}>{successText}</p> : null}

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
          {domains.map((domain, index) => (
            <div key={domain.path} className={styles.siteAdminOverrideRow}>
              <span>
                <strong>{domain.label}</strong>
                <br />
                <small>{domain.path} · {domain.sidebarId}</small>
              </span>
              <div className={styles.siteAdminInlineActions}>
                <label className={styles.siteAdminCheckboxRow}>
                  <input
                    type="checkbox"
                    checked={domain.showLandingInSidebar === true}
                    onChange={(event) => void updateDomain(domain, {showLandingInSidebar: event.target.checked})}
                    disabled={saving || loading}
                  />
                  <span>Show landing in sidebar</span>
                </label>
                <button type="button" className={styles.secondaryButton} onClick={() => void renameDomain(domain)} disabled={saving || loading}>
                  Rename
                </button>
                <button type="button" className={styles.secondaryButton} onClick={() => void moveDomain(domain.path, 'up')} disabled={saving || loading || index === 0}>
                  Up
                </button>
                <button type="button" className={styles.secondaryButton} onClick={() => void moveDomain(domain.path, 'down')} disabled={saving || loading || index === domains.length - 1}>
                  Down
                </button>
                <button type="button" className={styles.secondaryButton} onClick={() => void deleteDomain(domain)} disabled={saving || loading || domains.length <= 1}>
                  Delete
                </button>
              </div>
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
        <label className={styles.siteAdminCheckboxRow}>
          <input
            type="checkbox"
            checked={createDomainLandingPage}
            onChange={(event) => setCreateDomainLandingPage(event.target.checked)}
            disabled={saving || loading}
          />
          <span>Create a landing page for this domain</span>
        </label>
        <label className={styles.siteAdminField}>
          <span>Domain title</span>
          <input type="text" value={domainTitle} onChange={(event) => setDomainTitle(event.target.value)} placeholder="Project Docs" disabled={saving || loading} />
        </label>
        <label className={styles.siteAdminField}>
          <span>Domain description</span>
          <input type="text" value={domainDescription} onChange={(event) => setDomainDescription(event.target.value)} placeholder="Optional summary for the domain" disabled={saving || loading} />
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
          <strong>Structure ordering</strong>
          <span>Filter a single domain and move items in-context instead of scanning one long flat list.</span>
        </div>
        {domains.map((domain) => (
          <div key={domain.path} className={styles.siteAdminStructureBlock}>
            <div className={styles.siteAdminStructureHeader}>
              <strong>{domain.label}</strong>
              <span>{domain.path}</span>
            </div>
            <div className={styles.siteAdminActionRow}>
              <button type="button" className={styles.secondaryButton} onClick={() => void createPageInSection(domain, domain.path)} disabled={saving || loading}>
                New Page
              </button>
              <button type="button" className={styles.secondaryButton} onClick={() => void createSectionInSection(domain, domain.path)} disabled={saving || loading}>
                New Section
              </button>
            </div>
            <label className={styles.siteAdminField}>
              <span>Filter this domain</span>
              <input
                type="text"
                value={structureFilters[domain.path] ?? ''}
                onChange={(event) =>
                  setStructureFilters((current) => ({
                    ...current,
                    [domain.path]: event.target.value,
                  }))
                }
                placeholder="Search pages or sections"
                disabled={saving || loading}
              />
            </label>
            <div className={styles.siteAdminTreeShell}>
              <ul className={styles.siteAdminTreeList}>
                {(domainTrees[domain.path]?.children ?? []).map((node, siblingIndex, nodes) =>
                  renderStructureNode(domain, node, {
                    depth: 0,
                    parentPath: domain.path,
                    siblingIndex,
                    siblingCount: nodes.length,
                  }),
                )}
              </ul>
              {structureLoading ? (
                <div className={styles.siteAdminOverrideRow}>
                  <span>Loading structure...</span>
                </div>
              ) : null}
              {!structureLoading && (domainTrees[domain.path]?.children ?? []).length === 0 ? (
                <div className={styles.siteAdminOverrideRow}>
                  <span>No items found for this domain yet.</span>
                </div>
              ) : null}
            </div>
          </div>
        ))}
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
  );
}
