export const DEFAULT_EDITOR_API_URL = '/__ue_docs_api__/';
export const DIRECT_EDITOR_API_URL = 'http://127.0.0.1:38473/';
export const EDITOR_API_HEALTH_PATH = 'health';
export const EDITOR_API_CAPABILITY_VERSION = 2;
export const EDITOR_API_APPLICATION_ID = 'UEToolSuiteDocsEditorApi';
export const EDITOR_API_PROBE_TIMEOUT_MS = 1500;

const RUNTIME_CONFIG_PATHS = ['/ue-tools/editor-runtime.json', '/.ue-tools/editor-runtime.json'] as const;
const RETRY_DELAYS_MS = [1000, 2000, 5000, 10000, 30000] as const;
const CONNECTED_HEALTH_POLL_MS = 5000;

export type EditorRuntimeConfig = {
  apiUrl: string;
  applicationId: string;
  apiVersion: number;
  repoRoot: string;
  docsRoot: string;
  processId: number;
  startedAt?: string;
  modulePath?: string;
  scriptPath?: string;
  generatedAt?: string;
};

export type EditorApiHealthPayload = {
  ok: boolean;
  applicationId: string;
  apiVersion: number;
  processId: number;
  repoRoot: string;
  docsRoot: string;
  startedAt?: string;
  modulePath?: string;
  scriptPath?: string;
  capabilities: {
    authoringApiVersion: number;
    siteConfig: boolean;
    domains: boolean;
    tree: boolean;
    visibility: boolean;
  };
};

export type AuthoringConnectionFailureKind =
  | 'runtime-descriptor-not-found'
  | 'runtime-descriptor-http-error'
  | 'runtime-descriptor-invalid-json'
  | 'runtime-descriptor-invalid-schema'
  | 'runtime-descriptor-network-error'
  | 'api-network-error'
  | 'api-timeout'
  | 'api-http-error'
  | 'api-invalid-json'
  | 'api-invalid-schema'
  | 'api-unhealthy'
  | 'application-id-mismatch'
  | 'api-version-mismatch'
  | 'capability-mismatch'
  | 'process-id-mismatch'
  | 'repo-root-mismatch'
  | 'docs-root-mismatch'
  | 'unexpected-error';

export type AuthoringConnectionFailure = {
  kind: AuthoringConnectionFailureKind;
  transient: boolean;
  phase: 'runtime-discovery' | 'health-probe';
  attemptedUrls?: string[];
  runtimeConfigPath?: string;
  runtimeConfig?: EditorRuntimeConfig;
  apiBaseUrl?: string;
  endpoint?: string;
  status?: number;
  field?: string;
  expected?: string | number | boolean;
  actual?: unknown;
  message?: string;
  details?: string[];
};

export type AuthoringConnectionSuccess = {
  kind: 'connected';
  transient: false;
  runtimeConfigPath: string;
  runtimeConfig: EditorRuntimeConfig;
  apiBaseUrl: string;
  endpoint: string;
  attemptedUrls: string[];
  health: EditorApiHealthPayload;
};

export type AuthoringConnectionStatus =
  | {kind: 'checking'}
  | AuthoringConnectionFailure
  | AuthoringConnectionSuccess;

export type AuthoringConnectionPresentation = {
  title: string;
  summary: string;
  nextAction: string;
  technicalDetails: Array<{label: string; value: string}>;
};

export type AuthoringConnectionController = {
  getStatus(): AuthoringConnectionStatus;
  start(): void;
  retry(): void;
  stop(): void;
};

type AuthoringConnectionControllerOptions = {
  fetchImpl?: FetchLike;
  timeoutMs?: number;
  connectedPollMs?: null | number;
  onStatus?: (status: AuthoringConnectionStatus) => void;
  setTimer?: typeof globalThis.setTimeout;
  clearTimer?: typeof globalThis.clearTimeout;
  logFailure?: (failure: AuthoringConnectionFailure) => void;
};

type FetchLike = typeof fetch;

type RuntimeConfigLoadResult =
  | {
      ok: true;
      runtimeConfigPath: string;
      runtimeConfig: EditorRuntimeConfig;
    }
  | AuthoringConnectionFailure;

function isRecord(value: unknown): value is Record<string, unknown> {
  return typeof value === 'object' && value !== null;
}

function isBoolean(value: unknown): value is boolean {
  return typeof value === 'boolean';
}

