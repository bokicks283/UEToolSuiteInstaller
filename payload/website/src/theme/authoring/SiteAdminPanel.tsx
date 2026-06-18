import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';

import styles from '../DocItem/Layout/ueAuthoring.module.css';
import {
  broadcastDocsStructureChanged,
  getSidebarIdFromDomainPath,
  type DocsDomain,
  type DocsDomainsPayload,
  type DocsTreeNode,
  type DocsTreePayload,
} from './api';

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

type SiteMutationResponse = {ok: true; result?: {path?: string; sidebarId?: string}};
type TreeResponse = {ok: true; tree: DocsTreePayload};
type DomainsResponse = {ok: true; domains: DocsDomainsPayload};

type Props = {
  requestJson: RequestJsonFn;
};

type StructureSelection =
  | {kind: 'domain'; domainPath: string}
  | {kind: 'node'; domainPath: string; nodePath: string}
  | null;

type SectionCreateConfig = {
  sectionName: string;
  title: string;
  linkType: 'doc' | 'generated-index' | 'none';
  generatedIndexTitle?: string;
  generatedIndexSlug?: string;
  generatedIndexDescription?: string;
};

type StructureMutation =
  | {kind: 'createDomain'; domainName: string; title: string; description: string; createLandingPage: boolean}
  | {kind: 'updateDomain'; domainPath: string; label: string; showLandingInSidebar: boolean}
  | {kind: 'moveDomain'; domainPath: string; direction: 'up' | 'down'}
  | {kind: 'deleteDomain'; domainPath: string}
  | {kind: 'createPage'; domainPath: string; sectionPath: string; pageName: string; title: string}
  | {kind: 'createSection'; domainPath: string; parentPath: string; config: SectionCreateConfig}
  | {kind: 'updateNodeMeta'; path: string; title?: string; label?: string}
  | {kind: 'visibility'; path: string; hidden: boolean}
  | {kind: 'reorderNode'; targetPath: string; position: number}
  | {kind: 'moveNode'; sourcePath: string; destinationDomainPath: string; destinationParentPath: string; insertIndex: number}
  | {kind: 'deleteNode'; path: string};

type PendingMutation = {
  id: string;
  summary: string;
  key?: string;
  op: StructureMutation;
};

type ParentOption = {
  path: string;
  label: string;
};

type CreateDomainDialogState = {
  kind: 'createDomain';
  domainName: string;
  title: string;
  description: string;
  createLandingPage: boolean;
};

type CreatePageDialogState = {
  kind: 'createPage';
  domainPath: string;
  parentPath: string;
  pageName: string;
  title: string;
};

type CreateSectionDialogState = {
  kind: 'createSection';
  domainPath: string;
  parentPath: string;
  config: SectionCreateConfig;
};

type ConfirmDeleteDialogState = {
  kind: 'confirmDelete';
  domainPath: string;
  targetType: 'domain' | 'page' | 'section';
  label: string;
  path?: string;
};

type DialogState =
  | CreateDomainDialogState
  | CreatePageDialogState
  | CreateSectionDialogState
  | ConfirmDeleteDialogState
  | null;

type NodeContext = {
  node: DocsTreeNode;
  parentPath: string;
  siblingIndex: number;
  siblingCount: number;
  depth: number;
};

const SITE_ADMIN_SELECTION_STORAGE_KEY = 'ue-docs:site-admin-selection';

function normalizeFilter(value: string): string {
  return value.trim().toLowerCase();
}

function normalizePathToken(value: string): string {
  return value.replaceAll('\\', '/').replace(/^\/+|\/+$/g, '').trim();
}

function getParentPath(pathToken: string): string {
  const normalized = normalizePathToken(pathToken);
  const lastSlashIndex = normalized.lastIndexOf('/');
  return lastSlashIndex >= 0 ? normalized.slice(0, lastSlashIndex) : '';
}

function getLeafName(pathToken: string): string {
  const normalized = normalizePathToken(pathToken);
  const lastSlashIndex = normalized.lastIndexOf('/');
  return lastSlashIndex >= 0 ? normalized.slice(lastSlashIndex + 1) : normalized;
}

function buildChildPath(parentPath: string, leafName: string): string {
  const normalizedParent = normalizePathToken(parentPath);
  const normalizedLeaf = normalizePathToken(leafName);
  return normalizedParent ? `${normalizedParent}/${normalizedLeaf}` : normalizedLeaf;
}

function ensureMarkdownFileName(value: string): string {
  const trimmed = value.trim();
  return /\.(md|mdx)$/i.test(trimmed) ? trimmed : `${trimmed}.md`;
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

function cloneNode(node: DocsTreeNode): DocsTreeNode {
  return {
    ...node,
    children: node.children ? node.children.map(cloneNode) : undefined,
  };
}

function cloneTreePayload(tree: DocsTreePayload): DocsTreePayload {
  return {
    ...tree,
    children: (tree.children ?? []).map(cloneNode),
  };
}

function cloneDomains(domains: DocsDomain[]): DocsDomain[] {
  return domains.map((domain) => ({
    ...domain,
    ownedRoots: domain.ownedRoots ? [...domain.ownedRoots] : [],
    ownedDocs: domain.ownedDocs ? [...domain.ownedDocs] : [],
  }));
}

function seedExpandedState(trees: Record<string, DocsTreePayload>, current: Record<string, boolean>): Record<string, boolean> {
  const next = {...current};
  const visit = (nodes: DocsTreeNode[]) => {
    for (const node of nodes) {
      if (node.type === 'section' && !(node.path in next)) {
        next[node.path] = true;
      }
      if (node.children?.length) {
        visit(node.children);
      }
    }
  };

  Object.values(trees).forEach((tree) => visit(tree.children ?? []));
  return next;
}

function reorderInArray<T>(items: T[], fromIndex: number, toIndex: number): T[] {
  const next = [...items];
  const [moved] = next.splice(fromIndex, 1);
  next.splice(Math.max(0, Math.min(toIndex, next.length)), 0, moved);
  return next;
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

    return cloneNode(node);
  });
}

function rewriteNodePaths(node: DocsTreeNode, sourcePath: string, destinationPath: string): DocsTreeNode {
  const rewritePath = (value: string): string => {
    if (value === sourcePath) {
      return destinationPath;
    }
    if (value.startsWith(`${sourcePath}/`)) {
      return `${destinationPath}${value.slice(sourcePath.length)}`;
    }
    return value;
  };

  return {
    ...node,
    path: rewritePath(node.path),
    children: node.children ? node.children.map((child) => rewriteNodePaths(child, sourcePath, destinationPath)) : undefined,
  };
}

function updateNodeList(nodes: DocsTreeNode[], targetPath: string, updater: (node: DocsTreeNode) => DocsTreeNode): DocsTreeNode[] {
  return nodes.map((node) => {
    if (node.path === targetPath) {
      return updater(cloneNode(node));
    }

    if (node.children?.length) {
      return {...node, children: updateNodeList(node.children, targetPath, updater)};
    }

    return cloneNode(node);
  });
}

function findNodeContext(nodes: DocsTreeNode[], targetPath: string, depth: number = 0, parentPath = ''): NodeContext | null {
  for (const [index, node] of nodes.entries()) {
    const nextParentPath = depth === 0 ? getParentPath(node.path) : parentPath;
    if (node.path === targetPath) {
      return {
        node,
        parentPath: nextParentPath,
        siblingIndex: index,
        siblingCount: nodes.length,
        depth,
      };
    }

    if (node.children?.length) {
      const nested = findNodeContext(node.children, targetPath, depth + 1, node.path);
      if (nested) {
        return nested;
      }
    }
  }

  return null;
}

function hasNodePath(nodes: DocsTreeNode[], targetPath: string): boolean {
  return findNodeContext(nodes, targetPath) !== null;
}

function hasDomainPath(domains: DocsDomain[], targetPath: string): boolean {
  const normalizedTarget = normalizePathToken(targetPath).toLowerCase();
  return domains.some((domain) => normalizePathToken(domain.path).toLowerCase() === normalizedTarget);
}

