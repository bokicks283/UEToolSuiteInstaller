import {useCallback, useEffect, useMemo, useState} from 'react';

export type DocsNodeType = 'page' | 'section';

export type DocsTreeNode = {
  type: DocsNodeType;
  path: string;
  name: string;
  position: number;
  unlisted?: boolean;
  children?: DocsTreeNode[];
};

export type DocsTreePayload = {
  root: string;
  domainPath?: string;
  sidebarId?: string;
  children: DocsTreeNode[];
};

export type DocsDomain = {
  key?: string;
  path: string;
  label: string;
  sidebarId: string;
  readmePath?: string;
  description?: string;
  showLandingInSidebar?: boolean;
  ownedRoots?: string[];
  ownedDocs?: string[];
  catchAll?: boolean;
};

export type DocsDomainsPayload = {
  domains: DocsDomain[];
  generalDomain?: {
    label: string;
    sidebarId: string;
  } | null;
};

export const DOCS_STRUCTURE_CHANGED_EVENT = 'ue-docs:structure-changed';
const DOCS_STRUCTURE_CHANGED_STORAGE_KEY = 'ue-docs:structure-changed';
const EDITOR_API_CAPABILITY_VERSION = 2;
const EDITOR_API_APPLICATION_ID = 'UEToolSuiteDocsEditorApi';

export type DocsContentPayload = {
  path: string;
  content: string;
  hash: string;
  modifiedUtc: string;
};

export const DEFAULT_EDITOR_API_URL = '/__ue_docs_api__/';
const DIRECT_EDITOR_API_URL = 'http://127.0.0.1:38473/';
const EDITOR_API_HEALTH_PATH = 'health';
const EDITOR_API_PROBE_TIMEOUT_MS = 1500;
const EDITOR_API_PROBE_RETRY_DELAY_MS = 1000;

type EditorRuntimeConfig = {
  apiUrl?: string;
  applicationId?: string;
  apiVersion?: number;
  repoRoot?: string;
  docsRoot?: string;
  processId?: number;
  startedAt?: string;
};

type EditorApiHealthPayload = {
  ok?: boolean;
  applicationId?: string;
  apiVersion?: number;
  processId?: number;
  repoRoot?: string;
  docsRoot?: string;
  startedAt?: string;
  capabilities?: {
    authoringApiVersion?: number;
    siteConfig?: boolean;
    domains?: boolean;
    tree?: boolean;
    visibility?: boolean;
  };
};

function trimTrailingSlash(value: string): string {
  return value.endsWith('/') ? value.slice(0, -1) : value;
}

export function normalizeApiBase(value: string): string {
  const trimmed = value.trim();
  if (!trimmed) {
    return DEFAULT_EDITOR_API_URL;
  }
  return `${trimTrailingSlash(trimmed)}/`;
}

export function broadcastDocsStructureChanged(detail?: {sidebarId?: string}): void {
  if (typeof window === 'undefined') {
    return;
  }

  const payload = {
    sidebarId: detail?.sidebarId || '',
    timestamp: Date.now(),
  };

  window.dispatchEvent(new CustomEvent(DOCS_STRUCTURE_CHANGED_EVENT, {detail: payload}));
  try {
    window.localStorage.setItem(DOCS_STRUCTURE_CHANGED_STORAGE_KEY, JSON.stringify(payload));
  } catch {
    // Ignore storage write failures. The in-page event is the primary path.
  }
}

export function getDocsStructureChangedStorageKey(): string {
  return DOCS_STRUCTURE_CHANGED_STORAGE_KEY;
}

function stripLeadingSlash(value: string): string {
  return value.startsWith('/') ? value.slice(1) : value;
}

function toPosixPath(value: string): string {
  return value.replaceAll('\\', '/');
}

