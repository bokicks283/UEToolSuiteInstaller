const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const Module = require('node:module');
const test = require('node:test');
const React = require('react');
const ReactDOMServer = require('react-dom/server');
const ts = require('typescript');

function installTsLoader() {
  const extensions = ['.ts', '.tsx'];
  const previous = new Map();
  const trackedModules = new Set();

  function compile(module, filename) {
    trackedModules.add(filename);
    const source = fs.readFileSync(filename, 'utf8');
    const transpiled = ts.transpileModule(source, {
      compilerOptions: {
        module: ts.ModuleKind.CommonJS,
        moduleResolution: ts.ModuleResolutionKind.NodeJs,
        target: ts.ScriptTarget.ES2020,
        jsx: ts.JsxEmit.ReactJSX,
        esModuleInterop: true,
      },
      fileName: filename,
    }).outputText;

    module._compile(transpiled, filename);
  }

  for (const extension of extensions) {
    previous.set(extension, Module._extensions[extension]);
    Module._extensions[extension] = compile;
  }

  return () => {
    for (const extension of extensions) {
      Module._extensions[extension] = previous.get(extension);
    }

    for (const filename of trackedModules) {
      delete require.cache[filename];
    }
  };
}

function loadAuthoringModules() {
  const restore = installTsLoader();
  try {
    const runtimePath = path.resolve(__dirname, '..', 'src', 'theme', 'authoring', 'runtimeDiscovery.ts');
    const apiPath = path.resolve(__dirname, '..', 'src', 'theme', 'authoring', 'api.ts');
    const cardPath = path.resolve(
      __dirname,
      '..',
      'src',
      'theme',
      'authoring',
      'AuthoringConnectionStatusCard.tsx',
    );
    const docPageAuthoringPath = path.resolve(
      __dirname,
      '..',
      'src',
      'theme',
      'authoring',
      'docPageAuthoring.ts',
    );
    return {
      api: require(apiPath),
      docPageAuthoring: require(docPageAuthoringPath),
      runtime: require(runtimePath),
      StatusCard: require(cardPath).default,
    };
  } finally {
    restore();
  }
}

function createExpectedRuntime(overrides = {}) {
  return {
    apiUrl: 'http://127.0.0.1:38473/',
    applicationId: 'UEToolSuiteDocsEditorApi',
    apiVersion: 2,
    repoRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG',
    docsRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG\\Docs',
    processId: 83288,
    startedAt: '07/01/2026 23:48:57',
    ...overrides,
  };
}

function createHealthPayload(overrides = {}) {
  return {
    ok: true,
    applicationId: 'UEToolSuiteDocsEditorApi',
    apiVersion: 2,
    processId: 83288,
    repoRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG',
    docsRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG\\Docs',
    startedAt: '2026-07-01T23:48:57.5905015-04:00',
    capabilities: {
      authoringApiVersion: 2,
      siteConfig: true,
      domains: true,
      tree: true,
      visibility: true,
    },
    ...overrides,
  };
}

function createJsonResponse(body, options = {}) {
  const {ok = true, status = ok ? 200 : 500, statusText = ok ? 'OK' : 'Error'} = options;
  return {
    ok,
    status,
    statusText,
    async json() {
      return body;
    },
  };
}

function createInvalidJsonResponse(message = 'Invalid JSON') {
  return {
    ok: true,
    status: 200,
    statusText: 'OK',
    async json() {
      throw new Error(message);
    },
  };
}

function createDescriptorAwareFetch(healthHandler) {
  return async (url) => {
    if (url === '/ue-tools/editor-runtime.json') {
      return createJsonResponse(createExpectedRuntime());
    }

    if (url === '/.ue-tools/editor-runtime.json') {
      return createJsonResponse({}, {ok: false, status: 404, statusText: 'Not Found'});
    }

    return healthHandler(url);
  };
}