function collectSectionOptions(nodes: DocsTreeNode[], options: ParentOption[] = []): ParentOption[] {
  for (const node of nodes) {
    if (node.type === 'section') {
      options.push({path: node.path, label: node.name});
      if (node.children?.length) {
        collectSectionOptions(node.children, options);
      }
    }
  }
  return options;
}

function buildParentOptionsForDomain(
  domains: DocsDomain[],
  trees: Record<string, DocsTreePayload>,
  targetDomainPath: string,
  options?: {
    includeSharedRoot?: boolean;
    excludeSectionPath?: string;
  },
): ParentOption[] {
  const targetDomain = domains.find((domain) => domain.path === targetDomainPath);
  const targetTree = trees[targetDomainPath];
  if (!targetDomain || !targetTree) {
    return [];
  }

  const nextOptions: ParentOption[] = [];
  if (options?.includeSharedRoot) {
    nextOptions.push({path: '', label: 'Docs root (shared)'});
  }

  nextOptions.push({path: targetDomain.path, label: `${targetDomain.label} folder`});

  const sectionOptions = collectSectionOptions(targetTree.children ?? [])
    .filter((option) => {
      if (!options?.excludeSectionPath) {
        return true;
      }

      return option.path !== options.excludeSectionPath && !option.path.startsWith(`${options.excludeSectionPath}/`);
    })
    .map((option) => ({
      ...option,
      label: `${targetDomain.label} / ${option.label}`,
    }));

  nextOptions.push(...sectionOptions);
  return nextOptions;
}

function nextSelectionAfterDelete(
  tree: DocsTreePayload | undefined,
  deletedPath: string,
  domainPath: string,
): StructureSelection {
  if (!tree) {
    return {kind: 'domain', domainPath};
  }

  const context = findNodeContext(tree.children ?? [], deletedPath);
  if (!context) {
    return {kind: 'domain', domainPath};
  }

  const remainingNodes = removeTreeNode(tree.children ?? [], deletedPath).nodes;
  const flattenedTopLevel = remainingNodes;
  const siblingCandidateIndex = Math.min(context.siblingIndex, Math.max(0, context.siblingCount - 2));
  if (!context.parentPath) {
    const siblingCandidate = flattenedTopLevel[siblingCandidateIndex];
    return siblingCandidate ? {kind: 'node', domainPath, nodePath: siblingCandidate.path} : {kind: 'domain', domainPath};
  }

  const parentContext = findNodeContext(remainingNodes, context.parentPath);
  if (!parentContext?.node.children?.length) {
    return {kind: 'domain', domainPath};
  }

  const siblingCandidate = parentContext.node.children[Math.min(context.siblingIndex, parentContext.node.children.length - 1)];
  return siblingCandidate ? {kind: 'node', domainPath, nodePath: siblingCandidate.path} : {kind: 'node', domainPath, nodePath: parentContext.node.path};
}

function enqueueMutation(current: PendingMutation[], next: PendingMutation): PendingMutation[] {
  if (!next.key) {
    return [...current, next];
  }

  const existingIndex = current.findIndex((entry) => entry.key === next.key);
  if (existingIndex < 0) {
    return [...current, next];
  }

  const replacement = [...current];
  replacement[existingIndex] = next;
  return replacement;
}

function formatHiddenState(hidden: boolean): string {
  return hidden ? 'Hide From Site' : 'Show In Site';
}

function readStoredSelection(): StructureSelection {
  if (typeof window === 'undefined') {
    return null;
  }

  try {
    const rawValue = window.localStorage.getItem(SITE_ADMIN_SELECTION_STORAGE_KEY);
    if (!rawValue) {
      return null;
    }

    const parsed = JSON.parse(rawValue) as StructureSelection;
    if (!parsed || typeof parsed !== 'object' || !('kind' in parsed)) {
      return null;
    }

    return parsed;
  } catch {
    return null;
  }
}

function readLocationSelection(): StructureSelection {
  if (typeof window === 'undefined') {
    return null;
  }

  try {
    const params = new URLSearchParams(window.location.search);
    const domainPath = params.get('domain')?.trim() ?? '';
    const nodePath = params.get('node')?.trim() ?? '';
    if (!domainPath) {
      return null;
    }

    return nodePath ? {kind: 'node', domainPath, nodePath} : {kind: 'domain', domainPath};
  } catch {
    return null;
  }
}

function DialogFrame({
  title,
  body,
  actions,
}: {
  title: string;
  body: React.ReactNode;
  actions: React.ReactNode;
}): React.JSX.Element {
  return (
    <div className={styles.dialogBackdrop}>
      <div className={styles.dialogCard}>
        <h3 className={styles.dialogTitle}>{title}</h3>
        <div className={styles.dialogBody}>{body}</div>
        <div className={styles.dialogActions}>{actions}</div>
      </div>
    </div>
  );
}

