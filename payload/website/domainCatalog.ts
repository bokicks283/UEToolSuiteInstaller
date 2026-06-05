import fs from 'node:fs';
import path from 'node:path';

import type {SidebarsConfig} from '@docusaurus/plugin-content-docs';

export type DocsDomainDefinition = {
  key: string;
  dirName: string;
  sidebarId: string;
  label: string;
  position: number;
  docId?: string;
  description?: string;
  ownedRoots: string[];
  ownedDocs: string[];
  catchAll?: boolean;
};

export type GeneralDocsDefinition = {
  sidebarId: string;
  label: string;
  docIds: string[];
};

export type DocsDomainCatalog = {
  domains: DocsDomainDefinition[];
  generalDocs: GeneralDocsDefinition | null;
};

type RawDomainConfig = {
  schemaVersion?: number;
  domains?: Array<{
    key?: string;
    dirName?: string;
    sidebarId?: string;
    label?: string;
    position?: number;
    landingDoc?: string;
    description?: string;
    ownedRoots?: string[];
    ownedDocs?: string[];
    catchAll?: boolean;
  }>;
};

const DOCS_ROOT = path.resolve(__dirname, '../Docs');
const DOMAINS_CONFIG_PATH = path.join(DOCS_ROOT, '_domains.json');
const MARKDOWN_EXTENSIONS = new Set(['.md', '.mdx']);
const STANDARD_DIR_NAMES = new Set([
  'workflowstandards',
  'workflow',
  'codingstandards',
  'docssite',
  'ai',
  'aicontext',
  'testing',
  'pipeline',
  'setup',
  'gitstandards',
  'unrealstandards',
]);
const STANDARD_DOC_IDS = new Set(['setup', 'testing']);

function isMarkdownFile(fileName: string): boolean {
  return MARKDOWN_EXTENSIONS.has(path.extname(fileName).toLowerCase());
}

function isVisibleDirectory(entryName: string): boolean {
  return !!entryName && !entryName.startsWith('.');
}

function normalizeToken(value: string): string {
  return value.replace(/\\/g, '/').replace(/^\/+|\/+$/g, '').trim();
}

function toDocId(fullPath: string): string {
  const relativePath = path.relative(DOCS_ROOT, fullPath).replace(/\\/g, '/');
  return relativePath.replace(/\.(md|mdx)$/i, '');
}