function createScheduler() {
  let nextId = 1;
  const timers = [];

  return {
    setTimeout(callback, delay) {
      const timer = {id: nextId++, callback, delay};
      timers.push(timer);
      return timer.id;
    },
    clearTimeout(id) {
      const index = timers.findIndex((timer) => timer.id === id);
      if (index >= 0) {
        timers.splice(index, 1);
      }
    },
    getTimers() {
      return timers.map((timer) => ({...timer}));
    },
    async fireNext() {
      assert.ok(timers.length > 0, 'Expected a queued timer to fire.');
      const timer = timers.shift();
      await timer.callback();
      return timer;
    },
  };
}

function deferred() {
  let resolve;
  let reject;
  const promise = new Promise((res, rej) => {
    resolve = res;
    reject = rej;
  });
  return {promise, resolve, reject};
}

async function flushAsyncWork() {
  await Promise.resolve();
  await Promise.resolve();
  await new Promise((resolve) => setImmediate(resolve));
}

async function waitFor(condition, message) {
  for (let attempt = 0; attempt < 20; attempt += 1) {
    await flushAsyncWork();
    if (condition()) {
      return;
    }
  }

  assert.fail(message);
}

function renderStatusCard(StatusCard, status) {
  return ReactDOMServer.renderToStaticMarkup(
    React.createElement(StatusCard, {
      status,
      onRetry() {},
    }),
  );
}

test('identity matching accepts equivalent runtime when only startedAt formatting differs', async () => {
  const {runtime} = loadAuthoringModules();
  const expected = createExpectedRuntime();
  const health = createHealthPayload();

  assert.equal(runtime.compareRuntimeIdentity(health, expected), null);

  const result = await runtime.probeApiBase(
    async () => createJsonResponse(health),
    expected.apiUrl,
    expected,
    50,
  );

  assert.equal(result.kind, 'connected');
});

test('identity matching ignores different startedAt values on the same runtime', () => {
  const {runtime} = loadAuthoringModules();
  const expected = createExpectedRuntime({startedAt: 'yesterday'});
  const health = createHealthPayload({startedAt: 'tomorrow'});

  assert.equal(runtime.compareRuntimeIdentity(health, expected), null);
});

test('identity matching accepts repo and docs roots with case, slash, and trailing separator differences', () => {
  const {runtime} = loadAuthoringModules();
  const expected = createExpectedRuntime({
    repoRoot: 'c:/users/rim28/projects/cppcozyrpg/',
    docsRoot: 'c:/users/rim28/projects/cppcozyrpg/docs/',
  });
  const health = createHealthPayload({
    repoRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG',
    docsRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG\\Docs',
  });

  assert.equal(runtime.compareRuntimeIdentity(health, expected), null);
});

test('identity matching rejects different repo roots', () => {
  const {runtime} = loadAuthoringModules();
  const result = runtime.compareRuntimeIdentity(
    createHealthPayload({repoRoot: 'C:\\Users\\Rim28\\Projects\\OtherProject'}),
    createExpectedRuntime(),
  );

  assert.equal(result.kind, 'repo-root-mismatch');
});