function isNonEmptyString(value: unknown): value is string {
  return typeof value === 'string' && value.trim().length > 0;
}

function isFiniteNumber(value: unknown): value is number {
  return typeof value === 'number' && Number.isFinite(value);
}

function toErrorMessage(error: unknown): string {
  if (error instanceof Error && error.message) {
    return error.message;
  }
  return String(error);
}

function isAbortError(error: unknown): boolean {
  return error instanceof DOMException
    ? error.name === 'AbortError'
    : isRecord(error) && error.name === 'AbortError';
}

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

export function normalizeComparablePath(value: string | undefined): string {
  return (value || '').replaceAll('\\', '/').replace(/\/+$/g, '').toLowerCase();
}

export function formatDiagnosticValue(value: unknown): string {
  if (typeof value === 'string') {
    return value;
  }
  if (typeof value === 'number' || typeof value === 'boolean') {
    return String(value);
  }
  if (value === null) {
    return 'null';
  }
  if (value === undefined) {
    return 'undefined';
  }
  try {
    return JSON.stringify(value);
  } catch {
    return String(value);
  }
}

function buildApiCandidates(preferredApiBase: string): string[] {
  const candidates = new Set<string>();
  const preferred = normalizeApiBase(preferredApiBase || DEFAULT_EDITOR_API_URL);
  candidates.add(preferred);
  candidates.add(normalizeApiBase(DEFAULT_EDITOR_API_URL));
  candidates.add(normalizeApiBase(DIRECT_EDITOR_API_URL));
  return [...candidates];
}

function isRetryableHttpStatus(status: number): boolean {
  return status === 408 || status === 425 || status === 429 || status >= 500;
}

function validateRuntimeConfigPayload(
  payload: unknown,
): {ok: true; value: EditorRuntimeConfig} | {ok: false; details: string[]} {
  if (!isRecord(payload)) {
    return {ok: false, details: ['Runtime descriptor root value was not an object.']};
  }

  const details: string[] = [];
  if (!isNonEmptyString(payload.apiUrl)) {
    details.push('Missing required string field `apiUrl`.');
  }
  if (!isNonEmptyString(payload.applicationId)) {
    details.push('Missing required string field `applicationId`.');
  }
  if (!isFiniteNumber(payload.apiVersion)) {
    details.push('Missing required numeric field `apiVersion`.');
  }
  if (!isNonEmptyString(payload.repoRoot)) {
    details.push('Missing required string field `repoRoot`.');
  }
  if (!isNonEmptyString(payload.docsRoot)) {
    details.push('Missing required string field `docsRoot`.');
  }
  if (!isFiniteNumber(payload.processId)) {
    details.push('Missing required numeric field `processId`.');
  }
  if (payload.startedAt !== undefined && typeof payload.startedAt !== 'string') {
    details.push('Optional field `startedAt` must be a string when present.');
  }

  if (details.length > 0) {
    return {ok: false, details};
  }

  return {
    ok: true,
    value: {
      apiUrl: normalizeApiBase(String(payload.apiUrl)),
      applicationId: String(payload.applicationId),
      apiVersion: Number(payload.apiVersion),
      repoRoot: String(payload.repoRoot),
      docsRoot: String(payload.docsRoot),
      processId: Number(payload.processId),
      startedAt: typeof payload.startedAt === 'string' ? payload.startedAt : undefined,
      modulePath: typeof payload.modulePath === 'string' ? payload.modulePath : undefined,
      scriptPath: typeof payload.scriptPath === 'string' ? payload.scriptPath : undefined,
      generatedAt: typeof payload.generatedAt === 'string' ? payload.generatedAt : undefined,
    },
  };
}