function toSidebarId(value: string): string {
  const slug = normalizeToken(value)
    .replace(/([a-z0-9])([A-Z])/g, '$1-$2')
    .replace(/[^A-Za-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '')
    .toLowerCase();
  return slug ? `${slug}-sidebar` : 'docs-sidebar';
}

function toDisplayLabel(value: string): string {
  return value
    .replace(/([a-z0-9])([A-Z])/g, '$1 $2')
    .replace(/[-_]+/g, ' ')
    .replace(/\s+/g, ' ')
    .trim()
    .replace(/\b\w/g, (letter) => letter.toUpperCase());
}

function readJsonFile(filePath: string): Record<string, unknown> | null {
  try {
    return JSON.parse(fs.readFileSync(filePath, 'utf8')) as Record<string, unknown>;
  } catch {
    return null;
  }
}

function readDomainsConfig(): RawDomainConfig | null {
  if (!fs.existsSync(DOMAINS_CONFIG_PATH)) {
    return null;
  }
  try {
    return JSON.parse(fs.readFileSync(DOMAINS_CONFIG_PATH, 'utf8')) as RawDomainConfig;
  } catch {
    return null;
  }
}

function readTextFile(filePath: string): string {
  try {
    return fs.readFileSync(filePath, 'utf8');
  } catch {
    return '';
  }
}

function extractFrontMatterValue(content: string, key: string): string {
  const frontMatterMatch = content.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*/);
  if (!frontMatterMatch) {
    return '';
  }
  const pattern = new RegExp(`^\\s*${key}\\s*:\\s*(.+?)\\s*$`, 'm');
  const frontMatterBody = frontMatterMatch[1] ?? '';
  const match = frontMatterBody.match(pattern);
  return match ? match[1].trim().replace(/^['"]|['"]$/g, '') : '';
}

function extractHeading(content: string): string {
  const match = content.match(/^\#\s+(.+?)\s*$/m);
  return match ? match[1].trim() : '';
}

function getDirectoryReadmePath(directoryPath: string): string | null {
  const candidates = ['README.md', 'README.mdx', 'index.md', 'index.mdx'];
  for (const candidate of candidates) {
    const fullPath = path.join(directoryPath, candidate);
    if (fs.existsSync(fullPath) && fs.statSync(fullPath).isFile()) {
      return fullPath;
    }
  }
  return null;
}

function getDirectoryLabel(directoryPath: string, fallbackName: string): string {
  const categoryJson = readJsonFile(path.join(directoryPath, '_category_.json'));
  const categoryLabel = typeof categoryJson?.label === 'string' ? categoryJson.label.trim() : '';
  if (categoryLabel) {
    return categoryLabel;
  }

  const readmePath = getDirectoryReadmePath(directoryPath);
  if (readmePath) {
    const content = readTextFile(readmePath);
    const title = extractFrontMatterValue(content, 'title') || extractHeading(content);
    if (title) {
      return title;
    }
  }

  return toDisplayLabel(fallbackName);
}

function getDirectoryDescription(directoryPath: string): string {
  const readmePath = getDirectoryReadmePath(directoryPath);
  if (!readmePath) {
    return '';
  }
  const content = readTextFile(readmePath);
  return extractFrontMatterValue(content, 'description');
}

function getDirectoryPosition(directoryPath: string): number {
  const categoryJson = readJsonFile(path.join(directoryPath, '_category_.json'));
  const rawPosition = categoryJson?.position;
  if (typeof rawPosition === 'number' && Number.isFinite(rawPosition)) {
    return rawPosition;
  }
  if (typeof rawPosition === 'string') {
    const parsed = Number.parseFloat(rawPosition);
    if (Number.isFinite(parsed)) {
      return parsed;
    }
  }
  return Number.POSITIVE_INFINITY;
}

function directoryHasDocsContent(directoryPath: string): boolean {
  const entries = fs.readdirSync(directoryPath, {withFileTypes: true});
  for (const entry of entries) {
    if (entry.isFile() && isMarkdownFile(entry.name)) {
      return true;
    }
    if (entry.isDirectory() && isVisibleDirectory(entry.name) && directoryHasDocsContent(path.join(directoryPath, entry.name))) {
      return true;
    }
  }
  return false;
}

function getTopLevelDirectoryNames(): string[] {
  if (!fs.existsSync(DOCS_ROOT)) {
    return [];
  }
  return fs
    .readdirSync(DOCS_ROOT, {withFileTypes: true})
    .filter((entry) => entry.isDirectory() && isVisibleDirectory(entry.name) && directoryHasDocsContent(path.join(DOCS_ROOT, entry.name)))
    .map((entry) => entry.name)
    .sort((left, right) => left.localeCompare(right));
}

function getTopLevelMarkdownDocIds(): string[] {
  if (!fs.existsSync(DOCS_ROOT)) {
    return [];
  }
  return fs
    .readdirSync(DOCS_ROOT, {withFileTypes: true})
    .filter((entry) => entry.isFile() && isMarkdownFile(entry.name) && !/^readme\.(md|mdx)$/i.test(entry.name))
    .sort((left, right) => left.name.localeCompare(right.name))
    .map((entry) => toDocId(path.join(DOCS_ROOT, entry.name)));
}

function findDocPathFromDocId(docId: string): string | null {
  const normalized = normalizeToken(docId);
  if (!normalized) {
    return null;
  }

  for (const extension of MARKDOWN_EXTENSIONS) {
    const fullPath = path.join(DOCS_ROOT, `${normalized}${extension}`);
    if (fs.existsSync(fullPath) && fs.statSync(fullPath).isFile()) {
      return fullPath;
    }
  }

  return null;
}

function buildDefaultDomainConfig(topLevelDirectories: string[], topLevelDocIds: string[]): DocsDomainDefinition[] {
  const standardRoots = topLevelDirectories.filter((entry) => STANDARD_DIR_NAMES.has(entry.toLowerCase()));
  const projectRoots = topLevelDirectories.filter((entry) => !STANDARD_DIR_NAMES.has(entry.toLowerCase()));
  const standardDocs = topLevelDocIds.filter((entry) => STANDARD_DOC_IDS.has(entry.toLowerCase()));
  const projectDocs = topLevelDocIds.filter((entry) => !STANDARD_DOC_IDS.has(entry.toLowerCase()));

  return [
    {
      key: 'workflow-standards',
      dirName: 'WorkflowStandards',
      sidebarId: 'workflow-standards-sidebar',
      label: 'Workflow & Standards',
      position: 10,
      docId: 'WorkflowStandards/README',
      description: 'Best practices, setup guidance, and technical standards for the project.',
      ownedRoots: Array.from(new Set(['WorkflowStandards', ...standardRoots])),
      ownedDocs: standardDocs,
      catchAll: false,
    },
    {
      key: 'project-docs',
      dirName: 'ProjectDocs',
      sidebarId: 'project-docs-sidebar',
      label: 'Project Docs',
      position: 20,
      docId: 'ProjectDocs/README',
      description: 'Project-specific design, gameplay, and implementation documentation.',
      ownedRoots: Array.from(new Set(['ProjectDocs', ...projectRoots])),
      ownedDocs: projectDocs,
      catchAll: projectRoots.length === 0 && projectDocs.length === 0,
    },
  ];
}

function normalizeConfigDomains(rawConfig: RawDomainConfig | null, topLevelDirectories: string[], topLevelDocIds: string[]): DocsDomainDefinition[] {
  const configuredDomains = rawConfig?.domains ?? [];
  if (configuredDomains.length === 0) {
    return buildDefaultDomainConfig(topLevelDirectories, topLevelDocIds);
  }

  const claimedRoots = new Set<string>();
  const claimedDocs = new Set<string>();
  const domains: DocsDomainDefinition[] = configuredDomains.map((entry, index) => {
    const key = normalizeToken(entry.key || entry.dirName || `domain-${index + 1}`) || `domain-${index + 1}`;
    const dirName = normalizeToken(entry.dirName || key) || key;
    const landingDoc = normalizeToken(entry.landingDoc || `${dirName}/README`);
    const sidebarId = normalizeToken(entry.sidebarId || toSidebarId(key)) || toSidebarId(key);
    const label = (entry.label || toDisplayLabel(dirName)).trim();
    const ownedRoots = Array.from(
      new Set((entry.ownedRoots ?? []).map((value) => normalizeToken(value)).filter(Boolean)),
    ).filter((value) => {
      const exists = topLevelDirectories.includes(value);
      if (exists) {
        claimedRoots.add(value);
      }
      return exists;
    });
    const ownedDocs = Array.from(
      new Set((entry.ownedDocs ?? []).map((value) => normalizeToken(value)).filter(Boolean)),
    ).filter((value) => {
      const exists = topLevelDocIds.includes(value);
      if (exists) {
        claimedDocs.add(value);
      }
      return exists;
    });

    return {
      key,
      dirName,
      sidebarId,
      label,
      position: typeof entry.position === 'number' && Number.isFinite(entry.position) ? entry.position : (index + 1) * 10,
      docId: landingDoc || undefined,
      description: entry.description?.trim() || undefined,
      ownedRoots,
      ownedDocs,
      catchAll: entry.catchAll === true,
    };
  });

  const workflowDomain = domains.find(
    (domain) => domain.key === 'workflow-standards' || domain.dirName === 'WorkflowStandards',
  );
  if (workflowDomain) {
    for (const directoryName of topLevelDirectories) {
      if (
        STANDARD_DIR_NAMES.has(directoryName.toLowerCase()) &&
        !claimedRoots.has(directoryName) &&
        !workflowDomain.ownedRoots.includes(directoryName)
      ) {
        workflowDomain.ownedRoots.push(directoryName);
        claimedRoots.add(directoryName);
      }
    }
    for (const docId of topLevelDocIds) {
      if (STANDARD_DOC_IDS.has(docId.toLowerCase()) && !claimedDocs.has(docId) && !workflowDomain.ownedDocs.includes(docId)) {
        workflowDomain.ownedDocs.push(docId);
        claimedDocs.add(docId);
      }
    }
  }

  const catchAllDomain = domains.find((domain) => domain.catchAll);
  if (catchAllDomain) {
    for (const directoryName of topLevelDirectories) {
      if (!claimedRoots.has(directoryName) && !catchAllDomain.ownedRoots.includes(directoryName)) {
        catchAllDomain.ownedRoots.push(directoryName);
      }
    }
    for (const docId of topLevelDocIds) {
      if (!claimedDocs.has(docId) && !catchAllDomain.ownedDocs.includes(docId)) {
        catchAllDomain.ownedDocs.push(docId);
      }
    }
  }

  return domains.sort((left, right) => {
    if (left.position !== right.position) {
      return left.position - right.position;
    }
    return left.label.localeCompare(right.label);
  });
}

export function getDocsDomainCatalog(): DocsDomainCatalog {
  if (!fs.existsSync(DOCS_ROOT)) {
    return {domains: [], generalDocs: null};
  }

  const topLevelDirectories = getTopLevelDirectoryNames();
  const topLevelDocIds = getTopLevelMarkdownDocIds();
  const rawConfig = readDomainsConfig();
  const domains = normalizeConfigDomains(rawConfig, topLevelDirectories, topLevelDocIds);

  const enrichedDomains = domains.map((domain) => {
    const domainDirectoryPath = path.join(DOCS_ROOT, domain.dirName);
    const fallbackLabel = fs.existsSync(domainDirectoryPath) ? getDirectoryLabel(domainDirectoryPath, domain.dirName) : domain.label;
    const fallbackDescription = fs.existsSync(domainDirectoryPath) ? getDirectoryDescription(domainDirectoryPath) : '';
    const fallbackPosition = fs.existsSync(domainDirectoryPath) ? getDirectoryPosition(domainDirectoryPath) : domain.position;
    return {
      ...domain,
      label: domain.label || fallbackLabel,
      description: domain.description || fallbackDescription || undefined,
      position: Number.isFinite(domain.position) ? domain.position : fallbackPosition,
      docId: domain.docId && findDocPathFromDocId(domain.docId) ? domain.docId : undefined,
    };
  });

  return {
    domains: enrichedDomains,
    generalDocs: null,
  };
}

export function buildDocsSidebarsConfig(): SidebarsConfig {
  const catalog = getDocsDomainCatalog();
  const sidebars: SidebarsConfig = {};

  for (const domain of catalog.domains) {
    const items: Array<string | {type: 'autogenerated'; dirName: string}> = [];
    for (const docId of domain.ownedDocs) {
      items.push(docId);
    }
    for (const root of domain.ownedRoots) {
      const fullRootPath = path.join(DOCS_ROOT, root);
      if (fs.existsSync(fullRootPath) && fs.statSync(fullRootPath).isDirectory() && directoryHasDocsContent(fullRootPath)) {
        items.push({
          type: 'autogenerated',
          dirName: root,
        });
      }
    }
    if (items.length > 0) {
      sidebars[domain.sidebarId] = items;
    }
  }

  if (Object.keys(sidebars).length === 0) {
    sidebars.docsSidebar = [
      {
        type: 'autogenerated',
        dirName: '.',
      },
    ];
  }

  return sidebars;
}