test('identity matching rejects different docs roots', () => {
  const {runtime} = loadAuthoringModules();
  const result = runtime.compareRuntimeIdentity(
    createHealthPayload({docsRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG\\OtherDocs'}),
    createExpectedRuntime(),
  );

  assert.equal(result.kind, 'docs-root-mismatch');
});

test('identity matching rejects different process ids', () => {
  const {runtime} = loadAuthoringModules();
  const result = runtime.compareRuntimeIdentity(
    createHealthPayload({processId: 42}),
    createExpectedRuntime(),
  );

  assert.equal(result.kind, 'process-id-mismatch');
});

test('identity matching rejects different application ids', async () => {
  const {runtime} = loadAuthoringModules();
  const result = await runtime.probeApiBase(
    async () => createJsonResponse(createHealthPayload({applicationId: 'OtherApi'})),
    'http://127.0.0.1:38473/',
    createExpectedRuntime(),
    50,
  );

  assert.equal(result.kind, 'application-id-mismatch');
});

test('identity matching rejects different api versions', async () => {
  const {runtime} = loadAuthoringModules();
  const result = await runtime.probeApiBase(
    async () => createJsonResponse(createHealthPayload({apiVersion: 1})),
    'http://127.0.0.1:38473/',
    createExpectedRuntime(),
    50,
  );

  assert.equal(result.kind, 'api-version-mismatch');
});

test('connection diagnostics classify network, timeout, http, and malformed JSON failures', async () => {
  const {runtime} = loadAuthoringModules();
  const expected = createExpectedRuntime();

  const network = await runtime.probeApiBase(
    async () => {
      throw new Error('connect ECONNREFUSED');
    },
    expected.apiUrl,
    expected,
    50,
  );
  assert.equal(network.kind, 'api-network-error');

  const timeout = await runtime.probeApiBase(
    async () => {
      const error = new Error('aborted');
      error.name = 'AbortError';
      throw error;
    },
    expected.apiUrl,
    expected,
    50,
  );
  assert.equal(timeout.kind, 'api-timeout');

  const http = await runtime.probeApiBase(
    async () => createJsonResponse({}, {ok: false, status: 503, statusText: 'Service Unavailable'}),
    expected.apiUrl,
    expected,
    50,
  );
  assert.equal(http.kind, 'api-http-error');

  const invalidJson = await runtime.probeApiBase(
    async () => createInvalidJsonResponse(),
    expected.apiUrl,
    expected,
    50,
  );
  assert.equal(invalidJson.kind, 'api-invalid-json');
});

test('connection diagnostics classify capability, process, repo, docs, and runtime-descriptor failures', async () => {
  const {runtime} = loadAuthoringModules();

  const capability = await runtime.resolveAuthoringConnection(
    createDescriptorAwareFetch(async () =>
      createJsonResponse(
        createHealthPayload({
          capabilities: {
            authoringApiVersion: 2,
            siteConfig: true,
            domains: false,
            tree: true,
            visibility: true,
          },
        }),
      ),
    ),
    50,
  );
  assert.equal(capability.kind, 'capability-mismatch');

  const process = await runtime.resolveAuthoringConnection(
    createDescriptorAwareFetch(async () => createJsonResponse(createHealthPayload({processId: 99999}))),
    50,
  );
  assert.equal(process.kind, 'process-id-mismatch');

  const repo = await runtime.resolveAuthoringConnection(
    createDescriptorAwareFetch(async () =>
      createJsonResponse(createHealthPayload({repoRoot: 'C:\\Users\\Rim28\\Projects\\OtherProject'})),
    ),
    50,
  );
  assert.equal(repo.kind, 'repo-root-mismatch');

  const docs = await runtime.resolveAuthoringConnection(
    createDescriptorAwareFetch(async () =>
      createJsonResponse(createHealthPayload({docsRoot: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG\\OtherDocs'})),
    ),
    50,
  );
  assert.equal(docs.kind, 'docs-root-mismatch');

  const descriptorInvalid = await runtime.resolveAuthoringConnection(async (url) => {
    if (url === '/ue-tools/editor-runtime.json') {
      return createJsonResponse({apiUrl: 'http://127.0.0.1:38473/'});
    }

    throw new Error(`Unexpected fetch: ${url}`);
  }, 50);
  assert.equal(descriptorInvalid.kind, 'runtime-descriptor-invalid-schema');
});

test('connection diagnostics classify invalid backend response schemas', async () => {
  const {runtime} = loadAuthoringModules();
  const result = await runtime.resolveAuthoringConnection(
    createDescriptorAwareFetch(async () => createJsonResponse({ok: true})),
    50,
  );

  assert.equal(result.kind, 'api-invalid-schema');
});

test('status card renders useful messages for key failure categories', () => {
  const {StatusCard} = loadAuthoringModules();

  const unreachableMarkup = renderStatusCard(StatusCard, {
    kind: 'api-network-error',
    transient: true,
    phase: 'health-probe',
    apiBaseUrl: 'http://127.0.0.1:38473/',
    endpoint: 'http://127.0.0.1:38473/health',
  });
  assert.match(unreachableMarkup, /Docs Editor API is not running/);
  assert.match(unreachableMarkup, /Retry connection/);
  assert.match(unreachableMarkup, /http:\/\/127\.0\.0\.1:38473\/health/);

  const versionMismatchMarkup = renderStatusCard(StatusCard, {
    kind: 'api-version-mismatch',
    transient: false,
    phase: 'health-probe',
    endpoint: 'http://127.0.0.1:38473/health',
    field: 'apiVersion',
    expected: 2,
    actual: 1,
  });
  assert.match(versionMismatchMarkup, /Docs Editor API version mismatch/);
  assert.match(versionMismatchMarkup, /Expected API version/);
  assert.match(versionMismatchMarkup, /Actual API version/);

  const projectMismatchMarkup = renderStatusCard(StatusCard, {
    kind: 'repo-root-mismatch',
    transient: false,
    phase: 'health-probe',
    endpoint: 'http://127.0.0.1:38473/health',
    field: 'repoRoot',
    expected: 'C:\\Users\\Rim28\\Projects\\cppCozyRPG',
    actual: 'C:\\Users\\Rim28\\Projects\\OtherProject',
  });
  assert.match(projectMismatchMarkup, /belongs to another project/);
  assert.match(projectMismatchMarkup, /Expected project/);
  assert.match(projectMismatchMarkup, /API project/);

  const invalidRuntimeMarkup = renderStatusCard(StatusCard, {
    kind: 'runtime-descriptor-invalid-schema',
    transient: false,
    phase: 'runtime-discovery',
    runtimeConfigPath: '/ue-tools/editor-runtime.json',
    details: ['Missing required numeric field `apiVersion`.'],
  });
  assert.match(invalidRuntimeMarkup, /runtime configuration is invalid/);
  assert.match(invalidRuntimeMarkup, /editor-runtime\.json/);

  const invalidBackendMarkup = renderStatusCard(StatusCard, {
    kind: 'api-invalid-schema',
    transient: false,
    phase: 'health-probe',
    endpoint: 'http://127.0.0.1:38473/health',
    details: ['Missing required object field `capabilities`.'],
  });
  assert.match(invalidBackendMarkup, /unexpected response/);
  assert.match(invalidBackendMarkup, /Technical details/);
});

test('resolveSourceToken normalizes site-relative docs sources', () => {
  const {api} = loadAuthoringModules();
  assert.equal(
    api.resolveSourceToken('@site/../Docs/WorkflowStandards/README.md'),
    'WorkflowStandards/README.md',
  );
});

test('doc page authoring state enables edit and visibility actions when runtime is connected', () => {
  const {docPageAuthoring} = loadAuthoringModules();
  const state = docPageAuthoring.getDocPageAuthoringState({
    sourceToken: 'WorkflowStandards/README.md',
    runtimeReady: true,
    runtimeAvailable: true,
    connectionStatus: {
      kind: 'connected',
      transient: false,
      runtimeConfigPath: '/ue-tools/editor-runtime.json',
      runtimeConfig: createExpectedRuntime(),
      apiBaseUrl: 'http://127.0.0.1:38473/',
      endpoint: 'http://127.0.0.1:38473/health',
      attemptedUrls: ['http://127.0.0.1:38473/'],
      health: createHealthPayload(),
    },
  });

  assert.equal(state.pageIsEditable, true);
  assert.equal(state.authoringAvailable, true);
  assert.equal(state.pageCanManageVisibility, true);
  assert.equal(state.showConnectionNotice, false);
});

test('doc page authoring state shows structured connection notice when an editable document cannot connect', () => {
  const {docPageAuthoring} = loadAuthoringModules();
  const state = docPageAuthoring.getDocPageAuthoringState({
    sourceToken: 'WorkflowStandards/README.md',
    runtimeReady: true,
    runtimeAvailable: false,
    connectionStatus: {
      kind: 'api-http-error',
      transient: true,
      phase: 'health-probe',
      apiBaseUrl: '/__ue_docs_api__/',
      endpoint: '/__ue_docs_api__/health',
      status: 504,
      message: 'Gateway Timeout',
    },
  });

  assert.equal(state.authoringAvailable, false);
  assert.equal(state.pageCanManageVisibility, false);
  assert.equal(state.showConnectionNotice, true);
  assert.equal(state.connectionFailure?.kind, 'api-http-error');
});

test('doc page authoring state does not flash a connection error while discovery is still pending', () => {
  const {docPageAuthoring} = loadAuthoringModules();
  const state = docPageAuthoring.getDocPageAuthoringState({
    sourceToken: 'WorkflowStandards/README.md',
    runtimeReady: false,
    runtimeAvailable: false,
    connectionStatus: {kind: 'checking'},
  });

  assert.equal(state.showConnectionNotice, false);
  assert.equal(state.connectionFailure, null);
});

test('doc page authoring state suppresses authoring diagnostics for non-editable category records', () => {
  const {docPageAuthoring} = loadAuthoringModules();
  const state = docPageAuthoring.getDocPageAuthoringState({
    sourceToken: 'WorkflowStandards/_category_.json',
    runtimeReady: true,
    runtimeAvailable: false,
    connectionStatus: {
      kind: 'api-network-error',
      transient: true,
      phase: 'health-probe',
      apiBaseUrl: 'http://127.0.0.1:38473/',
      endpoint: 'http://127.0.0.1:38473/health',
    },
  });

  assert.equal(state.pageIsEditable, false);
  assert.equal(state.pageSupportsVisibility, false);
  assert.equal(state.pageSupportsAuthoringUi, false);
  assert.equal(state.showConnectionNotice, false);
});

test('controller backs off transient failures and stops retrying after success', async () => {
  const {runtime} = loadAuthoringModules();
  const scheduler = createScheduler();
  const attempts = [];
  let primaryAttempt = 0;

  const controller = runtime.createAuthoringConnectionController({
    fetchImpl: createDescriptorAwareFetch(async (url) => {
      if (url === 'http://127.0.0.1:38473/health') {
        attempts.push(primaryAttempt);
        if (primaryAttempt < 2) {
          primaryAttempt += 1;
          throw new Error('connect ECONNREFUSED');
        }

        return createJsonResponse(createHealthPayload());
      }

      throw new Error('connect ECONNREFUSED');
    }),
    connectedPollMs: null,
    setTimer: scheduler.setTimeout,
    clearTimer: scheduler.clearTimeout,
  });

  controller.start();
  await waitFor(() => scheduler.getTimers().length === 1, 'Expected first retry timer to be scheduled.');
  let timers = scheduler.getTimers();
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 1000);

  await scheduler.fireNext();
  await waitFor(() => scheduler.getTimers().length === 1, 'Expected second retry timer to be scheduled.');
  timers = scheduler.getTimers();
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 2000);

  await scheduler.fireNext();
  await waitFor(() => controller.getStatus().kind === 'connected', 'Expected controller to connect successfully.');
  timers = scheduler.getTimers();
  assert.equal(timers.length, 0);
  assert.equal(controller.getStatus().kind, 'connected');
  assert.deepEqual(attempts, [0, 1, 2]);
});

test('controller does not auto-retry persistent identity failures', async () => {
  const {runtime} = loadAuthoringModules();
  const scheduler = createScheduler();

  const controller = runtime.createAuthoringConnectionController({
    fetchImpl: createDescriptorAwareFetch(async () =>
      createJsonResponse(createHealthPayload({repoRoot: 'C:\\Users\\Rim28\\Projects\\OtherProject'})),
    ),
    connectedPollMs: null,
    setTimer: scheduler.setTimeout,
    clearTimer: scheduler.clearTimeout,
  });

  controller.start();
  await waitFor(
    () => controller.getStatus().kind === 'repo-root-mismatch',
    'Expected controller to settle on repo-root-mismatch.',
  );

  assert.equal(controller.getStatus().kind, 'repo-root-mismatch');
  assert.equal(scheduler.getTimers().length, 0);
});

test('controller manual retry runs immediately, keeps one timer, and stop cleans up timers', async () => {
  const {runtime} = loadAuthoringModules();
  const scheduler = createScheduler();
  let primaryAttempts = 0;

  const controller = runtime.createAuthoringConnectionController({
    fetchImpl: createDescriptorAwareFetch(async (url) => {
      if (url === 'http://127.0.0.1:38473/health') {
        primaryAttempts += 1;
      }
      throw new Error('connect ECONNREFUSED');
    }),
    connectedPollMs: null,
    setTimer: scheduler.setTimeout,
    clearTimer: scheduler.clearTimeout,
  });

  controller.start();
  await waitFor(() => scheduler.getTimers().length === 1, 'Expected retry timer after first transient failure.');
  assert.equal(scheduler.getTimers().length, 1);

  controller.retry();
  await waitFor(() => primaryAttempts === 2, 'Expected manual retry to trigger a second probe immediately.');
  assert.equal(primaryAttempts, 2);
  assert.equal(scheduler.getTimers().length, 1);

  controller.stop();
  assert.equal(scheduler.getTimers().length, 0);
});

test('controller does not overlap probes while a prior probe is still running', async () => {
  const {runtime} = loadAuthoringModules();
  const scheduler = createScheduler();
  const healthDeferred = deferred();
  let healthRequests = 0;

  const controller = runtime.createAuthoringConnectionController({
    fetchImpl: createDescriptorAwareFetch(async () => {
      healthRequests += 1;
      return healthDeferred.promise;
    }),
    connectedPollMs: null,
    setTimer: scheduler.setTimeout,
    clearTimer: scheduler.clearTimeout,
  });

  controller.start();
  controller.retry();
  await waitFor(() => healthRequests === 1, 'Expected only one in-flight health probe.');
  assert.equal(healthRequests, 1);

  healthDeferred.resolve(createJsonResponse(createHealthPayload()));
  await waitFor(() => controller.getStatus().kind === 'connected', 'Expected deferred probe to resolve as connected.');

  assert.equal(controller.getStatus().kind, 'connected');
  assert.equal(scheduler.getTimers().length, 0);
});

test('controller keeps monitoring a connected runtime without dropping back to checking', async () => {
  const {runtime} = loadAuthoringModules();
  const scheduler = createScheduler();
  var healthChecks = 0;

  const controller = runtime.createAuthoringConnectionController({
    fetchImpl: createDescriptorAwareFetch(async () => {
      healthChecks += 1;
      return createJsonResponse(createHealthPayload());
    }),
    connectedPollMs: 5000,
    setTimer: scheduler.setTimeout,
    clearTimer: scheduler.clearTimeout,
  });

  controller.start();
  await waitFor(() => controller.getStatus().kind === 'connected', 'Expected controller to connect successfully.');
  var timers = scheduler.getTimers();
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 5000);

  await scheduler.fireNext();
  await waitFor(() => controller.getStatus().kind === 'connected', 'Expected controller to stay connected after health poll.');
  timers = scheduler.getTimers();
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 5000);
  assert.equal(healthChecks, 2);
});

test('controller reports a lost runtime after a successful connection and schedules transient retry', async () => {
  const {runtime} = loadAuthoringModules();
  const scheduler = createScheduler();
  var healthChecks = 0;

  const controller = runtime.createAuthoringConnectionController({
    fetchImpl: createDescriptorAwareFetch(async () => {
      healthChecks += 1;
      if (healthChecks === 1) {
        return createJsonResponse(createHealthPayload());
      }
      throw new Error('connect ECONNREFUSED');
    }),
    connectedPollMs: 5000,
    setTimer: scheduler.setTimeout,
    clearTimer: scheduler.clearTimeout,
  });

  controller.start();
  await waitFor(() => controller.getStatus().kind === 'connected', 'Expected controller to connect successfully.');
  var timers = scheduler.getTimers();
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 5000);

  await scheduler.fireNext();
  await waitFor(
    () => controller.getStatus().kind === 'api-network-error',
    'Expected connected health monitoring to surface the lost runtime.',
  );

  timers = scheduler.getTimers();
  assert.equal(timers.length, 1);
  assert.equal(timers[0].delay, 1000);
  assert.equal(healthChecks, 3);
});