function validateHealthPayload(
  payload: unknown,
): {ok: true; value: EditorApiHealthPayload} | {ok: false; details: string[]} {
  if (!isRecord(payload)) {
    return {ok: false, details: ['Health payload root value was not an object.']};
  }

  const details: string[] = [];
  if (!isBoolean(payload.ok)) {
    details.push('Missing required boolean field `ok`.');
  }
  if (!isNonEmptyString(payload.applicationId)) {
    details.push('Missing required string field `applicationId`.');
  }
  if (!isFiniteNumber(payload.apiVersion)) {
    details.push('Missing required numeric field `apiVersion`.');
  }
  if (!isFiniteNumber(payload.processId)) {
    details.push('Missing required numeric field `processId`.');
  }
  if (!isNonEmptyString(payload.repoRoot)) {
    details.push('Missing required string field `repoRoot`.');
  }
  if (!isNonEmptyString(payload.docsRoot)) {
    details.push('Missing required string field `docsRoot`.');
  }
  if (payload.startedAt !== undefined && typeof payload.startedAt !== 'string') {
    details.push('Optional field `startedAt` must be a string when present.');
  }

  const capabilities = payload.capabilities;
  if (!isRecord(capabilities)) {
    details.push('Missing required object field `capabilities`.');
  } else {
    if (!isFiniteNumber(capabilities.authoringApiVersion)) {
      details.push('Missing required numeric field `capabilities.authoringApiVersion`.');
    }
    if (!isBoolean(capabilities.siteConfig)) {
      details.push('Missing required boolean field `capabilities.siteConfig`.');
    }
    if (!isBoolean(capabilities.domains)) {
      details.push('Missing required boolean field `capabilities.domains`.');
    }
    if (!isBoolean(capabilities.tree)) {
      details.push('Missing required boolean field `capabilities.tree`.');
    }
    if (!isBoolean(capabilities.visibility)) {
      details.push('Missing required boolean field `capabilities.visibility`.');
    }
  }

  if (details.length > 0) {
    return {ok: false, details};
  }

  return {
    ok: true,
    value: {
      ok: Boolean(payload.ok),
      applicationId: String(payload.applicationId),
      apiVersion: Number(payload.apiVersion),
      processId: Number(payload.processId),
      repoRoot: String(payload.repoRoot),
      docsRoot: String(payload.docsRoot),
      startedAt: typeof payload.startedAt === 'string' ? payload.startedAt : undefined,
      modulePath: typeof payload.modulePath === 'string' ? payload.modulePath : undefined,
      scriptPath: typeof payload.scriptPath === 'string' ? payload.scriptPath : undefined,
      capabilities: {
        authoringApiVersion: Number((payload.capabilities as Record<string, unknown>).authoringApiVersion),
        siteConfig: Boolean((payload.capabilities as Record<string, unknown>).siteConfig),
        domains: Boolean((payload.capabilities as Record<string, unknown>).domains),
        tree: Boolean((payload.capabilities as Record<string, unknown>).tree),
        visibility: Boolean((payload.capabilities as Record<string, unknown>).visibility),
      },
    },
  };
}

function createMismatchFailure(
  kind: AuthoringConnectionFailureKind,
  expected: EditorRuntimeConfig,
  health: EditorApiHealthPayload,
  apiBaseUrl: string,
  field: string,
  expectedValue: string | number | boolean,
  actualValue: unknown,
): AuthoringConnectionFailure {
  return {
    kind,
    transient: false,
    phase: 'health-probe',
    runtimeConfig: expected,
    apiBaseUrl,
    endpoint: `${apiBaseUrl}${EDITOR_API_HEALTH_PATH}`,
    field,
    expected: expectedValue,
    actual: actualValue,
  };
}

export function compareRuntimeIdentity(
  payload: EditorApiHealthPayload,
  expected: EditorRuntimeConfig | null,
  apiBaseUrl = DEFAULT_EDITOR_API_URL,
): AuthoringConnectionFailure | null {
  if (!expected) {
    return null;
  }

  if (payload.applicationId !== expected.applicationId) {
    return createMismatchFailure(
      'application-id-mismatch',
      expected,
      payload,
      apiBaseUrl,
      'applicationId',
      expected.applicationId,
      payload.applicationId,
    );
  }

  if (payload.apiVersion !== expected.apiVersion) {
    return createMismatchFailure('api-version-mismatch', expected, payload, apiBaseUrl, 'apiVersion', expected.apiVersion, payload.apiVersion);
  }

  if (normalizeComparablePath(payload.repoRoot) !== normalizeComparablePath(expected.repoRoot)) {
    return createMismatchFailure('repo-root-mismatch', expected, payload, apiBaseUrl, 'repoRoot', expected.repoRoot, payload.repoRoot);
  }

  if (normalizeComparablePath(payload.docsRoot) !== normalizeComparablePath(expected.docsRoot)) {
    return createMismatchFailure('docs-root-mismatch', expected, payload, apiBaseUrl, 'docsRoot', expected.docsRoot, payload.docsRoot);
  }

  if (payload.processId !== expected.processId) {
    return createMismatchFailure('process-id-mismatch', expected, payload, apiBaseUrl, 'processId', expected.processId, payload.processId);
  }

  return null;
}

