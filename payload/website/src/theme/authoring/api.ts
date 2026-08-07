import {useCallback, useEffect, useMemo, useRef, useState} from 'react';

import {
  DEFAULT_EDITOR_API_URL,
  createAuthoringConnectionController,
  formatConnectionLogMessage,
  normalizeApiBase,
  type AuthoringConnectionStatus,
} from './runtimeDiscovery';

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
export type DocsContentPayload = {
  path: string;
  content: string;
  hash: string;
  modifiedUtc: string;
};

function trimTrailingSlash(value: string): string {
  return value.endsWith('/') ? value.slice(0, -1) : value;
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

export function useDocsAuthoringApi() {
  const [apiBaseUrl, setApiBaseUrl] = useState<string>(DEFAULT_EDITOR_API_URL);
  const [connectionStatus, setConnectionStatus] = useState<AuthoringConnectionStatus>({kind: 'checking'});
  const controllerRef = useRef<ReturnType<typeof createAuthoringConnectionController> | null>(null);

  useEffect(() => {
    const controller = createAuthoringConnectionController({
      onStatus: (status) => {
        if (status.kind === 'connected') {
          setApiBaseUrl(status.apiBaseUrl);
        } else if ('apiBaseUrl' in status && status.apiBaseUrl) {
          setApiBaseUrl(normalizeApiBase(status.apiBaseUrl));
        }

        setConnectionStatus(status);
      },
      logFailure: (failure) => {
        if (typeof console !== 'undefined') {
          console.warn(formatConnectionLogMessage(failure));
        }
      },
    });

    controllerRef.current = controller;
    controller.start();
    return () => {
      controller.stop();
      if (controllerRef.current === controller) {
        controllerRef.current = null;
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

  const runtimeReady = connectionStatus.kind !== 'checking';
  const runtimeAvailable = connectionStatus.kind === 'connected';
  const retryConnection = useCallback(() => {
    controllerRef.current?.retry();
  }, []);

  return {
    apiBaseUrl,
    connectionStatus,
    docsRuntimeBaseUrl,
    retryConnection,
    runtimeAvailable,
    runtimeReady,
    requestJson,
  };
}