export default function SiteAdminPanel({requestJson}: Props): React.JSX.Element {
  const mutationCounterRef = useRef(0);

  const [loading, setLoading] = useState(false);
  const [structureLoading, setStructureLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [selectionPersistenceReady, setSelectionPersistenceReady] = useState(false);
  const [errorText, setErrorText] = useState('');
  const [successText, setSuccessText] = useState('');

  const [themeOptions, setThemeOptions] = useState<Array<{id: string; label: string; description?: string}>>([]);
  const [knownPaths, setKnownPaths] = useState<string[]>([]);
  const [themeId, setThemeId] = useState('neutral');
  const [logoPath, setLogoPath] = useState('');
  const [faviconPath, setFaviconPath] = useState('');
  const [socialCardPath, setSocialCardPath] = useState('');
  const [overrideMap, setOverrideMap] = useState<Record<string, '' | 'suite' | 'project'>>({});

  const [baselineDomains, setBaselineDomains] = useState<DocsDomain[]>([]);
  const [baselineTrees, setBaselineTrees] = useState<Record<string, DocsTreePayload>>({});
  const [draftDomains, setDraftDomains] = useState<DocsDomain[]>([]);
  const [draftTrees, setDraftTrees] = useState<Record<string, DocsTreePayload>>({});
  const [pendingMutations, setPendingMutations] = useState<PendingMutation[]>([]);
  const [selection, setSelection] = useState<StructureSelection>(null);
  const [structureFilters, setStructureFilters] = useState<Record<string, string>>({});
  const [expandedPaths, setExpandedPaths] = useState<Record<string, boolean>>({});
  const [dialogState, setDialogState] = useState<DialogState>(null);

  const [domainLabelDraft, setDomainLabelDraft] = useState('');
  const [domainLandingDraft, setDomainLandingDraft] = useState(false);
  const [nodeNameDraft, setNodeNameDraft] = useState('');
  const [nodeHiddenDraft, setNodeHiddenDraft] = useState(false);
  const [moveTargetDomainPath, setMoveTargetDomainPath] = useState('');
  const [moveTargetParentPath, setMoveTargetParentPath] = useState('');

  const nextMutationId = useCallback(() => {
    mutationCounterRef.current += 1;
    return `pending-${mutationCounterRef.current}`;
  }, []);

  const load = useCallback(async () => {
    setLoading(true);
    setStructureLoading(true);
    setSelectionPersistenceReady(false);
    setErrorText('');
    try {
      const [catalogPayload, configPayload, domainsPayload] = await Promise.all([
        requestJson<ThemeCatalogResponse>('/api/site/theme-catalog'),
        requestJson<SiteConfigResponse>('/api/site/config'),
        requestJson<DomainsResponse>('/api/domains'),
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
      const treeEntries = await Promise.all(
        loadedDomains.map(async (domain) => {
          const treePayload = await requestJson<TreeResponse>(`/api/tree?sidebarId=${encodeURIComponent(domain.sidebarId)}`);
          return [domain.path, treePayload.tree] as const;
        }),
      );

      const loadedTrees = Object.fromEntries(treeEntries);
      const clonedDomains = cloneDomains(loadedDomains);
      const clonedTrees = Object.fromEntries(
        Object.entries(loadedTrees).map(([domainPath, tree]) => [domainPath, cloneTreePayload(tree)]),
      ) as Record<string, DocsTreePayload>;

      setBaselineDomains(clonedDomains);
      setBaselineTrees(clonedTrees);
      setDraftDomains(cloneDomains(clonedDomains));
      setDraftTrees(
        Object.fromEntries(Object.entries(clonedTrees).map(([domainPath, tree]) => [domainPath, cloneTreePayload(tree)])) as Record<
          string,
          DocsTreePayload
        >,
      );
      setExpandedPaths((current) => seedExpandedState(clonedTrees, current));
      setPendingMutations([]);

      if (clonedDomains.length > 0) {
        const locationSelection = readLocationSelection();
        const storedSelection = readStoredSelection();
        setSelection((current) => {
          const preferredSelection = current ?? locationSelection ?? storedSelection;
          if (!preferredSelection) {
            return {kind: 'domain', domainPath: clonedDomains[0].path};
          }

          if (preferredSelection.kind === 'domain') {
            return clonedDomains.some((domain) => domain.path === preferredSelection.domainPath)
              ? preferredSelection
              : {kind: 'domain', domainPath: clonedDomains[0].path};
          }

          const matchingTree = clonedTrees[preferredSelection.domainPath];
          if (!matchingTree) {
            return {kind: 'domain', domainPath: clonedDomains[0].path};
          }

          const context = findNodeContext(matchingTree.children ?? [], preferredSelection.nodePath);
          return context ? preferredSelection : {kind: 'domain', domainPath: preferredSelection.domainPath};
        });
      } else {
        setSelection(null);
      }

      setSuccessText('');
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to load site settings.');
    } finally {
      setSelectionPersistenceReady(true);
      setLoading(false);
      setStructureLoading(false);
    }
  }, [requestJson]);

  useEffect(() => {
    void load();
  }, [load]);

  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }

    if (!selectionPersistenceReady) {
      return;
    }

    try {
      const nextUrl = new URL(window.location.href);
      if (!selection) {
        window.localStorage.removeItem(SITE_ADMIN_SELECTION_STORAGE_KEY);
        nextUrl.searchParams.delete('domain');
        nextUrl.searchParams.delete('node');
        window.history.replaceState(null, '', nextUrl);
        return;
      }

      nextUrl.searchParams.set('domain', selection.domainPath);
      if (selection.kind === 'node') {
        nextUrl.searchParams.set('node', selection.nodePath);
      } else {
        nextUrl.searchParams.delete('node');
      }

      window.localStorage.setItem(SITE_ADMIN_SELECTION_STORAGE_KEY, JSON.stringify(selection));
      window.history.replaceState(null, '', nextUrl);
    } catch {
      // Ignore storage failures.
    }
  }, [selection, selectionPersistenceReady]);

  const overrideRows = useMemo(() => {
    return knownPaths.map((path) => ({
      path,
      mode: overrideMap[path] ?? '',
    }));
  }, [knownPaths, overrideMap]);

  const activeDomainPath = useMemo(() => {
    if (selection?.kind === 'node' || selection?.kind === 'domain') {
      return selection.domainPath;
    }
    return draftDomains[0]?.path ?? '';
  }, [draftDomains, selection]);

  const activeDomain = useMemo(
    () => draftDomains.find((domain) => domain.path === activeDomainPath) ?? null,
    [draftDomains, activeDomainPath],
  );

  const activeTree = useMemo(
    () => (activeDomain ? draftTrees[activeDomain.path] : undefined),
    [draftTrees, activeDomain],
  );

  const selectedNode = useMemo(() => {
    if (!activeTree || selection?.kind !== 'node') {
      return null;
    }

    return findNodeContext(activeTree.children ?? [], selection.nodePath)?.node ?? null;
  }, [activeTree, selection]);

  const selectedNodeContext = useMemo(() => {
    if (!activeTree || selection?.kind !== 'node') {
      return null;
    }

    return findNodeContext(activeTree.children ?? [], selection.nodePath);
  }, [activeTree, selection]);

  useEffect(() => {
    if (!activeDomain) {
      return;
    }

    if (selection?.kind === 'node' && selectedNode) {
      setNodeNameDraft(selectedNode.name);
      setNodeHiddenDraft(selectedNode.unlisted === true);
      setMoveTargetDomainPath(activeDomain.path);
      setMoveTargetParentPath(selectedNodeContext?.parentPath ?? activeDomain.path);
      return;
    }

    setDomainLabelDraft(activeDomain.label);
    setDomainLandingDraft(activeDomain.showLandingInSidebar === true);
    setMoveTargetDomainPath(activeDomain.path);
    setMoveTargetParentPath(activeDomain.path);
  }, [activeDomain, selectedNode, selectedNodeContext, selection]);

  const queueMutation = useCallback(
    (summary: string, op: StructureMutation, key?: string) => {
      setPendingMutations((current) =>
        enqueueMutation(current, {
          id: nextMutationId(),
          summary,
          key,
          op,
        }),
      );
    },
    [nextMutationId],
  );

  const applyTheme = useCallback(async (): Promise<void> => {
    setSaving(true);
    setErrorText('');
    setSuccessText('');
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
      setSuccessText('Theme updated.');
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to update the theme.');
    } finally {
      setSaving(false);
    }
  }, [faviconPath, logoPath, requestJson, socialCardPath, themeId]);

  const applyBranding = useCallback(async (): Promise<void> => {
    setSaving(true);
    setErrorText('');
    setSuccessText('');
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
      setSuccessText('Branding updated.');
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to update branding.');
    } finally {
      setSaving(false);
    }
  }, [faviconPath, logoPath, requestJson, socialCardPath]);

  const applyOverrides = useCallback(async (): Promise<void> => {
    setSaving(true);
    setErrorText('');
    setSuccessText('');
    try {
      const entries = Object.entries(overrideMap)
        .filter(([, mode]) => mode === 'suite' || mode === 'project')
        .map(([path, mode]) => ({path, mode}));
      await requestJson<SiteMutationResponse>('/api/site/overrides', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({entries}),
      });
      setSuccessText('Override policy updated.');
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to update override policy.');
    } finally {
      setSaving(false);
    }
  }, [overrideMap, requestJson]);

  const discardStructureChanges = useCallback(() => {
    setDraftDomains(cloneDomains(baselineDomains));
    setDraftTrees(
      Object.fromEntries(Object.entries(baselineTrees).map(([domainPath, tree]) => [domainPath, cloneTreePayload(tree)])) as Record<
        string,
        DocsTreePayload
      >,
    );
    setPendingMutations([]);
    setSuccessText('Discarded unsaved structure changes.');
    setErrorText('');
  }, [baselineDomains, baselineTrees]);

  const updateDraftDomain = useCallback((domainPath: string, updater: (domain: DocsDomain) => DocsDomain) => {
    setDraftDomains((current) => current.map((domain) => (domain.path === domainPath ? updater({...domain}) : {...domain})));
  }, []);

  const updateDraftTreeNode = useCallback((domainPath: string, nodePath: string, updater: (node: DocsTreeNode) => DocsTreeNode) => {
    setDraftTrees((current) => {
      const targetTree = current[domainPath];
      if (!targetTree) {
        return current;
      }

      return {
        ...current,
        [domainPath]: {
          ...targetTree,
          children: updateNodeList(targetTree.children ?? [], nodePath, updater),
        },
      };
    });
  }, []);

  const moveDraftNode = useCallback(
    (sourceDomainPath: string, destinationDomainPath: string, sourcePath: string, destinationParentPath: string, insertIndex: number) => {
      setDraftTrees((current) => {
        const sourceTree = current[sourceDomainPath];
        const destinationTree = current[destinationDomainPath];
        if (!sourceTree || !destinationTree) {
          return current;
        }

        const removal = removeTreeNode(sourceTree.children ?? [], sourcePath);
        if (!removal.removed) {
          return current;
        }

        const currentParentPath = getParentPath(sourcePath);
        const leafName = getLeafName(sourcePath);
        const nextPath = currentParentPath === destinationParentPath ? sourcePath : buildChildPath(destinationParentPath, leafName);
        const rewrittenNode = currentParentPath === destinationParentPath ? removal.removed : rewriteNodePaths(removal.removed, sourcePath, nextPath);
        const nextSourceTree =
          sourceDomainPath === destinationDomainPath
            ? {
                ...sourceTree,
                children: insertTreeNode(removal.nodes, destinationParentPath, insertIndex, rewrittenNode, destinationTree.domainPath ?? destinationDomainPath),
              }
            : {
                ...sourceTree,
                children: removal.nodes,
              };

        const nextDestinationTree =
          sourceDomainPath === destinationDomainPath
            ? nextSourceTree
            : {
                ...destinationTree,
                children: insertTreeNode(
                  destinationTree.children ?? [],
                  destinationParentPath,
                  insertIndex,
                  rewrittenNode,
                  destinationTree.domainPath ?? destinationDomainPath,
                ),
              };

        return {
          ...current,
          [sourceDomainPath]: nextSourceTree,
          [destinationDomainPath]: nextDestinationTree,
        };
      });

      const currentLeafName = getLeafName(sourcePath);
      const nextSelectionPath = buildChildPath(destinationParentPath, currentLeafName);
      setSelection({kind: 'node', domainPath: destinationDomainPath, nodePath: nextSelectionPath});
      setMoveTargetDomainPath(destinationDomainPath);
      setMoveTargetParentPath(destinationParentPath);
    },
    [],
  );

  const createDraftPage = useCallback(
    (domainPath: string, parentPath: string, pageName: string, title: string) => {
      const nextPath = buildChildPath(parentPath, ensureMarkdownFileName(pageName));
      const targetTree = draftTrees[domainPath];
      if (!targetTree) {
        setErrorText('Unable to find the selected domain tree.');
        setSuccessText('');
        return;
      }

      if (hasNodePath(targetTree.children ?? [], nextPath)) {
        setErrorText(`A page already exists at ${nextPath}.`);
        setSuccessText('');
        return;
      }

      const nextNode: DocsTreeNode = {
        type: 'page',
        path: nextPath,
        name: title || pageName,
        position: Number.POSITIVE_INFINITY,
        unlisted: false,
      };

      setDraftTrees((current) => {
        const targetTree = current[domainPath];
        if (!targetTree) {
          return current;
        }

        return {
          ...current,
          [domainPath]: {
            ...targetTree,
            children: insertTreeNode(targetTree.children ?? [], parentPath, Number.MAX_SAFE_INTEGER, nextNode, targetTree.domainPath ?? domainPath),
          },
        };
      });

      setSelection({kind: 'node', domainPath, nodePath: nextPath});
      queueMutation(`Create page "${title || pageName}"`, {
        kind: 'createPage',
        domainPath,
        sectionPath: parentPath,
        pageName,
        title,
      });
    },
    [draftTrees, queueMutation],
  );

  const createDraftSection = useCallback(
    (domainPath: string, parentPath: string, config: SectionCreateConfig) => {
      const nextPath = buildChildPath(parentPath, config.sectionName);
      const targetTree = draftTrees[domainPath];
      if (!targetTree) {
        setErrorText('Unable to find the selected domain tree.');
        setSuccessText('');
        return;
      }

      if (hasNodePath(targetTree.children ?? [], nextPath)) {
        setErrorText(`A section already exists at ${nextPath}.`);
        setSuccessText('');
        return;
      }

      const nextNode: DocsTreeNode = {
        type: 'section',
        path: nextPath,
        name: config.title || config.sectionName,
        position: Number.POSITIVE_INFINITY,
        children: [],
      };

      setDraftTrees((current) => {
        const targetTree = current[domainPath];
        if (!targetTree) {
          return current;
        }

        return {
          ...current,
          [domainPath]: {
            ...targetTree,
            children: insertTreeNode(targetTree.children ?? [], parentPath, Number.MAX_SAFE_INTEGER, nextNode, targetTree.domainPath ?? domainPath),
          },
        };
      });
      setExpandedPaths((current) => ({
        ...current,
        [parentPath]: true,
        [nextPath]: true,
      }));
      setSelection({kind: 'node', domainPath, nodePath: nextPath});
      queueMutation(`Create section "${config.title || config.sectionName}"`, {
        kind: 'createSection',
        domainPath,
        parentPath,
        config,
      });
    },
    [draftTrees, queueMutation],
  );

  const createDraftDomain = useCallback(
    (state: CreateDomainDialogState) => {
      const predictedPath = state.domainName.trim();
      const predictedLabel = state.title.trim() || predictedPath;
      if (!predictedPath) {
        setErrorText('A domain folder name is required.');
        setSuccessText('');
        return;
      }

      if (hasDomainPath(draftDomains, predictedPath)) {
        setErrorText(`A domain already exists at ${predictedPath}.`);
        setSuccessText('');
        return;
      }

      const sidebarId = getSidebarIdFromDomainPath(predictedPath);
      const nextDomain: DocsDomain = {
        key: predictedPath,
        path: predictedPath,
        label: predictedLabel,
        sidebarId,
        readmePath: state.createLandingPage ? `${predictedPath}/README.md` : undefined,
        description: state.description.trim() || undefined,
        showLandingInSidebar: false,
        ownedRoots: [predictedPath],
        ownedDocs: [],
        catchAll: false,
      };

      setDraftDomains((current) => [...current, nextDomain]);
      setDraftTrees((current) => ({
        ...current,
        [predictedPath]: {
          root: predictedLabel,
          domainPath: predictedPath,
          sidebarId,
          children: [],
        },
      }));
      setSelection({kind: 'domain', domainPath: predictedPath});
      queueMutation(`Create domain "${predictedLabel}"`, {
        kind: 'createDomain',
        domainName: predictedPath,
        title: predictedLabel,
        description: state.description.trim(),
        createLandingPage: state.createLandingPage,
      });
    },
    [draftDomains, queueMutation],
  );

  const applyDomainDraft = useCallback(() => {
    if (!activeDomain) {
      return;
    }

    const trimmedLabel = domainLabelDraft.trim();
    if (!trimmedLabel) {
      return;
    }

    updateDraftDomain(activeDomain.path, (domain) => ({
      ...domain,
      label: trimmedLabel,
      showLandingInSidebar: domainLandingDraft,
    }));

    queueMutation(
      `Update domain "${trimmedLabel}"`,
      {
        kind: 'updateDomain',
        domainPath: activeDomain.path,
        label: trimmedLabel,
        showLandingInSidebar: domainLandingDraft,
      },
      `domain-update:${activeDomain.path}`,
    );
    setSuccessText(`Queued changes for ${trimmedLabel}.`);
    setErrorText('');
  }, [activeDomain, domainLabelDraft, domainLandingDraft, queueMutation, updateDraftDomain]);

  const applyNodeDraft = useCallback(() => {
    if (!activeDomain || !selectedNode) {
      return;
    }

    const trimmedName = nodeNameDraft.trim();
    if (!trimmedName) {
      return;
    }

    updateDraftTreeNode(activeDomain.path, selectedNode.path, (node) => ({
      ...node,
      name: trimmedName,
      unlisted: node.type === 'page' ? nodeHiddenDraft : node.unlisted,
    }));

    queueMutation(
      `Update ${selectedNode.type} "${trimmedName}"`,
      {
        kind: 'updateNodeMeta',
        path: selectedNode.path,
        ...(selectedNode.type === 'page' ? {title: trimmedName} : {label: trimmedName}),
      },
      `node-meta:${selectedNode.path}`,
    );

    if (selectedNode.type === 'page') {
      queueMutation(
        `${nodeHiddenDraft ? 'Hide' : 'Show'} "${trimmedName}" in site`,
        {
          kind: 'visibility',
          path: selectedNode.path,
          hidden: nodeHiddenDraft,
        },
        `node-visibility:${selectedNode.path}`,
      );
    }

    setSuccessText(`Queued changes for ${trimmedName}.`);
    setErrorText('');
  }, [activeDomain, nodeHiddenDraft, nodeNameDraft, queueMutation, selectedNode, updateDraftTreeNode]);

  const moveSelectedNodeWithinParent = useCallback(
    (direction: 'up' | 'down') => {
      if (!activeDomain || !selectedNodeContext) {
        return;
      }

      const nextIndex = direction === 'up' ? selectedNodeContext.siblingIndex - 1 : selectedNodeContext.siblingIndex + 1;
      if (nextIndex < 0 || nextIndex >= selectedNodeContext.siblingCount) {
        return;
      }

      const siblingList =
        selectedNodeContext.parentPath && selectedNodeContext.parentPath !== activeDomain.path
          ? (findNodeContext(activeTree?.children ?? [], selectedNodeContext.parentPath)?.node.children ?? [])
          : (activeTree?.children ?? []);
      const adjacentNode = siblingList[nextIndex];
      if (!adjacentNode) {
        return;
      }

      moveDraftNode(activeDomain.path, activeDomain.path, selectedNodeContext.node.path, selectedNodeContext.parentPath, nextIndex);
      queueMutation(
        `Move ${selectedNodeContext.node.name} ${direction}`,
        {
          kind: 'reorderNode',
          targetPath: selectedNodeContext.node.path,
          position: adjacentNode.position,
        },
      );
    },
    [activeDomain, activeTree, moveDraftNode, queueMutation, selectedNodeContext],
  );

  const moveSelectedNodeToTarget = useCallback(() => {
    if (!activeDomain || !selectedNode || !moveTargetDomainPath) {
      return;
    }

    const destinationTree = draftTrees[moveTargetDomainPath];
    if (!destinationTree) {
      setErrorText('Unable to find the selected destination domain.');
      setSuccessText('');
      return;
    }

    const nextPath = buildChildPath(moveTargetParentPath, getLeafName(selectedNode.path));
    if (nextPath !== selectedNode.path && hasNodePath(destinationTree.children ?? [], nextPath)) {
      setErrorText(`An item already exists at ${nextPath}.`);
      setSuccessText('');
      return;
    }

    const insertIndex =
      moveTargetParentPath && moveTargetParentPath !== destinationTree.domainPath
        ? (findNodeContext(destinationTree.children ?? [], moveTargetParentPath)?.node.children ?? []).length
        : (destinationTree.children ?? []).length;

    moveDraftNode(activeDomain.path, moveTargetDomainPath, selectedNode.path, moveTargetParentPath, insertIndex);
    queueMutation(
      `Move ${selectedNode.name} to ${moveTargetParentPath || 'docs root'}`,
      {
        kind: 'moveNode',
        sourcePath: selectedNode.path,
        destinationDomainPath: moveTargetDomainPath,
        destinationParentPath: moveTargetParentPath,
        insertIndex,
        },
      );
    setErrorText('');
    setSuccessText(`Queued move for ${selectedNode.name}.`);
  }, [activeDomain, draftTrees, moveDraftNode, moveTargetDomainPath, moveTargetParentPath, queueMutation, selectedNode]);

  const moveDomainLocally = useCallback(
    (domainPath: string, direction: 'up' | 'down') => {
      const currentIndex = draftDomains.findIndex((domain) => domain.path === domainPath);
      if (currentIndex < 0) {
        return;
      }

      const targetIndex = direction === 'up' ? currentIndex - 1 : currentIndex + 1;
      if (targetIndex < 0 || targetIndex >= draftDomains.length) {
        return;
      }

      setDraftDomains((current) => reorderInArray(current, currentIndex, targetIndex));
      queueMutation(`Move domain ${direction}`, {kind: 'moveDomain', domainPath, direction});
    },
    [draftDomains, queueMutation],
  );

  const confirmDelete = useCallback(() => {
    if (!dialogState || dialogState.kind !== 'confirmDelete') {
      return;
    }

    if (dialogState.targetType === 'domain') {
      const nextDomains = draftDomains.filter((domain) => domain.path !== dialogState.domainPath);
      const nextTrees = {...draftTrees};
      delete nextTrees[dialogState.domainPath];
      setDraftDomains(nextDomains);
      setDraftTrees(nextTrees);
      setSelection(nextDomains[0] ? {kind: 'domain', domainPath: nextDomains[0].path} : null);
      queueMutation(`Delete domain "${dialogState.label}"`, {kind: 'deleteDomain', domainPath: dialogState.domainPath});
      setDialogState(null);
      return;
    }

    if (!dialogState.path) {
      return;
    }

    const targetTree = draftTrees[dialogState.domainPath];
    const nextSelection = nextSelectionAfterDelete(targetTree, dialogState.path, dialogState.domainPath);
    setDraftTrees((current) => {
      const tree = current[dialogState.domainPath];
      if (!tree) {
        return current;
      }
      return {
        ...current,
        [dialogState.domainPath]: {
          ...tree,
          children: removeTreeNode(tree.children ?? [], dialogState.path!).nodes,
        },
      };
    });
    setSelection(nextSelection);
    queueMutation(`Delete ${dialogState.targetType} "${dialogState.label}"`, {kind: 'deleteNode', path: dialogState.path});
    setDialogState(null);
  }, [dialogState, draftDomains, draftTrees, queueMutation]);

  const activeMoveParentOptions = useMemo(() => {
    if (!moveTargetDomainPath) {
      return [] as ParentOption[];
    }

    return buildParentOptionsForDomain(draftDomains, draftTrees, moveTargetDomainPath, {
      includeSharedRoot: activeDomainPath === moveTargetDomainPath,
      excludeSectionPath: selection?.kind === 'node' && selectedNode?.type === 'section' ? selectedNode.path : undefined,
    });
  }, [activeDomainPath, draftDomains, draftTrees, moveTargetDomainPath, selectedNode, selection]);

  const createDialogParentOptions = useMemo(() => {
    if (dialogState?.kind !== 'createPage' && dialogState?.kind !== 'createSection') {
      return [] as ParentOption[];
    }

    return buildParentOptionsForDomain(draftDomains, draftTrees, dialogState.domainPath, {
      includeSharedRoot: true,
    });
  }, [dialogState, draftDomains, draftTrees]);

  useEffect(() => {
    if (activeMoveParentOptions.length === 0) {
      return;
    }

    if (activeMoveParentOptions.some((option) => option.path === moveTargetParentPath)) {
      return;
    }

    setMoveTargetParentPath(activeMoveParentOptions[0].path);
  }, [activeMoveParentOptions, moveTargetParentPath]);

  const structureDirty = pendingMutations.length > 0;

  const saveStructureChanges = useCallback(async (): Promise<void> => {
    if (!structureDirty) {
      return;
    }

    setSaving(true);
    setErrorText('');
    setSuccessText('');
    try {
      for (const mutation of pendingMutations) {
        switch (mutation.op.kind) {
          case 'createDomain':
            await requestJson<SiteMutationResponse>('/api/create/domain', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                domainName: mutation.op.domainName,
                title: mutation.op.title,
                description: mutation.op.description,
                createLandingPage: mutation.op.createLandingPage,
              }),
            });
            break;
          case 'updateDomain':
            await requestJson<SiteMutationResponse>('/api/domains/update', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                domainPath: mutation.op.domainPath,
                label: mutation.op.label,
                showLandingInSidebar: mutation.op.showLandingInSidebar,
              }),
            });
            break;
          case 'moveDomain':
            await requestJson<SiteMutationResponse>('/api/domains/reorder', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                domainPath: mutation.op.domainPath,
                direction: mutation.op.direction,
              }),
            });
            break;
          case 'deleteDomain':
            await requestJson<SiteMutationResponse>('/api/domains/delete', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                domainPath: mutation.op.domainPath,
              }),
            });
            break;
          case 'createPage':
            await requestJson<SiteMutationResponse>('/api/create/page', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                domainPath: mutation.op.domainPath,
                sectionPath: mutation.op.sectionPath,
                pageName: mutation.op.pageName,
                title: mutation.op.title,
              }),
            });
            break;
          case 'createSection':
            await requestJson<SiteMutationResponse>('/api/create/section', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                domainPath: mutation.op.domainPath,
                parentPath: mutation.op.parentPath,
                sectionName: mutation.op.config.sectionName,
                title: mutation.op.config.title,
                linkType: mutation.op.config.linkType,
                generatedIndexTitle: mutation.op.config.generatedIndexTitle ?? '',
                generatedIndexSlug: mutation.op.config.generatedIndexSlug ?? '',
                generatedIndexDescription: mutation.op.config.generatedIndexDescription ?? '',
              }),
            });
            break;
          case 'updateNodeMeta':
            await requestJson<SiteMutationResponse>('/api/node/metadata', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                path: mutation.op.path,
                title: mutation.op.title ?? '',
                label: mutation.op.label ?? '',
              }),
            });
            break;
          case 'visibility':
            await requestJson<SiteMutationResponse>('/api/visibility', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                path: mutation.op.path,
                hidden: mutation.op.hidden,
              }),
            });
            break;
          case 'reorderNode':
            await requestJson<SiteMutationResponse>('/api/reorder', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                targetPath: mutation.op.targetPath,
                position: mutation.op.position,
              }),
            });
            break;
          case 'moveNode':
            await requestJson<SiteMutationResponse>('/api/move', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                sourcePath: mutation.op.sourcePath,
                destinationDomainPath: mutation.op.destinationDomainPath,
                destinationParentPath: mutation.op.destinationParentPath,
                insertIndex: mutation.op.insertIndex,
              }),
            });
            break;
          case 'deleteNode':
            await requestJson<SiteMutationResponse>('/api/delete', {
              method: 'POST',
              headers: {'Content-Type': 'application/json'},
              body: JSON.stringify({
                path: mutation.op.path,
              }),
            });
            break;
          default:
            break;
        }
      }

      broadcastDocsStructureChanged();
      await load();
      setSuccessText(`Applied ${pendingMutations.length} structure change${pendingMutations.length === 1 ? '' : 's'}.`);
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to apply structure changes.');
    } finally {
      setSaving(false);
    }
  }, [load, pendingMutations, requestJson, structureDirty]);

  const renderTreeNode = useCallback(
    (domainPath: string, node: DocsTreeNode, depth: number): React.JSX.Element | null => {
      const filter = normalizeFilter(structureFilters[domainPath] ?? '');
      if (!treeNodeMatchesFilter(node, filter)) {
        return null;
      }

      const hasChildren = Boolean(node.children?.length);
      const expanded = filter ? true : (expandedPaths[node.path] ?? depth === 0);
      const selected = selection?.kind === 'node' && selection.domainPath === domainPath && selection.nodePath === node.path;

      return (
        <li key={node.path} className={styles.siteAdminTreeItem}>
          <div
            className={`${styles.siteAdminTreeRow} ${selected ? styles.siteAdminTreeRowSelected : ''}`}
            role="button"
            tabIndex={0}
            onClick={() => setSelection({kind: 'node', domainPath, nodePath: node.path})}
            onKeyDown={(event) => {
              if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                setSelection({kind: 'node', domainPath, nodePath: node.path});
              }
            }}
          >
            <div className={styles.siteAdminTreeLabel} style={{paddingLeft: `${depth * 0.95}rem`}}>
              {hasChildren ? (
                <button
                  type="button"
                  className={styles.siteAdminTreeToggle}
                  onClick={(event) => {
                    event.stopPropagation();
                    setExpandedPaths((current) => ({
                      ...current,
                      [node.path]: !expanded,
                    }));
                  }}
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
          </div>
          {hasChildren && expanded ? (
            <ul className={styles.siteAdminTreeList}>
              {node.children!.map((child) => renderTreeNode(domainPath, child, depth + 1))}
            </ul>
          ) : null}
        </li>
      );
    },
    [expandedPaths, selection, structureFilters],
  );

  const structureToolbarTargetPath =
    selection?.kind === 'node' && selectedNode?.type === 'section' ? selectedNode.path : activeDomain?.path ?? '';

  return (
    <div className={styles.siteAdminPage}>
      <div className={styles.siteAdminHeader}>
        <div>
          <h2>Site Settings</h2>
          <p>Use one domain at a time, stage structural edits locally, then apply them in one pass.</p>
        </div>
        <div className={styles.siteAdminInlineActions}>
          <button
            type="button"
            className={styles.secondaryButton}
            onClick={() => setDialogState({kind: 'createDomain', domainName: '', title: '', description: '', createLandingPage: true})}
            disabled={saving || loading}
          >
            New Domain
          </button>
          <button type="button" className={styles.secondaryButton} onClick={discardStructureChanges} disabled={saving || !structureDirty}>
            Discard Draft
          </button>
          <button type="button" className={styles.primaryButton} onClick={() => void saveStructureChanges()} disabled={saving || !structureDirty}>
            Save Structure
          </button>
        </div>
      </div>

      {loading ? <p className={styles.statusText}>Loading site settings...</p> : null}
      {errorText ? <p className={styles.errorText}>{errorText}</p> : null}
      {successText ? <p className={styles.statusText}>{successText}</p> : null}

      <div className={styles.siteAdminSection}>
        <div className={styles.siteAdminOverridesHeader}>
          <strong>Structure</strong>
          <span>Keep changes in the draft until you are ready to apply them.</span>
        </div>

        <div className={styles.siteAdminTabs}>
          {draftDomains.map((domain) => {
            const active = domain.path === activeDomainPath;
            return (
              <button
                key={domain.path}
                type="button"
                className={`${styles.siteAdminTabButton} ${active ? styles.siteAdminTabButtonActive : ''}`}
                onClick={() => setSelection({kind: 'domain', domainPath: domain.path})}
              >
                {domain.label}
              </button>
            );
          })}
        </div>

        {activeDomain ? (
          <>
            <div className={styles.siteAdminToolbar}>
              <button
                type="button"
                className={styles.secondaryButton}
                onClick={() =>
                  setDialogState({
                    kind: 'createPage',
                    domainPath: activeDomain.path,
                    parentPath: structureToolbarTargetPath,
                    pageName: '',
                    title: '',
                  })
                }
                disabled={saving}
              >
                New Page
              </button>
              <button
                type="button"
                className={styles.secondaryButton}
                onClick={() =>
                  setDialogState({
                    kind: 'createSection',
                    domainPath: activeDomain.path,
                    parentPath: structureToolbarTargetPath,
                    config: {
                      sectionName: '',
                      title: '',
                      linkType: 'doc',
                      generatedIndexTitle: '',
                      generatedIndexSlug: '',
                      generatedIndexDescription: '',
                    },
                  })
                }
                disabled={saving}
              >
                New Section
              </button>
              {selectedNodeContext ? (
                <>
                  <button
                    type="button"
                    className={styles.secondaryButton}
                    onClick={() => moveSelectedNodeWithinParent('up')}
                    disabled={saving || selectedNodeContext.siblingIndex === 0}
                  >
                    Move Up
                  </button>
                  <button
                    type="button"
                    className={styles.secondaryButton}
                    onClick={() => moveSelectedNodeWithinParent('down')}
                    disabled={saving || selectedNodeContext.siblingIndex >= selectedNodeContext.siblingCount - 1}
                  >
                    Move Down
                  </button>
                </>
              ) : null}
            </div>

            <div className={styles.siteAdminWorkspace}>
              <div className={styles.siteAdminSidebarPane}>
                <label className={styles.siteAdminField}>
                  <span>Filter {activeDomain.label}</span>
                  <input
                    type="text"
                    value={structureFilters[activeDomain.path] ?? ''}
                    onChange={(event) =>
                      setStructureFilters((current) => ({
                        ...current,
                        [activeDomain.path]: event.target.value,
                      }))
                    }
                    placeholder="Search pages or sections"
                    disabled={saving || loading}
                  />
                </label>

                <div className={styles.siteAdminTreeShell}>
                  <ul className={styles.siteAdminTreeList}>
                    {(activeTree?.children ?? []).map((node) => renderTreeNode(activeDomain.path, node, 0))}
                  </ul>
                  {structureLoading ? <p className={styles.statusText}>Loading structure...</p> : null}
                  {!structureLoading && (activeTree?.children ?? []).length === 0 ? <p className={styles.statusText}>No items yet.</p> : null}
                </div>
              </div>

              <div className={styles.siteAdminInspectorPane}>
                {selection?.kind === 'node' && selectedNode ? (
                  <>
                    <div className={styles.siteAdminCardTitle}>
                      <strong>{selectedNode.type === 'section' ? 'Section' : 'Page'} Inspector</strong>
                      <span>{selectedNode.path}</span>
                    </div>
                    <label className={styles.siteAdminField}>
                      <span>{selectedNode.type === 'section' ? 'Section label' : 'Page title'}</span>
                      <input type="text" value={nodeNameDraft} onChange={(event) => setNodeNameDraft(event.target.value)} disabled={saving} />
                    </label>
                    {selectedNode.type === 'page' ? (
                      <label className={styles.siteAdminCheckboxRow}>
                        <input type="checkbox" checked={nodeHiddenDraft} onChange={(event) => setNodeHiddenDraft(event.target.checked)} disabled={saving} />
                        <span>{formatHiddenState(nodeHiddenDraft)}</span>
                      </label>
                    ) : null}
                    <div className={styles.siteAdminActionRow}>
                      <button type="button" className={styles.primaryButton} onClick={applyNodeDraft} disabled={saving || !nodeNameDraft.trim()}>
                        Stage Changes
                      </button>
                    </div>

                    <div className={styles.siteAdminInspectorBlock}>
                      <div className={styles.siteAdminCardTitle}>
                        <strong>Move</strong>
                        <span>Move this item to another domain folder or section.</span>
                      </div>
                      <label className={styles.siteAdminField}>
                        <span>Target domain</span>
                        <select value={moveTargetDomainPath} onChange={(event) => setMoveTargetDomainPath(event.target.value)} disabled={saving}>
                          {draftDomains.map((domain) => (
                            <option key={domain.path} value={domain.path}>
                              {domain.label}
                            </option>
                          ))}
                        </select>
                      </label>
                      <label className={styles.siteAdminField}>
                        <span>Target parent</span>
                        <select value={moveTargetParentPath} onChange={(event) => setMoveTargetParentPath(event.target.value)} disabled={saving}>
                          {activeMoveParentOptions.map((option) => (
                            <option key={`${option.path || 'root'}:${option.label}`} value={option.path}>
                              {option.label}
                            </option>
                          ))}
                        </select>
                      </label>
                      <div className={styles.siteAdminActionRow}>
                        <button type="button" className={styles.secondaryButton} onClick={moveSelectedNodeToTarget} disabled={saving}>
                          Move To Target
                        </button>
                      </div>
                    </div>

                    <div className={styles.siteAdminActionRow}>
                      <button
                        type="button"
                        className={styles.secondaryButton}
                        onClick={() =>
                          setDialogState({
                            kind: 'confirmDelete',
                            domainPath: activeDomain.path,
                            targetType: selectedNode.type,
                            label: selectedNode.name,
                            path: selectedNode.path,
                          })
                        }
                        disabled={saving}
                      >
                        Delete
                      </button>
                    </div>
                  </>
                ) : activeDomain ? (
                  <>
                    <div className={styles.siteAdminCardTitle}>
                      <strong>Domain Inspector</strong>
                      <span>{activeDomain.path}</span>
                    </div>
                    <label className={styles.siteAdminField}>
                      <span>Domain label</span>
                      <input type="text" value={domainLabelDraft} onChange={(event) => setDomainLabelDraft(event.target.value)} disabled={saving} />
                    </label>
                    <label className={styles.siteAdminCheckboxRow}>
                      <input type="checkbox" checked={domainLandingDraft} onChange={(event) => setDomainLandingDraft(event.target.checked)} disabled={saving} />
                      <span>Show landing page in sidebar</span>
                    </label>
                    <div className={styles.siteAdminActionRow}>
                      <button type="button" className={styles.primaryButton} onClick={applyDomainDraft} disabled={saving || !domainLabelDraft.trim()}>
                        Stage Changes
                      </button>
                    </div>
                    <div className={styles.siteAdminInlineActions}>
                      <button
                        type="button"
                        className={styles.secondaryButton}
                        onClick={() => moveDomainLocally(activeDomain.path, 'up')}
                        disabled={saving || draftDomains[0]?.path === activeDomain.path}
                      >
                        Move Up
                      </button>
                      <button
                        type="button"
                        className={styles.secondaryButton}
                        onClick={() => moveDomainLocally(activeDomain.path, 'down')}
                        disabled={saving || draftDomains[draftDomains.length - 1]?.path === activeDomain.path}
                      >
                        Move Down
                      </button>
                      <button
                        type="button"
                        className={styles.secondaryButton}
                        onClick={() =>
                          setDialogState({
                            kind: 'confirmDelete',
                            domainPath: activeDomain.path,
                            targetType: 'domain',
                            label: activeDomain.label,
                          })
                        }
                        disabled={saving || draftDomains.length <= 1}
                      >
                        Delete Domain
                      </button>
                    </div>
                  </>
                ) : null}
              </div>
            </div>

            <div className={styles.siteAdminPendingList}>
              <div className={styles.siteAdminCardTitle}>
                <strong>Pending Changes</strong>
                <span>{pendingMutations.length} queued</span>
              </div>
              {pendingMutations.length === 0 ? <p className={styles.statusText}>No unsaved structure changes.</p> : null}
              {pendingMutations.map((mutation) => (
                <div key={mutation.id} className={styles.siteAdminPendingItem}>
                  <span>{mutation.summary}</span>
                </div>
              ))}
            </div>
          </>
        ) : null}
      </div>

      <div className={styles.siteAdminSection}>
        <div className={styles.siteAdminOverridesHeader}>
          <strong>Theme</strong>
          <span>Apply site-wide theme settings immediately.</span>
        </div>
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
        <div className={styles.siteAdminOverridesHeader}>
          <strong>Branding</strong>
          <span>Update shared brand assets without reinstalling the site.</span>
        </div>
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
          <strong>Managed Overrides</strong>
          <span>Choose whether the suite or the project owns each overridable file.</span>
        </div>
        <div className={styles.siteAdminOverrideTable}>
          {overrideRows.map((row) => (
            <div key={row.path} className={styles.siteAdminOverrideRow}>
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
                <option value="">Default</option>
                <option value="suite">Suite</option>
                <option value="project">Project</option>
              </select>
            </div>
          ))}
        </div>
        <div className={styles.siteAdminActionRow}>
          <button type="button" className={styles.primaryButton} onClick={() => void applyOverrides()} disabled={saving || loading}>
            Apply Override Policy
          </button>
        </div>
      </div>

      {dialogState?.kind === 'createDomain' ? (
        <DialogFrame
          title="Create Domain"
          body={
            <div className={styles.siteAdminDialogGrid}>
              <label className={styles.siteAdminField}>
                <span>Domain folder</span>
                <input
                  type="text"
                  value={dialogState.domainName}
                  onChange={(event) =>
                    setDialogState((current) =>
                      current?.kind === 'createDomain'
                        ? {
                            ...current,
                            domainName: event.target.value,
                            title: current.title || event.target.value,
                          }
                        : current,
                    )
                  }
                />
              </label>
              <label className={styles.siteAdminField}>
                <span>Domain title</span>
                <input
                  type="text"
                  value={dialogState.title}
                  onChange={(event) =>
                    setDialogState((current) => (current?.kind === 'createDomain' ? {...current, title: event.target.value} : current))
                  }
                />
              </label>
              <label className={styles.siteAdminField}>
                <span>Description</span>
                <input
                  type="text"
                  value={dialogState.description}
                  onChange={(event) =>
                    setDialogState((current) => (current?.kind === 'createDomain' ? {...current, description: event.target.value} : current))
                  }
                />
              </label>
              <label className={styles.siteAdminCheckboxRow}>
                <input
                  type="checkbox"
                  checked={dialogState.createLandingPage}
                  onChange={(event) =>
                    setDialogState((current) =>
                      current?.kind === 'createDomain' ? {...current, createLandingPage: event.target.checked} : current,
                    )
                  }
                />
                <span>Create a landing page</span>
              </label>
            </div>
          }
          actions={
            <>
              <button type="button" className={styles.secondaryButton} onClick={() => setDialogState(null)}>
                Cancel
              </button>
              <button
                type="button"
                className={styles.primaryButton}
                disabled={!dialogState.domainName.trim()}
                onClick={() => {
                  if (dialogState.kind !== 'createDomain' || !dialogState.domainName.trim()) {
                    return;
                  }
                  createDraftDomain(dialogState);
                  setDialogState(null);
                }}
              >
                Add To Draft
              </button>
            </>
          }
        />
      ) : null}

      {dialogState?.kind === 'createPage' ? (
        <DialogFrame
          title="Create Page"
          body={
            <div className={styles.siteAdminDialogGrid}>
              <label className={styles.siteAdminField}>
                <span>Target parent</span>
                <select
                  value={dialogState.parentPath}
                  onChange={(event) =>
                    setDialogState((current) => (current?.kind === 'createPage' ? {...current, parentPath: event.target.value} : current))
                  }
                >
                  {createDialogParentOptions.map((option) => (
                    <option key={`${option.path || 'root'}:${option.label}`} value={option.path}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className={styles.siteAdminField}>
                <span>Page file</span>
                <input
                  type="text"
                  value={dialogState.pageName}
                  onChange={(event) =>
                    setDialogState((current) =>
                      current?.kind === 'createPage'
                        ? {
                            ...current,
                            pageName: event.target.value,
                            title: current.title || event.target.value.replace(/\.(md|mdx)$/i, ''),
                          }
                        : current,
                    )
                  }
                />
              </label>
              <label className={styles.siteAdminField}>
                <span>Page title</span>
                <input
                  type="text"
                  value={dialogState.title}
                  onChange={(event) =>
                    setDialogState((current) => (current?.kind === 'createPage' ? {...current, title: event.target.value} : current))
                  }
                />
              </label>
            </div>
          }
          actions={
            <>
              <button type="button" className={styles.secondaryButton} onClick={() => setDialogState(null)}>
                Cancel
              </button>
              <button
                type="button"
                className={styles.primaryButton}
                disabled={!dialogState.pageName.trim()}
                onClick={() => {
                  if (dialogState.kind !== 'createPage' || !dialogState.pageName.trim()) {
                    return;
                  }
                  createDraftPage(dialogState.domainPath, dialogState.parentPath, dialogState.pageName.trim(), dialogState.title.trim() || dialogState.pageName.trim());
                  setDialogState(null);
                }}
              >
                Add To Draft
              </button>
            </>
          }
        />
      ) : null}

      {dialogState?.kind === 'createSection' ? (
        <DialogFrame
          title="Create Section"
          body={
            <div className={styles.siteAdminDialogGrid}>
              <label className={styles.siteAdminField}>
                <span>Target parent</span>
                <select
                  value={dialogState.parentPath}
                  onChange={(event) =>
                    setDialogState((current) => (current?.kind === 'createSection' ? {...current, parentPath: event.target.value} : current))
                  }
                >
                  {createDialogParentOptions.map((option) => (
                    <option key={`${option.path || 'root'}:${option.label}`} value={option.path}>
                      {option.label}
                    </option>
                  ))}
                </select>
              </label>
              <label className={styles.siteAdminField}>
                <span>Section folder</span>
                <input
                  type="text"
                  value={dialogState.config.sectionName}
                  onChange={(event) =>
                    setDialogState((current) =>
                      current?.kind === 'createSection'
                        ? {
                            ...current,
                            config: {
                              ...current.config,
                              sectionName: event.target.value,
                              title: current.config.title || event.target.value,
                            },
                          }
                        : current,
                    )
                  }
                />
              </label>
              <label className={styles.siteAdminField}>
                <span>Section title</span>
                <input
                  type="text"
                  value={dialogState.config.title}
                  onChange={(event) =>
                    setDialogState((current) =>
                      current?.kind === 'createSection'
                        ? {
                            ...current,
                            config: {
                              ...current.config,
                              title: event.target.value,
                            },
                          }
                        : current,
                    )
                  }
                />
              </label>
              <label className={styles.siteAdminField}>
                <span>Landing type</span>
                <select
                  value={dialogState.config.linkType}
                  onChange={(event) =>
                    setDialogState((current) =>
                      current?.kind === 'createSection'
                        ? {
                            ...current,
                            config: {
                              ...current.config,
                              linkType: event.target.value as SectionCreateConfig['linkType'],
                            },
                          }
                        : current,
                    )
                  }
                >
                  <option value="doc">Linked doc</option>
                  <option value="generated-index">Generated index</option>
                  <option value="none">Container only</option>
                </select>
              </label>
              {dialogState.config.linkType === 'generated-index' ? (
                <>
                  <label className={styles.siteAdminField}>
                    <span>Generated index title</span>
                    <input
                      type="text"
                      value={dialogState.config.generatedIndexTitle ?? ''}
                      onChange={(event) =>
                        setDialogState((current) =>
                          current?.kind === 'createSection'
                            ? {
                                ...current,
                                config: {
                                  ...current.config,
                                  generatedIndexTitle: event.target.value,
                                },
                              }
                            : current,
                        )
                      }
                    />
                  </label>
                  <label className={styles.siteAdminField}>
                    <span>Generated index slug</span>
                    <input
                      type="text"
                      value={dialogState.config.generatedIndexSlug ?? ''}
                      onChange={(event) =>
                        setDialogState((current) =>
                          current?.kind === 'createSection'
                            ? {
                                ...current,
                                config: {
                                  ...current.config,
                                  generatedIndexSlug: event.target.value,
                                },
                              }
                            : current,
                        )
                      }
                    />
                  </label>
                  <label className={styles.siteAdminField}>
                    <span>Generated index description</span>
                    <input
                      type="text"
                      value={dialogState.config.generatedIndexDescription ?? ''}
                      onChange={(event) =>
                        setDialogState((current) =>
                          current?.kind === 'createSection'
                            ? {
                                ...current,
                                config: {
                                  ...current.config,
                                  generatedIndexDescription: event.target.value,
                                },
                              }
                            : current,
                        )
                      }
                    />
                  </label>
                </>
              ) : null}
            </div>
          }
          actions={
            <>
              <button type="button" className={styles.secondaryButton} onClick={() => setDialogState(null)}>
                Cancel
              </button>
              <button
                type="button"
                className={styles.primaryButton}
                disabled={!dialogState.config.sectionName.trim()}
                onClick={() => {
                  if (dialogState.kind !== 'createSection' || !dialogState.config.sectionName.trim()) {
                    return;
                  }
                  createDraftSection(dialogState.domainPath, dialogState.parentPath, {
                    ...dialogState.config,
                    sectionName: dialogState.config.sectionName.trim(),
                    title: dialogState.config.title.trim() || dialogState.config.sectionName.trim(),
                  });
                  setDialogState(null);
                }}
              >
                Add To Draft
              </button>
            </>
          }
        />
      ) : null}

      {dialogState?.kind === 'confirmDelete' ? (
        <DialogFrame
          title={`Delete ${dialogState.targetType}`}
          body={
            dialogState.targetType === 'domain' ? (
              <p>Delete "{dialogState.label}" and every page and section inside it? This removes the content from disk when you save.</p>
            ) : dialogState.targetType === 'section' ? (
              <p>Delete "{dialogState.label}" and every child page or subsection inside it? This removes the content from disk when you save.</p>
            ) : (
              <p>Delete "{dialogState.label}" from disk when you save?</p>
            )
          }
          actions={
            <>
              <button type="button" className={styles.secondaryButton} onClick={() => setDialogState(null)}>
                Cancel
              </button>
              <button type="button" className={styles.primaryButton} onClick={confirmDelete}>
                Delete In Draft
              </button>
            </>
          }
        />
      ) : null}
    </div>
  );
}