async function readJsonResponse(response: Response): Promise<unknown> {
  return response.json();
}

async function loadRuntimeDescriptor(fetchImpl: FetchLike): Promise<RuntimeConfigLoadResult> {
  for (const runtimeConfigPath of RUNTIME_CONFIG_PATHS) {
    let response: Response;
    try {
      response = await fetchImpl(runtimeConfigPath, {cache: 'no-store'});
    } catch (error) {
      return {
        kind: 'runtime-descriptor-network-error',
        transient: true,
        phase: 'runtime-discovery',
        runtimeConfigPath,
        attemptedUrls: [...RUNTIME_CONFIG_PATHS],
        message: toErrorMessage(error),
      };
    }

    if (!response.ok) {
      if (response.status === 404) {
        continue;
      }

      return {
        kind: 'runtime-descriptor-http-error',
        transient: isRetryableHttpStatus(response.status),
        phase: 'runtime-discovery',
        runtimeConfigPath,
        attemptedUrls: [...RUNTIME_CONFIG_PATHS],
        status: response.status,
        message: response.statusText,
      };
    }

    let payload: unknown;
    try {
      payload = await readJsonResponse(response);
    } catch (error) {
      return {
        kind: 'runtime-descriptor-invalid-json',
        transient: false,
        phase: 'runtime-discovery',
        runtimeConfigPath,
        attemptedUrls: [...RUNTIME_CONFIG_PATHS],
        message: toErrorMessage(error),
      };
    }

    const validation = validateRuntimeConfigPayload(payload);
    if (validation.ok) {
      return {
        ok: true,
        runtimeConfigPath,
        runtimeConfig: validation.value,
      };
    }

    return {
      kind: 'runtime-descriptor-invalid-schema',
      transient: false,
      phase: 'runtime-discovery',
      runtimeConfigPath,
      attemptedUrls: [...RUNTIME_CONFIG_PATHS],
      details: (validation as {ok: false; details: string[]}).details,
    };
  }

  return {
    kind: 'runtime-descriptor-not-found',
    transient: true,
    phase: 'runtime-discovery',
    attemptedUrls: [...RUNTIME_CONFIG_PATHS],
  };
}