function toSlugSegment(value: string): string {
  const withWordBreaks = value.trim().replace(/([a-z0-9])([A-Z])/g, '$1 $2');
  return withWordBreaks
    .toLowerCase()
    .replace(/['’]/g, '')
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

export function resolveSourceToken(sourcePath: string): string {
  const normalized = toPosixPath((sourcePath || '').trim());
  if (!normalized) {
    return '';
  }

  let candidate = normalized;
  if (candidate.startsWith('@site/')) {
    candidate = candidate.slice('@site/'.length);
  }

  candidate = candidate.replace(/^(?:\.\/)+/, '');
  candidate = candidate.replace(/^(?:\.\.\/)+Docs\//i, '');
  candidate = candidate.replace(/^Docs\//i, '');
  candidate = candidate.replace(/^(?:\.\.\/)+/, '');

  return stripLeadingSlash(candidate);
}

export function getSectionPathFromToken(token: string): string {
  const normalized = toPosixPath((token || '').trim()).replace(/\/+$/, '');
  if (!normalized) {
    return '';
  }

  const withoutExtension = normalized.replace(/\.md$/i, '');
  const parts = withoutExtension.split('/');
  if (parts.length <= 1) {
    return '';
  }

  if (parts[parts.length - 1].toLowerCase() === 'readme') {
    parts.pop();
  } else {
    parts.pop();
  }
  return parts.join('/');
}

export function getDocsRouteFromToken(token: string): string {
  const normalized = toPosixPath((token || '').trim()).replace(/^\/+|\/+$/g, '');
  if (!normalized) {
    return '/docs/';
  }

  let tokenPath = normalized.replace(/\.md$/i, '');
  if (tokenPath.toLowerCase().endsWith('/readme')) {
    tokenPath = tokenPath.slice(0, -('/readme'.length));
  }

  if (!tokenPath) {
    return '/docs/';
  }

  const slugPath = tokenPath
    .split('/')
    .map((segment) => toSlugSegment(segment))
    .filter(Boolean)
    .join('/');

  return slugPath ? `/docs/${slugPath}` : '/docs/';
}

export function getSidebarIdFromDomainPath(domainPath: string): string {
  const normalized = toPosixPath((domainPath || '').trim()).replace(/^\/+|\/+$/g, '');
  if (!normalized) {
    return 'general-sidebar';
  }
  const slug = normalized
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/[^A-Za-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase();
  return `${slug}-sidebar`;
}

function buildApiCandidates(preferredApiBase: string): string[] {
  const candidates = new Set<string>();
  const preferred = normalizeApiBase(preferredApiBase || DEFAULT_EDITOR_API_URL);
  candidates.add(preferred);
  candidates.add(normalizeApiBase(DEFAULT_EDITOR_API_URL));
  candidates.add(normalizeApiBase(DIRECT_EDITOR_API_URL));
  return [...candidates];
}

function normalizeComparablePath(value: string | undefined): string {
  return (value || '').replaceAll('\\', '/').replace(/\/+$/g, '').toLowerCase();
}

function matchesExpectedRuntimeIdentity(payload: EditorApiHealthPayload, expected: EditorRuntimeConfig | null): boolean {
  if (!expected) {
    return true;
  }

  if (expected.applicationId && payload.applicationId !== expected.applicationId) {
    return false;
  }

  if (typeof expected.apiVersion === 'number' && payload.apiVersion !== expected.apiVersion) {
    return false;
  }

  if (expected.repoRoot && normalizeComparablePath(payload.repoRoot) !== normalizeComparablePath(expected.repoRoot)) {
    return false;
  }

  if (expected.docsRoot && normalizeComparablePath(payload.docsRoot) !== normalizeComparablePath(expected.docsRoot)) {
    return false;
  }

  if (typeof expected.processId === 'number' && payload.processId !== expected.processId) {
    return false;
  }

  if (expected.startedAt && payload.startedAt !== expected.startedAt) {
    return false;
  }

  return true;
}

async function probeApiBase(
  apiBase: string,
  expectedRuntime: EditorRuntimeConfig | null,
  timeoutMs = EDITOR_API_PROBE_TIMEOUT_MS,
): Promise<boolean> {
  const controller = new AbortController();
  const timeoutId = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  try {
    const response = await fetch(`${apiBase}${EDITOR_API_HEALTH_PATH}`, {
      cache: 'no-store',
      signal: controller.signal,
    });
    if (!response.ok) {
      return false;
    }
    const payload = (await response.json()) as EditorApiHealthPayload;
    if (payload.ok === false) {
      return false;
    }

    const capabilities = payload.capabilities;
    return (
      payload.applicationId === EDITOR_API_APPLICATION_ID &&
      payload.apiVersion === EDITOR_API_CAPABILITY_VERSION &&
      !!capabilities &&
      capabilities.authoringApiVersion === EDITOR_API_CAPABILITY_VERSION &&
      capabilities.siteConfig === true &&
      capabilities.domains === true &&
      capabilities.tree === true &&
      capabilities.visibility === true &&
      matchesExpectedRuntimeIdentity(payload, expectedRuntime)
    );
  } catch {
    return false;
  } finally {
    globalThis.clearTimeout(timeoutId);
  }
}

async function resolveReachableApiBase(
  preferredApiBase: string,
  expectedRuntime: EditorRuntimeConfig | null,
): Promise<{apiBaseUrl: string; runtimeAvailable: boolean}> {
  const candidates = buildApiCandidates(preferredApiBase);
  const probeResults = await Promise.all(
    candidates.map(async (candidate) => ({candidate, ok: await probeApiBase(candidate, expectedRuntime)})),
  );
  for (const result of probeResults) {
    if (result.ok) {
      return {apiBaseUrl: result.candidate, runtimeAvailable: true};
    }
  }
  return {apiBaseUrl: candidates[0], runtimeAvailable: false};
}

export function useDocsAuthoringApi() {
  const [apiBaseUrl, setApiBaseUrl] = useState<string>(DEFAULT_EDITOR_API_URL);
  const [runtimeReady, setRuntimeReady] = useState<boolean>(false);
  const [runtimeAvailable, setRuntimeAvailable] = useState<boolean>(false);

  useEffect(() => {
    let cancelled = false;
    let retryTimeoutId: ReturnType<typeof globalThis.setTimeout> | null = null;

    async function loadRuntimeConfig() {
      let preferredApiBase = DEFAULT_EDITOR_API_URL;
      let expectedRuntime: EditorRuntimeConfig | null = null;
      try {
        const runtimeConfigPaths = ['/ue-tools/editor-runtime.json', '/.ue-tools/editor-runtime.json'];
        for (const runtimeConfigPath of runtimeConfigPaths) {
          const response = await fetch(runtimeConfigPath, {cache: 'no-store'});
          if (!response.ok) {
            continue;
          }

          const payload = (await response.json()) as EditorRuntimeConfig;
          if (payload.apiUrl) {
            preferredApiBase = normalizeApiBase(payload.apiUrl);
          }
          expectedRuntime = payload;
          break;
        }
      } catch {
        // Keep default loopback API URL.
      } finally {
        const resolvedApi = await resolveReachableApiBase(preferredApiBase, expectedRuntime);
        if (!cancelled) {
          setApiBaseUrl(resolvedApi.apiBaseUrl);
          setRuntimeAvailable(resolvedApi.runtimeAvailable);
          setRuntimeReady(true);
          if (!resolvedApi.runtimeAvailable) {
            retryTimeoutId = globalThis.setTimeout(() => {
              if (!cancelled) {
                void loadRuntimeConfig();
              }
            }, EDITOR_API_PROBE_RETRY_DELAY_MS);
          }
        }
      }
    }

    void loadRuntimeConfig();
    return () => {
      cancelled = true;
      if (retryTimeoutId !== null) {
        globalThis.clearTimeout(retryTimeoutId);
      }
    };
  }, []);

  const requestJson = useCallback(
    async <T,>(path: string, init?: RequestInit): Promise<T> => {
      const response = await fetch(`${apiBaseUrl}${path.replace(/^\//, '')}`, init);
      const payload = (await response.json()) as {ok?: boolean; error?: string};
      if (!response.ok || payload.ok === false) {
        const message = payload.error || `Request failed (${response.status})`;
        throw new Error(message);
      }
      return payload as T;
    },
    [apiBaseUrl],
  );

  const docsRuntimeBaseUrl = useMemo(() => {
    return trimTrailingSlash(apiBaseUrl).replace('/api', '');
  }, [apiBaseUrl]);

  return {
    apiBaseUrl,
    docsRuntimeBaseUrl,
    runtimeAvailable,
    runtimeReady,
    requestJson,
  };
}