export async function probeApiBase(
  fetchImpl: FetchLike,
  apiBaseUrl: string,
  expectedRuntime: EditorRuntimeConfig | null,
  timeoutMs = EDITOR_API_PROBE_TIMEOUT_MS,
): Promise<AuthoringConnectionFailure | AuthoringConnectionSuccess> {
  const controller = new AbortController();
  const timeoutId = globalThis.setTimeout(() => controller.abort(), timeoutMs);
  const endpoint = `${apiBaseUrl}${EDITOR_API_HEALTH_PATH}`;

  try {
    let response: Response;
    try {
      response = await fetchImpl(endpoint, {
        cache: 'no-store',
        signal: controller.signal,
      });
    } catch (error) {
      if (isAbortError(error)) {
        return {
          kind: 'api-timeout',
          transient: true,
          phase: 'health-probe',
          runtimeConfig: expectedRuntime || undefined,
          apiBaseUrl,
          endpoint,
          message: `Timed out after ${timeoutMs} ms.`,
        };
      }

      return {
        kind: 'api-network-error',
        transient: true,
        phase: 'health-probe',
        runtimeConfig: expectedRuntime || undefined,
        apiBaseUrl,
        endpoint,
        message: toErrorMessage(error),
      };
    }

    if (!response.ok) {
      return {
        kind: 'api-http-error',
        transient: isRetryableHttpStatus(response.status),
        phase: 'health-probe',
        runtimeConfig: expectedRuntime || undefined,
        apiBaseUrl,
        endpoint,
        status: response.status,
        message: response.statusText,
      };
    }

    let payload: unknown;
    try {
      payload = await readJsonResponse(response);
    } catch (error) {
      return {
        kind: 'api-invalid-json',
        transient: false,
        phase: 'health-probe',
        runtimeConfig: expectedRuntime || undefined,
        apiBaseUrl,
        endpoint,
        message: toErrorMessage(error),
      };
    }

    const validation = validateHealthPayload(payload);
    if (validation.ok) {
      const health = validation.value;
      if (health.ok === false) {
        return {
          kind: 'api-unhealthy',
          transient: true,
          phase: 'health-probe',
          runtimeConfig: expectedRuntime || undefined,
          apiBaseUrl,
          endpoint,
        };
      }

      if (health.applicationId !== EDITOR_API_APPLICATION_ID) {
        return createMismatchFailure(
          'application-id-mismatch',
          expectedRuntime || {
            apiUrl: apiBaseUrl,
            applicationId: EDITOR_API_APPLICATION_ID,
            apiVersion: EDITOR_API_CAPABILITY_VERSION,
            repoRoot: health.repoRoot,
            docsRoot: health.docsRoot,
            processId: health.processId,
          },
          health,
          apiBaseUrl,
          'applicationId',
          EDITOR_API_APPLICATION_ID,
          health.applicationId,
        );
      }

      if (health.apiVersion !== EDITOR_API_CAPABILITY_VERSION) {
        return createMismatchFailure(
          'api-version-mismatch',
          expectedRuntime || {
            apiUrl: apiBaseUrl,
            applicationId: health.applicationId,
            apiVersion: EDITOR_API_CAPABILITY_VERSION,
            repoRoot: health.repoRoot,
            docsRoot: health.docsRoot,
            processId: health.processId,
          },
          health,
          apiBaseUrl,
          'apiVersion',
          EDITOR_API_CAPABILITY_VERSION,
          health.apiVersion,
        );
      }

      const capabilities = health.capabilities;
      if (
        capabilities.authoringApiVersion !== EDITOR_API_CAPABILITY_VERSION ||
        capabilities.siteConfig !== true ||
        capabilities.domains !== true ||
        capabilities.tree !== true ||
        capabilities.visibility !== true
      ) {
        return {
          kind: 'capability-mismatch',
          transient: false,
          phase: 'health-probe',
          runtimeConfig: expectedRuntime || undefined,
          apiBaseUrl,
          endpoint,
          field: 'capabilities',
          expected: 'authoringApiVersion=2, siteConfig=true, domains=true, tree=true, visibility=true',
          actual: capabilities,
        };
      }

      const identityFailure = compareRuntimeIdentity(health, expectedRuntime, apiBaseUrl);
      if (identityFailure) {
        return identityFailure;
      }

      return {
        kind: 'connected',
        transient: false,
        runtimeConfigPath: '',
        runtimeConfig: expectedRuntime || {
          apiUrl: apiBaseUrl,
          applicationId: health.applicationId,
          apiVersion: health.apiVersion,
          repoRoot: health.repoRoot,
          docsRoot: health.docsRoot,
          processId: health.processId,
          startedAt: health.startedAt,
          modulePath: health.modulePath,
          scriptPath: health.scriptPath,
        },
        apiBaseUrl,
        endpoint,
        attemptedUrls: [apiBaseUrl],
        health,
      };
    }

    return {
      kind: 'api-invalid-schema',
      transient: false,
      phase: 'health-probe',
      runtimeConfig: expectedRuntime || undefined,
      apiBaseUrl,
      endpoint,
      details: (validation as {ok: false; details: string[]}).details,
    };
  } catch (error) {
    return {
      kind: 'unexpected-error',
      transient: false,
      phase: 'health-probe',
      runtimeConfig: expectedRuntime || undefined,
      apiBaseUrl,
      endpoint,
      message: toErrorMessage(error),
    };
  } finally {
    globalThis.clearTimeout(timeoutId);
  }
}

function choosePreferredFailure(
  failures: AuthoringConnectionFailure[],
  attemptedUrls: string[],
): AuthoringConnectionFailure {
  const preferred = failures.find((failure) => !failure.transient) || failures[failures.length - 1];
  return {
    ...preferred,
    attemptedUrls,
  };
}

export async function resolveAuthoringConnection(
  fetchImpl: FetchLike,
  timeoutMs = EDITOR_API_PROBE_TIMEOUT_MS,
): Promise<AuthoringConnectionFailure | AuthoringConnectionSuccess> {
  const runtimeDescriptor = await loadRuntimeDescriptor(fetchImpl);
  if (!('ok' in runtimeDescriptor) || !runtimeDescriptor.ok) {
    return runtimeDescriptor as AuthoringConnectionFailure;
  }

  const {runtimeConfig, runtimeConfigPath} = runtimeDescriptor;
  const candidates = buildApiCandidates(runtimeConfig.apiUrl);
  const failures: AuthoringConnectionFailure[] = [];
  for (const candidate of candidates) {
    const result = await probeApiBase(fetchImpl, candidate, runtimeConfig, timeoutMs);
    if (result.kind === 'connected') {
      return {
        ...result,
        runtimeConfigPath,
        runtimeConfig,
        attemptedUrls: candidates,
      };
    }
    failures.push(result);
  }

  return choosePreferredFailure(failures, candidates);
}

export function shouldAutoRetryConnection(status: AuthoringConnectionStatus): boolean {
  if (status.kind === 'connected' || status.kind === 'checking') {
    return false;
  }

  return status.transient;
}

export function getRetryDelayMs(attempt: number): number {
  const index = Math.max(0, Math.min(RETRY_DELAYS_MS.length - 1, attempt));
  return RETRY_DELAYS_MS[index];
}

export function getConnectionLogSignature(status: AuthoringConnectionStatus): string {
  if (status.kind === 'connected' || status.kind === 'checking') {
    return status.kind;
  }

  return JSON.stringify({
    kind: status.kind,
    phase: status.phase,
    endpoint: status.endpoint,
    status: status.status,
    field: status.field,
    expected: status.expected,
    actual: status.actual,
    message: status.message,
    details: status.details,
  });
}

export function formatConnectionLogMessage(status: AuthoringConnectionFailure): string {
  const lines = [`[UEToolSuite Docs] ${getAuthoringConnectionPresentation(status).title}`];
  if (status.field) {
    lines.push(`Field: ${status.field}`);
  }
  if (status.expected !== undefined) {
    lines.push(`Expected: ${formatDiagnosticValue(status.expected)}`);
  }
  if (status.actual !== undefined) {
    lines.push(`Actual: ${formatDiagnosticValue(status.actual)}`);
  }
  if (status.endpoint) {
    lines.push(`Endpoint: ${status.endpoint}`);
  }
  if (status.status !== undefined) {
    lines.push(`HTTP status: ${status.status}`);
  }
  if (status.message) {
    lines.push(`Message: ${status.message}`);
  }
  if (status.details && status.details.length > 0) {
    lines.push(`Details: ${status.details.join(' | ')}`);
  }
  return lines.join('\n');
}

export function createAuthoringConnectionController(
  options: AuthoringConnectionControllerOptions = {},
): AuthoringConnectionController {
  const fetchImpl = options.fetchImpl ?? globalThis.fetch.bind(globalThis);
  const timeoutMs = options.timeoutMs ?? EDITOR_API_PROBE_TIMEOUT_MS;
  const connectedPollMs = options.connectedPollMs === undefined ? CONNECTED_HEALTH_POLL_MS : options.connectedPollMs;
  const setTimer = options.setTimer ?? globalThis.setTimeout.bind(globalThis);
  const clearTimer = options.clearTimer ?? globalThis.clearTimeout.bind(globalThis);
  const onStatus = options.onStatus ?? (() => undefined);
  const logFailure = options.logFailure ?? (() => undefined);

  let status: AuthoringConnectionStatus = {kind: 'checking'};
  let retryAttempt = 0;
  let inFlight = false;
  let stopped = false;
  let timerId: ReturnType<typeof globalThis.setTimeout> | null = null;
  let lastFailureSignature: string | null = null;

  function emit(nextStatus: AuthoringConnectionStatus): void {
    status = nextStatus;
    onStatus(nextStatus);

    if (nextStatus.kind === 'connected' || nextStatus.kind === 'checking') {
      if (nextStatus.kind === 'connected') {
        lastFailureSignature = null;
      }
      return;
    }

    const signature = getConnectionLogSignature(nextStatus);
    if (signature === lastFailureSignature) {
      return;
    }

    lastFailureSignature = signature;
    logFailure(nextStatus);
  }

  function clearRetryTimer(): void {
    if (timerId !== null) {
      clearTimer(timerId);
      timerId = null;
    }
  }

  function scheduleRetry(delayMs: number): void {
    clearRetryTimer();
    timerId = setTimer(() => {
      timerId = null;
      void runProbe();
    }, delayMs);
  }

  function scheduleConnectedPoll(): void {
    if (connectedPollMs === null || connectedPollMs <= 0) {
      return;
    }

    clearRetryTimer();
    timerId = setTimer(() => {
      timerId = null;
      void runProbe(true);
    }, connectedPollMs);
  }

  async function runProbe(backgroundRefresh = false): Promise<void> {
    if (stopped || inFlight) {
      return;
    }

    clearRetryTimer();
    inFlight = true;
    if (!(backgroundRefresh && status.kind === 'connected')) {
      emit({kind: 'checking'});
    }

    try {
      const result = await resolveAuthoringConnection(fetchImpl, timeoutMs);
      if (stopped) {
        return;
      }

      emit(result);
      if (result.kind === 'connected') {
        retryAttempt = 0;
        scheduleConnectedPoll();
        return;
      }

      if (!shouldAutoRetryConnection(result)) {
        return;
      }

      const delayMs = getRetryDelayMs(retryAttempt);
      retryAttempt += 1;
      scheduleRetry(delayMs);
    } finally {
      inFlight = false;
    }
  }

  return {
    getStatus(): AuthoringConnectionStatus {
      return status;
    },
    start(): void {
      if (stopped) {
        return;
      }
      void runProbe();
    },
    retry(): void {
      if (stopped) {
        return;
      }
      retryAttempt = 0;
      lastFailureSignature = null;
      clearRetryTimer();
      void runProbe();
    },
    stop(): void {
      stopped = true;
      clearRetryTimer();
    },
  };
}

function withTechnicalDetails(
  presentation: Omit<AuthoringConnectionPresentation, 'technicalDetails'>,
  entries: Array<[string, unknown]>,
): AuthoringConnectionPresentation {
  return {
    ...presentation,
    technicalDetails: entries
      .filter(([, value]) => value !== undefined && value !== null && formatDiagnosticValue(value).length > 0)
      .map(([label, value]) => ({label, value: formatDiagnosticValue(value)})),
  };
}

export function getAuthoringConnectionPresentation(status: AuthoringConnectionFailure): AuthoringConnectionPresentation {
  switch (status.kind) {
    case 'runtime-descriptor-not-found':
      return withTechnicalDetails(
        {
          title: 'Docs Editor runtime configuration was not found',
          summary: 'The frontend could not find `editor-runtime.json` for this project.',
          nextAction: 'Start the Docs Editor API for this project, then retry the connection.',
        },
        [['Checked paths', status.attemptedUrls?.join(', ')]],
      );
    case 'runtime-descriptor-http-error':
      return withTechnicalDetails(
        {
          title: 'The Docs runtime configuration could not be loaded',
          summary: 'The frontend found `editor-runtime.json`, but the request returned an HTTP error.',
          nextAction: 'Check the docs site runtime files, then retry the connection.',
        },
        [
          ['Runtime config path', status.runtimeConfigPath],
          ['HTTP status', status.status],
        ],
      );
    case 'runtime-descriptor-invalid-json':
      return withTechnicalDetails(
        {
          title: 'The Docs runtime configuration is invalid',
          summary: 'The frontend loaded `editor-runtime.json`, but it was not valid JSON.',
          nextAction: 'Restart the Docs Editor API for this project to regenerate the runtime configuration, then retry.',
        },
        [
          ['Runtime config path', status.runtimeConfigPath],
          ['Message', status.message],
        ],
      );
    case 'runtime-descriptor-invalid-schema':
      return withTechnicalDetails(
        {
          title: 'The Docs runtime configuration is invalid',
          summary: 'The frontend loaded `editor-runtime.json`, but it did not contain the required runtime identity fields.',
          nextAction: 'Restart the Docs Editor API for this project to regenerate the runtime configuration, then retry.',
        },
        [
          ['Runtime config path', status.runtimeConfigPath],
          ['Details', status.details?.join(' ')],
        ],
      );
    case 'runtime-descriptor-network-error':
      return withTechnicalDetails(
        {
          title: 'The Docs runtime configuration could not be read',
          summary: 'The frontend could not read `editor-runtime.json` because the request failed before a response was returned.',
          nextAction: 'Check that the docs site files are available, then retry the connection.',
        },
        [['Message', status.message]],
      );
    case 'api-network-error':
      return withTechnicalDetails(
        {
          title: 'Docs Editor API is not running',
          summary: 'The frontend could not connect to the configured Docs Editor API endpoint.',
          nextAction: 'Start the Docs Editor API for this project, then retry the connection.',
        },
        [['Endpoint', status.endpoint]],
      );
    case 'api-timeout':
      return withTechnicalDetails(
        {
          title: 'Docs Editor API timed out',
          summary: 'The frontend reached the Docs Editor API endpoint, but the health probe did not finish in time.',
          nextAction: 'Check that the Docs Editor API is responsive, then retry the connection.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Timeout', status.message],
        ],
      );
    case 'api-http-error':
      return withTechnicalDetails(
        {
          title: 'Docs Editor API returned an HTTP error',
          summary: 'The frontend reached the Docs Editor API endpoint, but the health request did not succeed.',
          nextAction: 'Check the running Docs Editor API and retry the connection.',
        },
        [
          ['Endpoint', status.endpoint],
          ['HTTP status', status.status],
        ],
      );
    case 'api-invalid-json':
      return withTechnicalDetails(
        {
          title: 'Docs Editor API returned invalid JSON',
          summary: 'The frontend reached the health endpoint, but the response body was not valid JSON.',
          nextAction: 'Restart or update the Docs Editor API so the health endpoint returns the expected response.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Message', status.message],
        ],
      );
    case 'api-invalid-schema':
      return withTechnicalDetails(
        {
          title: 'The Docs Editor API returned an unexpected response',
          summary: 'The frontend reached the health endpoint, but the JSON response did not match the expected schema.',
          nextAction: 'Restart or update the Docs Editor API so the frontend and backend use the same UEToolSuite version.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Details', status.details?.join(' ')],
        ],
      );
    case 'api-unhealthy':
      return withTechnicalDetails(
        {
          title: 'Docs Editor API reported an unhealthy state',
          summary: 'The health endpoint responded, but the API reported that it is not ready for authoring requests.',
          nextAction: 'Wait for the Docs Editor API to finish starting, or restart it if it stays unhealthy.',
        },
        [['Endpoint', status.endpoint]],
      );
    case 'application-id-mismatch':
      return withTechnicalDetails(
        {
          title: 'The running Docs Editor API belongs to another application',
          summary: 'The frontend found a healthy API endpoint, but it did not identify itself as the expected Docs Editor API.',
          nextAction: 'Stop the incompatible API process or start the correct Docs Editor API for this project, then retry.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Expected application ID', status.expected],
          ['Actual application ID', status.actual],
        ],
      );
    case 'api-version-mismatch':
      return withTechnicalDetails(
        {
          title: 'Docs Editor API version mismatch',
          summary: 'The frontend and backend disagree on the supported Docs authoring API version.',
          nextAction: 'Restart or update the Docs Editor API so the frontend and backend use the same UEToolSuite version.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Expected API version', status.expected],
          ['Actual API version', status.actual],
        ],
      );
    case 'capability-mismatch':
      return withTechnicalDetails(
        {
          title: 'Docs Editor API capability mismatch',
          summary: 'The frontend reached the API, but the required authoring capabilities were not all enabled.',
          nextAction: 'Restart or update the Docs Editor API so the expected authoring capabilities are available.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Expected capabilities', status.expected],
          ['Actual capabilities', status.actual],
        ],
      );
    case 'process-id-mismatch':
      return withTechnicalDetails(
        {
          title: 'The running Docs Editor API is not the expected process',
          summary: 'The frontend reached a healthy API, but its process identity does not match the runtime descriptor for this project.',
          nextAction: 'Stop the unexpected Docs Editor API process and start the API for this project, then retry.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Expected process ID', status.expected],
          ['Actual process ID', status.actual],
        ],
      );
    case 'repo-root-mismatch':
      return withTechnicalDetails(
        {
          title: 'The running Docs Editor API belongs to another project',
          summary: 'The frontend found a healthy Docs Editor API, but its project root does not match this website.',
          nextAction: 'Stop the other project API or start the Docs Editor API for this project, then retry.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Expected project', status.expected],
          ['API project', status.actual],
        ],
      );
    case 'docs-root-mismatch':
      return withTechnicalDetails(
        {
          title: 'The running Docs Editor API points at another Docs root',
          summary: 'The frontend found a healthy Docs Editor API, but its Docs root does not match this project.',
          nextAction: 'Start the Docs Editor API for the correct Docs root, then retry the connection.',
        },
        [
          ['Endpoint', status.endpoint],
          ['Expected Docs root', status.expected],
          ['API Docs root', status.actual],
        ],
      );
    case 'unexpected-error':
    default:
      return withTechnicalDetails(
        {
          title: 'Unexpected Docs authoring initialization error',
          summary: 'The frontend hit an unexpected error while initializing authoring support.',
          nextAction: 'Retry the connection. If the error persists, restart the Docs Editor API and the docs site.',
        },
        [['Message', status.message]],
      );
  }
}
