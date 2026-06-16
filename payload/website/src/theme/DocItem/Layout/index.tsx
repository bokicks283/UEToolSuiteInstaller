import React, {useCallback, useEffect, useMemo, useRef, useState} from 'react';
import clsx from 'clsx';
import {ThemeClassNames, useWindowSize} from '@docusaurus/theme-common';
import {useDoc} from '@docusaurus/plugin-content-docs/client';
import DocItemPaginator from '@theme/DocItem/Paginator';
import DocVersionBanner from '@theme/DocVersionBanner';
import DocVersionBadge from '@theme/DocVersionBadge';
import DocItemFooter from '@theme/DocItem/Footer';
import TOC from '@theme/TOC';
import DocItemContent from '@theme/DocItem/Content';
import DocBreadcrumbs from '@theme/DocBreadcrumbs';
import ContentVisibility from '@theme/ContentVisibility';
import {EditorContent, NodeViewContent, NodeViewWrapper, ReactNodeViewRenderer, useEditor} from '@tiptap/react';
import StarterKit from '@tiptap/starter-kit';
import {Table} from '@tiptap/extension-table';
import {TableRow} from '@tiptap/extension-table-row';
import {TableCell} from '@tiptap/extension-table-cell';
import {TableHeader} from '@tiptap/extension-table-header';
import {TaskList} from '@tiptap/extension-task-list';
import {TaskItem} from '@tiptap/extension-task-item';
import Underline from '@tiptap/extension-underline';
import TextAlign from '@tiptap/extension-text-align';
import Heading from '@tiptap/extension-heading';
import Paragraph from '@tiptap/extension-paragraph';
import Link from '@tiptap/extension-link';
import Image from '@tiptap/extension-image';
import {Markdown} from '@tiptap/markdown';
import {AllSelection} from '@tiptap/pm/state';
import {Node, mergeAttributes, nodeInputRule, nodePasteRule, type Editor} from '@tiptap/core';
import {icons} from 'lucide';

import authoringStyles from './ueAuthoring.module.css';
import {broadcastDocsStructureChanged, resolveSourceToken, useDocsAuthoringApi, type DocsContentPayload} from '../../authoring/api';
import {
  EMOJI_MAP,
  SHORTCODE_INPUT_REGEX,
  SHORTCODE_PASTE_REGEX,
  SHORTCODE_REGEX,
  parseShortcodeToken,
  toLucideExportName,
  type ShortcodeKind,
  type ShortcodeMatch,
} from '../../authoring/shortcodes';

type DocsContentResponse = {ok: true; content: DocsContentPayload};
type DocsSaveResponse = {ok: true; result: {path: string; hash: string; modifiedUtc: string}};
type DocsVisibilityResponse = {ok: true; result: {path: string; hidden: boolean; hash: string; modifiedUtc: string}};

type FrontMatterSplit = {
  frontMatterBlock: string;
  body: string;
};

type InsertFormMode = 'link' | 'image' | 'code';
type NoteVariant = 'note' | 'info' | 'success' | 'warning' | 'error';
type PickerTab = 'emoji' | 'icon';

type PickerItem = {
  token: string;
  label: string;
};

type TextAlignmentValue = 'left' | 'center' | 'right';

type TocItem = {
  value: string;
  id: string;
  level: number;
  children?: TocItem[];
};

type IconName =
  | 'alignCenter'
  | 'alignLeft'
  | 'alignRight'
  | 'bold'
  | 'bulletList'
  | 'check'
  | 'clear'
  | 'code'
  | 'codeBlock'
  | 'columns'
  | 'deleteColumn'
  | 'deleteRow'
  | 'divider'
  | 'file'
  | 'italic'
  | 'image'
  | 'link'
  | 'listOrdered'
  | 'logOut'
  | 'minusCircle'
  | 'note'
  | 'panelLeft'
  | 'panelRight'
  | 'quote'
  | 'redo'
  | 'rows'
  | 'save'
  | 'sparkles'
  | 'strikethrough'
  | 'table'
  | 'taskList'
  | 'toc'
  | 'tocIgnore'
  | 'trash'
  | 'underline'
  | 'unlink';

const TOC_MARKER = '<!-- docs-tools-toc -->';
const TOC_PLACEHOLDER = '[[docs-tools-toc]]';
const TOC_BLOCK_START = '<!-- docs-tools-toc:start -->';
const TOC_BLOCK_END = '<!-- docs-tools-toc:end -->';
const TOC_IGNORE_METADATA_PATTERN = /^<!--\s*docs-tools-toc-ignore:\s*(.*?)\s*-->$/i;
const ZERO_WIDTH_CHARACTERS = /[\u200B\u200C\u200D\uFEFF]/g;
const ALIGNMENT_PLACEHOLDER_PATTERN = /\[\[ue-docs-align:(left|center|right)\]\]/i;
const ALIGNMENT_PLACEHOLDER_LINE_PATTERN = /^[ \t]*\[\[ue-docs-align:(left|center|right)\]\][ \t]*$/gim;
const ALIGNMENT_COMMENT_PATTERN = /<!--\s*ue-align:(left|center|right)\s*-->/gi;
const LEFT_SIDEBAR_COLLAPSED_KEY = 'ue-docs-left-sidebar-collapsed';
const RIGHT_TOC_COLLAPSED_KEY = 'ue-docs-right-toc-collapsed';
const ADMONITION_TYPES = new Set(['note', 'tip', 'info', 'warning', 'danger', 'caution', 'important']);

type MarkdownJsonNode = {
  type?: string;
  text?: string;
  attrs?: Record<string, unknown>;
  content?: MarkdownJsonNode[];
};

function createAlignmentPlaceholder(alignment: TextAlignmentValue): string {
  return `[[ue-docs-align:${alignment}]]`;
}

function normalizeTextAlignment(value: unknown): TextAlignmentValue | null {
  return value === 'left' || value === 'center' || value === 'right' ? value : null;
}

function parseAlignmentPlaceholder(value: string): TextAlignmentValue | null {
  const match = ALIGNMENT_PLACEHOLDER_PATTERN.exec(value.trim());
  return normalizeTextAlignment(match?.[1] ?? null);
}

function replaceAlignmentCommentsWithPlaceholders(content: string): string {
  return content.replace(ALIGNMENT_COMMENT_PATTERN, (_match, alignment: string) => createAlignmentPlaceholder(alignment as TextAlignmentValue));
}

function replaceAlignmentPlaceholdersWithComments(content: string): string {
  return content.replace(ALIGNMENT_PLACEHOLDER_LINE_PATTERN, (_match, alignment: string) => `<!-- ue-align:${alignment} -->`);
}

function createAlignmentPlaceholderParagraph(alignment: TextAlignmentValue): MarkdownJsonNode {
  return {
    type: 'paragraph',
    content: [{type: 'text', text: createAlignmentPlaceholder(alignment)}],
  };
}

function cloneMarkdownNode(node: MarkdownJsonNode): MarkdownJsonNode {
  return {
    ...node,
    attrs: node.attrs ? {...node.attrs} : undefined,
    content: Array.isArray(node.content) ? node.content.map(cloneMarkdownNode) : undefined,
  };
}

function getAlignmentPlaceholderFromNode(node: MarkdownJsonNode): TextAlignmentValue | null {
  if (node.type !== 'paragraph' || !Array.isArray(node.content) || node.content.length !== 1) {
    return null;
  }
  const textNode = node.content[0];
  if (textNode?.type !== 'text' || typeof textNode.text !== 'string') {
    return null;
  }
  return parseAlignmentPlaceholder(textNode.text);
}

function applyAlignmentPlaceholdersToDoc(node: MarkdownJsonNode): MarkdownJsonNode {
  const cloned = cloneMarkdownNode(node);
  if (!Array.isArray(cloned.content)) {
    return cloned;
  }

  const nextContent: MarkdownJsonNode[] = [];
  let pendingAlignment: TextAlignmentValue | null = null;

  for (const child of cloned.content) {
    const markerAlignment = getAlignmentPlaceholderFromNode(child);
    if (markerAlignment) {
      pendingAlignment = markerAlignment;
      continue;
    }

    const nextChild = applyAlignmentPlaceholdersToDoc(child);
    if (pendingAlignment && (nextChild.type === 'heading' || nextChild.type === 'paragraph')) {
      nextChild.attrs = {...(nextChild.attrs ?? {}), textAlign: pendingAlignment};
      pendingAlignment = null;
    }
    nextContent.push(nextChild);
  }

  cloned.content = nextContent;
  return cloned;
}

function injectAlignmentPlaceholdersIntoDoc(node: MarkdownJsonNode): MarkdownJsonNode {
  const cloned = cloneMarkdownNode(node);
  if (!Array.isArray(cloned.content)) {
    return cloned;
  }

  const nextContent: MarkdownJsonNode[] = [];
  for (const child of cloned.content) {
    const nextChild = injectAlignmentPlaceholdersIntoDoc(child);
    const alignment = normalizeTextAlignment(nextChild.attrs?.textAlign);
    if (alignment && alignment !== 'left' && (nextChild.type === 'heading' || nextChild.type === 'paragraph')) {
      nextContent.push(createAlignmentPlaceholderParagraph(alignment));
    }
    nextContent.push(nextChild);
  }

  cloned.content = nextContent;
  return cloned;
}

function collectMarkdownBlockAlignments(node: MarkdownJsonNode): Array<TextAlignmentValue | null> {
  const alignments: Array<TextAlignmentValue | null> = [];

  const visit = (current: MarkdownJsonNode) => {
    if (current.type === 'heading' || current.type === 'paragraph') {
      alignments.push(normalizeTextAlignment(current.attrs?.textAlign));
    }
    if (Array.isArray(current.content)) {
      current.content.forEach(visit);
    }
  };

  visit(node);
  return alignments;
}

function isHeadingMarkdownLine(line: string): boolean {
  return /^\s*#{1,6}\s+\S/.test(line);
}

function isNonParagraphMarkdownLine(line: string): boolean {
  const trimmed = line.trim();
  return (
    !trimmed ||
    /^<!--/.test(trimmed) ||
    /^(```|~~~)/.test(trimmed) ||
    /^:::+/.test(trimmed) ||
    /^>/.test(trimmed) ||
    /^[-*+]\s+/.test(trimmed) ||
    /^\d+[.)]\s+/.test(trimmed) ||
    /^\|/.test(trimmed) ||
    /^!\[/.test(trimmed) ||
    /^<[^!]/.test(trimmed) ||
    /^(-{3,}|\*{3,}|_{3,})$/.test(trimmed)
  );
}

function collectRenderBlockAlignments(markdown: string): Array<TextAlignmentValue | null> {
  const lines = prepareMarkdownForEditor(markdown).split(/\r?\n/);
  const alignments: Array<TextAlignmentValue | null> = [];
  let pendingAlignment: TextAlignmentValue | null = null;
  let inFence = false;

  for (let index = 0; index < lines.length; index += 1) {
    const trimmed = lines[index].trim();
    const markerMatch = /^<!--\s*ue-align:(left|center|right)\s*-->$/i.exec(trimmed);
    if (markerMatch) {
      pendingAlignment = normalizeTextAlignment(markerMatch[1]);
      continue;
    }

    if (!trimmed) {
      continue;
    }

    if (/^(```|~~~)/.test(trimmed)) {
      inFence = !inFence;
      continue;
    }

    if (inFence) {
      continue;
    }

    if (isHeadingMarkdownLine(trimmed)) {
      alignments.push(pendingAlignment);
      pendingAlignment = null;
      continue;
    }

    if (isNonParagraphMarkdownLine(trimmed)) {
      continue;
    }

    alignments.push(pendingAlignment);
    pendingAlignment = null;

    while (index + 1 < lines.length) {
      const nextTrimmed = lines[index + 1].trim();
      if (!nextTrimmed || isHeadingMarkdownLine(nextTrimmed) || /^<!--\s*ue-align:(left|center|right)\s*-->$/i.test(nextTrimmed) || isNonParagraphMarkdownLine(nextTrimmed)) {
        break;
      }
      index += 1;
    }
  }

  return alignments;
}

function parseEditorMarkdownDocument(editor: Editor, markdown: string): MarkdownJsonNode {
  const markdownEditor = editor as Editor & {
    markdown?: {
      parse: (content: string) => unknown;
    };
  };

  const preparedMarkdown = replaceAlignmentCommentsWithPlaceholders(markdown);
  if (markdownEditor.markdown) {
    return applyAlignmentPlaceholdersToDoc(markdownEditor.markdown.parse(preparedMarkdown) as MarkdownJsonNode);
  }

  return {type: 'doc', content: []};
}

function hasExistingTocMarker(content: string): boolean {
  return /<!--\s*docs-tools-toc:start\s*-->|<!--\s*docs-tools-toc\s*-->|\[\[docs-tools-toc\]\]/i.test(content || '');
}

function stripEditorOnlyTocMarkers(content: string): string {
  return content
    .replace(/<!--\s*docs-tools-toc:start\s*-->[\s\S]*?<!--\s*docs-tools-toc:end\s*-->/gi, '')
    .replace(/^\s*(?:<!--\s*docs-tools-toc\s*-->|\[\[docs-tools-toc\]\])\s*$/gim, '')
    .replace(/\s*<!--\s*toc-ignore\s*-->/gi, '')
    .replace(ZERO_WIDTH_CHARACTERS, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function normalizeTocLabel(value: string): string {
  return stripHeadingMarkdown(value.replace(ZERO_WIDTH_CHARACTERS, '').replace(/\s+/g, ' '));
}

function cleanTocIgnoreMetadataLabel(value: string): string {
  return value.replace(/-->/g, '').trim();
}

function getTocIgnoreMetadataLines(ignoredHeadingLabels: Set<string>): string[] {
  return Array.from(ignoredHeadingLabels)
    .map(cleanTocIgnoreMetadataLabel)
    .filter(Boolean)
    .sort((left, right) => left.localeCompare(right))
    .map((label) => `<!-- docs-tools-toc-ignore: ${label} -->`);
}

function filterIgnoredTocItems(items: TocItem[], ignoredHeadingLabels: Set<string>): TocItem[] {
  if (ignoredHeadingLabels.size === 0) {
    return items;
  }

  return items
    .map((item) => ({
      ...item,
      children: item.children ? filterIgnoredTocItems(item.children, ignoredHeadingLabels) : undefined,
    }))
    .filter((item) => !ignoredHeadingLabels.has(normalizeTocLabel(item.value)));
}

const DEFAULT_MERMAID_SOURCE = 'graph TD\n  A[Start] --> B[Next Step]';
const CODE_LANGUAGE_OPTIONS = [
  '',
  'bash',
  'powershell',
  'json',
  'yaml',
  'typescript',
  'javascript',
  'csharp',
  'cpp',
  'python',
  'sql',
  'md',
  'xml',
];
const EMOJI_ITEMS: PickerItem[] = [
  {token: ':rocket:', label: 'Rocket'},
  {token: ':white_check_mark:', label: 'Check'},
  {token: ':warning:', label: 'Warning'},
  {token: ':x:', label: 'Error'},
  {token: ':bulb:', label: 'Idea'},
  {token: ':memo:', label: 'Memo'},
  {token: ':gear:', label: 'Settings'},
  {token: ':bookmark:', label: 'Bookmark'},
  {token: ':chart_with_upwards_trend:', label: 'Chart up'},
  {token: ':wrench:', label: 'Wrench'},
];
const ICON_ITEMS: PickerItem[] = [
  {token: ':icon[rocket]:', label: 'Rocket'},
  {token: ':icon[book-open]:', label: 'Book open'},
  {token: ':icon[circle-check-big]:', label: 'Check circle'},
  {token: ':icon[triangle-alert]:', label: 'Alert'},
  {token: ':icon[bug]:', label: 'Bug'},
  {token: ':icon[flask-conical]:', label: 'Lab'},
  {token: ':icon[terminal]:', label: 'Terminal'},
  {token: ':icon[link]:', label: 'Link'},
  {token: ':icon[image]:', label: 'Image'},
  {token: ':icon[table]:', label: 'Table'},
];

function escapeMarkdownLinkText(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/\]/g, '\\]');
}

function escapeMarkdownTitle(value: string): string {
  return value.replace(/\\/g, '\\\\').replace(/"/g, '\\"');
}

function getAdmonitionLabel(kind: string): string {
  switch (kind) {
    case 'tip':
      return 'Tip';
    case 'info':
      return 'Info';
    case 'warning':
      return 'Warning';
    case 'danger':
      return 'Danger';
    case 'caution':
      return 'Caution';
    case 'important':
      return 'Important';
    case 'note':
    default:
      return 'Note';
  }
}

function mapNoteVariantToAdmonitionKind(variant: NoteVariant): string {
  switch (variant) {
    case 'info':
      return 'info';
    case 'success':
      return 'tip';
    case 'warning':
      return 'warning';
    case 'error':
      return 'danger';
    case 'note':
    default:
      return 'note';
  }
}

function stripHeadingMarkdown(value: string): string {
  return value
    .replace(/`([^`]+)`/g, '$1')
    .replace(/\*\*([^*]+)\*\*/g, '$1')
    .replace(/\*([^*]+)\*/g, '$1')
    .replace(/\[([^\]]+)\]\([^)]+\)/g, '$1')
    .replace(/<[^>]+>/g, '')
    .trim();
}

function slugifyHeading(value: string): string {
  return value
    .toLowerCase()
    .replace(/&[a-z]+;/g, '')
    .replace(/[^\w\s-]/g, '')
    .trim()
    .replace(/[\s_-]+/g, '-')
    .replace(/^-+|-+$/g, '');
}

function collectTocIgnoredHeadingLabels(body: string): Set<string> {
  const labels = new Set<string>();
  const lines = body.split(/\r?\n/);
  let insideFence = false;
  lines.forEach((rawLine) => {
    const trimmedLine = rawLine.trim();
    if (/^(```|~~~)/.test(trimmedLine)) {
      insideFence = !insideFence;
      return;
    }
    if (insideFence) {
      return;
    }
    const metadataMatch = TOC_IGNORE_METADATA_PATTERN.exec(trimmedLine);
    if (metadataMatch) {
      const label = cleanTocIgnoreMetadataLabel(metadataMatch[1]);
      if (label) {
        labels.add(label);
      }
      return;
    }
    if (!/<!--\s*toc-ignore\s*-->/i.test(rawLine)) {
      return;
    }
    const match = /^(#{1,6})\s+(.+?)\s*$/.exec(rawLine);
    if (!match) {
      return;
    }
    const label = stripHeadingMarkdown(match[2].replace(/\s*<!--\s*toc-ignore\s*-->\s*$/i, ''));
    if (label) {
      labels.add(label);
    }
  });
  return labels;
}

function restoreTocIgnoreMarkers(body: string, ignoredHeadingLabels: Set<string>): string {
  const cleanedBody = body
    .split(/\r?\n/)
    .map((rawLine) => {
      const match = /^(#{1,6})\s+(.+?)\s*$/.exec(rawLine);
      if (!match) {
        return rawLine;
      }
      return rawLine.replace(/\s*<!--\s*toc-ignore\s*-->/gi, '');
    })
    .join('\n')
    .replace(/^\s*<!--\s*docs-tools-toc-ignore:\s*.*?-->\s*$/gim, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();

  return cleanedBody;
}

function generateMarkdownTocFromBody(body: string, ignoredHeadingLabels: Set<string> = new Set()): string[] {
  const lines = body.split(/\r?\n/);
  const headings: Array<{depth: number; label: string}> = [];
  let insideGeneratedToc = false;
  let insideFence = false;
  for (let i = 0; i < lines.length; i += 1) {
    const rawLine = lines[i];
    const trimmedLine = rawLine.trim();
    if (/^<!--\s*docs-tools-toc:start\s*-->$/i.test(trimmedLine)) {
      insideGeneratedToc = true;
      continue;
    }
    if (/^<!--\s*docs-tools-toc:end\s*-->$/i.test(trimmedLine)) {
      insideGeneratedToc = false;
      continue;
    }
    if (trimmedLine === TOC_PLACEHOLDER || /^<!--\s*docs-tools-toc\s*-->$/i.test(trimmedLine)) {
      continue;
    }
    if (/^(```|~~~)/.test(trimmedLine)) {
      insideFence = !insideFence;
      continue;
    }
    if (insideGeneratedToc || insideFence) {
      continue;
    }

    const match = /^(#{1,6})\s+(.+?)\s*$/.exec(rawLine);
    if (!match) {
      continue;
    }
    if (match[1].length < 2) {
      continue;
    }
    const label = stripHeadingMarkdown(match[2].replace(/\s*<!--\s*toc-ignore\s*-->\s*$/i, ''));
    if (/<!--\s*toc-ignore\s*-->/i.test(rawLine) || ignoredHeadingLabels.has(label)) {
      continue;
    }
    const anchor = slugifyHeading(label);
    if (!label || !anchor) {
      continue;
    }
    headings.push({
      depth: match[1].length,
      label,
    });
  }

  if (headings.length === 0) {
    return [];
  }

  const minDepth = Math.min(...headings.map((heading) => heading.depth));
  return headings.map((heading) => {
    const indent = '  '.repeat(Math.max(0, heading.depth - minDepth));
    const anchor = slugifyHeading(heading.label);
    return `${indent}- [${heading.label}](#${anchor})`;
  });
}

const DocusaurusAdmonition = Node.create({
  name: 'docusaurusAdmonition',
  group: 'block',
  content: 'block+',
  defining: true,

  addAttributes() {
    return {
      kind: {
        default: 'note',
        parseHTML: (element) => element.getAttribute('data-ue-admonition') || 'note',
        renderHTML: () => ({}),
      },
      title: {
        default: '',
        parseHTML: (element) => element.getAttribute('data-ue-admonition-title') || '',
        renderHTML: () => ({}),
      },
    };
  },

  parseHTML() {
    return [{tag: 'aside[data-ue-admonition]'}];
  },

  renderHTML({node, HTMLAttributes}) {
    const kind = ADMONITION_TYPES.has(String(node.attrs.kind)) ? String(node.attrs.kind) : 'note';
    const title = String(node.attrs.title || '');
    return [
      'aside',
      mergeAttributes(HTMLAttributes, {
        class: authoringStyles.admonitionPanel,
        'data-ue-admonition': kind,
        'data-ue-admonition-title': title || getAdmonitionLabel(kind),
      }),
      0,
    ];
  },

  addNodeView() {
    return ReactNodeViewRenderer(AdmonitionNodeView);
  },

  markdownTokenName: 'docusaurusAdmonition',

  markdownTokenizer: {
    name: 'docusaurusAdmonition',
    level: 'block' as const,
    start(src: string) {
      const match = src.match(/^:::(note|tip|info|warning|danger|caution|important)\b/im);
      return match?.index ?? -1;
    },
    tokenize(src: string, _tokens: unknown, lexer: {blockTokens: (value: string) => unknown[]; inlineTokens: (value: string) => unknown[]}) {
      const openingMatch = src.match(/^:::(note|tip|info|warning|danger|caution|important)(?:[^\S\r\n]+([^\n]+))?\s*\n/i);
      if (!openingMatch) {
        return undefined;
      }

      const openingTag = openingMatch[0];
      const kind = openingMatch[1].toLowerCase();
      const title = (openingMatch[2] || '').trim();
      const remaining = src.slice(openingTag.length);
      const closeMatch = remaining.match(/(?:^|\n):::\s*(?:\n|$)/);
      if (!closeMatch || closeMatch.index === undefined) {
        return undefined;
      }

      const closeStart = closeMatch.index + (closeMatch[0].startsWith('\n') ? 1 : 0);
      const closeEnd = closeMatch.index + closeMatch[0].length;
      const rawContent = remaining.slice(0, closeStart);
      const fullMatch = src.slice(0, openingTag.length + closeEnd);
      const contentTokens = lexer.blockTokens(rawContent.trim());
      contentTokens.forEach((token: {text?: string; tokens?: unknown[]}) => {
        if (token.text && (!token.tokens || token.tokens.length === 0)) {
          token.tokens = lexer.inlineTokens(token.text);
        }
      });

      return {
        type: 'docusaurusAdmonition',
        raw: fullMatch,
        attributes: {kind, title},
        tokens: contentTokens,
      };
    },
  },

  parseMarkdown(token: {attributes?: {kind?: string; title?: string}; tokens?: unknown[]}, helpers: {parseChildren: (tokens: unknown[]) => unknown[]; createNode: (type: string, attrs?: unknown, content?: unknown[]) => unknown}) {
    const kind = ADMONITION_TYPES.has(String(token.attributes?.kind)) ? String(token.attributes?.kind) : 'note';
    const title = String(token.attributes?.title || '');
    return helpers.createNode('docusaurusAdmonition', {kind, title}, helpers.parseChildren(token.tokens || []));
  },

  renderMarkdown(node: {attrs?: {kind?: string; title?: string}; content?: unknown[]}, helpers: {renderChildren: (nodes: unknown[] | undefined, separator?: string) => string}) {
    const kind = ADMONITION_TYPES.has(String(node.attrs?.kind)) ? String(node.attrs?.kind) : 'note';
    const title = String(node.attrs?.title || '').trim();
    const renderedContent = helpers.renderChildren(node.content || [], '\n\n').trim();
    const titleSuffix = title ? ` ${title}` : '';
    return `:::${kind}${titleSuffix}\n\n${renderedContent}\n\n:::`;
  },
});

const DocsImage = Image.extend({
  markdownTokenName: 'image',

  parseMarkdown(token: {href?: string; text?: string; title?: string}, helpers: {createNode: (type: string, attrs?: unknown) => unknown}) {
    return helpers.createNode('image', {
      src: String(token.href || ''),
      alt: String(token.text || ''),
      title: token.title ? String(token.title) : null,
    });
  },

  renderMarkdown(node: {attrs?: {src?: string; alt?: string; title?: string}}) {
    const src = String(node.attrs?.src || '').trim();
    const alt = escapeMarkdownLinkText(String(node.attrs?.alt || ''));
    const title = String(node.attrs?.title || '').trim();
    return title ? `![${alt}](${src} "${escapeMarkdownTitle(title)}")` : `![${alt}](${src})`;
  },
});

function AdmonitionNodeView({
  node,
}: {
  node: {attrs: {kind?: string; title?: string}; nodeSize: number};
}): React.ReactElement {
  const kind = ADMONITION_TYPES.has(String(node.attrs.kind)) ? String(node.attrs.kind) : 'note';
  const title = String(node.attrs.title || getAdmonitionLabel(kind));

  return (
    <NodeViewWrapper
      as="aside"
      className={authoringStyles.admonitionPanel}
      data-ue-admonition={kind}
      data-ue-admonition-title={title}
    >
      <NodeViewContent as="div" className={authoringStyles.admonitionContent} />
    </NodeViewWrapper>
  );
}

function MermaidNodeView({
  node,
  updateAttributes,
}: {
  node: {attrs: {code?: string; collapsed?: boolean}};
  updateAttributes: (attrs: {code?: string; collapsed?: boolean}) => void;
}): React.ReactElement {
  const code = String(node.attrs.code || '').trimEnd();
  const collapsed = Boolean(node.attrs.collapsed ?? false);
  const [svg, setSvg] = useState('');
  const [error, setError] = useState('');
  const diagramId = useMemo(() => `ue-mermaid-${Math.random().toString(36).slice(2)}`, []);

  useEffect(() => {
    let cancelled = false;
    async function renderDiagram() {
      if (!code.trim()) {
        setSvg('');
        setError('');
        return;
      }

      try {
        const mermaid = (await import('mermaid')).default;
        mermaid.initialize({
          startOnLoad: false,
          securityLevel: 'strict',
          theme: document.documentElement.dataset.theme === 'dark' ? 'dark' : 'default',
        });
        const result = await mermaid.render(`${diagramId}-${Date.now()}`, code);
        if (!cancelled) {
          setSvg(result.svg);
          setError('');
        }
      } catch (renderError) {
        if (!cancelled) {
          setSvg('');
          setError(renderError instanceof Error ? renderError.message : 'Unable to render Mermaid diagram.');
        }
      }
    }

    void renderDiagram();
    return () => {
      cancelled = true;
    };
  }, [code, diagramId]);

  return (
    <NodeViewWrapper as="figure" className={authoringStyles.mermaidPanel} data-ue-mermaid="true">
      <div className={authoringStyles.mermaidPreview} aria-label="Mermaid diagram preview">
        <div className={authoringStyles.mermaidActions}>
          <button
            type="button"
            className={authoringStyles.mermaidActionButton}
            onMouseDown={(event) => {
              event.preventDefault();
              event.stopPropagation();
            }}
            onClick={(event) => {
              event.preventDefault();
              event.stopPropagation();
              updateAttributes({collapsed: !collapsed});
            }}
            aria-label={collapsed ? 'Edit Mermaid source' : 'Collapse Mermaid source'}
            title={collapsed ? 'Edit Mermaid source' : 'Collapse Mermaid source'}
          >
            {collapsed ? 'Edit' : 'Done'}
          </button>
        </div>
        {svg ? <div className={authoringStyles.mermaidSvg} dangerouslySetInnerHTML={{__html: svg}} /> : null}
        {!svg && !error ? <p className={authoringStyles.mermaidStatus}>Rendering diagram...</p> : null}
        {error ? <p className={authoringStyles.mermaidError}>{error}</p> : null}
      </div>
      {!collapsed ? (
        <textarea
          className={authoringStyles.mermaidSource}
          value={code}
          onMouseDown={(event) => event.stopPropagation()}
          onChange={(event) => updateAttributes({code: event.target.value})}
          aria-label="Mermaid source"
          spellCheck={false}
        />
      ) : null}
    </NodeViewWrapper>
  );
}

const DocusaurusMermaid = Node.create({
  name: 'docusaurusMermaid',
  group: 'block',
  atom: true,
  selectable: true,
  draggable: false,

  addAttributes() {
    return {
      code: {
        default: DEFAULT_MERMAID_SOURCE,
        parseHTML: (element) => element.getAttribute('data-ue-mermaid-source') || element.textContent || DEFAULT_MERMAID_SOURCE,
        renderHTML: (attrs) => ({
          'data-ue-mermaid-source': String(attrs.code || ''),
        }),
      },
      collapsed: {
        default: false,
        parseHTML: (element) => element.getAttribute('data-ue-mermaid-collapsed') === 'true',
        renderHTML: (attrs) => ({
          'data-ue-mermaid-collapsed': attrs.collapsed ? 'true' : 'false',
        }),
      },
    };
  },

  parseHTML() {
    return [{tag: 'figure[data-ue-mermaid]'}];
  },

  renderHTML({HTMLAttributes}) {
    return ['figure', mergeAttributes(HTMLAttributes, {class: authoringStyles.mermaidPanel, 'data-ue-mermaid': 'true'})];
  },

  addNodeView() {
    return ReactNodeViewRenderer(MermaidNodeView);
  },

  markdownTokenName: 'code',

  parseMarkdown(token: {lang?: string; text?: string}, helpers: {createNode: (type: string, attrs?: unknown) => unknown}) {
    if (String(token.lang || '').trim().toLowerCase() !== 'mermaid') {
      return [];
    }

    return helpers.createNode('docusaurusMermaid', {
      code: String(token.text || '').trimEnd(),
      collapsed: true,
    });
  },

  renderMarkdown(node: {attrs?: {code?: string}}) {
    const code = String(node.attrs?.code || '').trimEnd();
    return `\`\`\`mermaid\n${code}\n\`\`\``;
  },
});

const DocusaurusShortcode = Node.create({
  name: 'docusaurusShortcode',
  group: 'inline',
  inline: true,
  atom: true,
  selectable: true,

  addAttributes() {
    return {
      kind: {
        default: 'emoji',
      },
      name: {
        default: '',
      },
      token: {
        default: '',
      },
    };
  },

  parseHTML() {
    return [{tag: 'span[data-ue-shortcode-token]'}];
  },

  renderHTML({node, HTMLAttributes}) {
    return [
      'span',
      mergeAttributes(HTMLAttributes, {
        'data-ue-shortcode': String(node.attrs.kind || ''),
        'data-ue-shortcode-token': String(node.attrs.token || ''),
      }),
      String(node.attrs.token || ''),
    ];
  },

  addNodeView() {
    return ReactNodeViewRenderer(ShortcodeNodeView);
  },

  addInputRules() {
    return [
      nodeInputRule({
        find: SHORTCODE_INPUT_REGEX,
        type: this.type,
        getAttributes: (match) => getShortcodeNodeAttrs(match[0]) || false,
      }),
    ];
  },

  addPasteRules() {
    return [
      nodePasteRule({
        find: SHORTCODE_PASTE_REGEX,
        type: this.type,
        getAttributes: (match) => getShortcodeNodeAttrs(match[0]) || false,
      }),
    ];
  },

  markdownTokenizer: {
    name: 'docusaurusShortcode',
    level: 'inline' as const,
    start(src: string) {
      return src.search(SHORTCODE_REGEX);
    },
    tokenize(src: string) {
      SHORTCODE_REGEX.lastIndex = 0;
      const match = SHORTCODE_REGEX.exec(src);
      if (!match || match.index !== 0) {
        return undefined;
      }

      const parsed = parseShortcodeToken(match[0]);
      if (!parsed) {
        return undefined;
      }

      return {
        type: 'docusaurusShortcode',
        raw: parsed.token,
        kind: parsed.kind,
        name: parsed.name,
        token: parsed.token,
      };
    },
  },

  parseMarkdown(
    token: {kind?: ShortcodeKind; name?: string; token?: string; raw?: string},
    helpers: {createNode: (type: string, attrs?: unknown) => unknown},
  ) {
    const attrs = getShortcodeNodeAttrs(String(token.token || token.raw || ''));
    if (!attrs) {
      return [];
    }
    return helpers.createNode('docusaurusShortcode', attrs);
  },

  renderMarkdown(node: {attrs?: {token?: string}}) {
    return String(node.attrs?.token || '');
  },
});

const DocusaurusTocMarker = Node.create({
  name: 'docusaurusTocMarker',
  group: 'block',
  atom: true,
  selectable: true,

  parseHTML() {
    return [{tag: 'div[data-ue-toc-marker]'}];
  },

  renderHTML({HTMLAttributes}) {
    return ['div', mergeAttributes(HTMLAttributes, {'data-ue-toc-marker': 'true'}), TOC_PLACEHOLDER];
  },

  addNodeView() {
    return ReactNodeViewRenderer(TocMarkerNodeView);
  },

  markdownTokenizer: {
    name: 'docusaurusTocMarker',
    level: 'block' as const,
    start(src: string) {
      return src.indexOf(TOC_PLACEHOLDER);
    },
    tokenize(src: string) {
      if (!src.startsWith(TOC_PLACEHOLDER)) {
        return undefined;
      }

      const trailingNewline = src.charAt(TOC_PLACEHOLDER.length) === '\n' ? '\n' : '';
      return {
        type: 'docusaurusTocMarker',
        raw: `${TOC_PLACEHOLDER}${trailingNewline}`,
        token: TOC_PLACEHOLDER,
      };
    },
  },

  parseMarkdown(_token: {token?: string}, helpers: {createNode: (type: string, attrs?: unknown) => unknown}) {
    return helpers.createNode('docusaurusTocMarker');
  },

  renderMarkdown() {
    return TOC_PLACEHOLDER;
  },
});

function prepareMarkdownForEditor(content: string): string {
  return content
    .replace(/<i\b[^>]*data-lucide=["']([a-z0-9-]+)["'][^>]*><\/i>/gi, ':icon[$1]:')
    .replace(/<u>([\s\S]*?)<\/u>/gi, '++$1++')
    .replace(/<!--\s*docs-tools-toc:start\s*-->[\s\S]*?<!--\s*docs-tools-toc:end\s*-->/gi, TOC_PLACEHOLDER)
    .replaceAll(TOC_MARKER, TOC_PLACEHOLDER)
    .replace(/\s*<!--\s*toc-ignore\s*-->/gi, '')
    .replace(ZERO_WIDTH_CHARACTERS, '')
    .replace(/\n{3,}/g, '\n\n')
    .trim();
}

function insertGeneratedTocBlock(content: string, ignoredHeadingLabels: Set<string>): string {
  const tocLines = generateMarkdownTocFromBody(content, ignoredHeadingLabels);
  const ignoreMetadataLines = getTocIgnoreMetadataLines(ignoredHeadingLabels);
  const generatedBlock = [
    TOC_BLOCK_START,
    ...ignoreMetadataLines,
    ...(tocLines.length === 0 ? ['- _No headings available yet._'] : tocLines),
    TOC_BLOCK_END,
  ];
  const lines = content.split(/\r?\n/);
  const firstH1Index = lines.findIndex((line) => /^#\s+/.test(line.trim()));
  if (firstH1Index < 0) {
    return [...generatedBlock, '', ...lines].join('\n');
  }

  const nextLines = [...lines];
  let insertIndex = firstH1Index + 1;
  while (insertIndex < nextLines.length && nextLines[insertIndex].trim() === '') {
    insertIndex += 1;
  }
  nextLines.splice(insertIndex, 0, '', ...generatedBlock, '');
  return nextLines.join('\n').replace(/\n{4,}/g, '\n\n\n');
}

function prepareMarkdownForSave(content: string, ignoredHeadingLabels: Set<string> = new Set(), shouldGenerateToc = false): string {
  const normalized = content
    .replace(/<!--\s*docs-tools-toc:start\s*-->[\s\S]*?<!--\s*docs-tools-toc:end\s*-->/g, TOC_PLACEHOLDER)
    .replaceAll(TOC_MARKER, TOC_PLACEHOLDER);
  const lines = normalized.split(/\r?\n/);
  const output: string[] = [];
  let renderedPlaceholder = false;

  for (let i = 0; i < lines.length; i += 1) {
    const line = lines[i];
    if (line.trim() !== TOC_PLACEHOLDER) {
      output.push(line);
      continue;
    }

    const tocLines = generateMarkdownTocFromBody(normalized, ignoredHeadingLabels);
    const ignoreMetadataLines = getTocIgnoreMetadataLines(ignoredHeadingLabels);
    output.push(TOC_BLOCK_START);
    output.push(...ignoreMetadataLines);
    if (tocLines.length === 0) {
      output.push('- _No headings available yet._');
    } else {
      output.push(...tocLines);
    }
    output.push(TOC_BLOCK_END);
    renderedPlaceholder = true;
  }

  const markdown = output.join('\n');
  if (!shouldGenerateToc || renderedPlaceholder || hasExistingTocMarker(markdown)) {
    return markdown;
  }

  return insertGeneratedTocBlock(markdown, ignoredHeadingLabels);
}

function testAdvancedMdx(content: string): boolean {
  if (!content) {
    return false;
  }
  if (/(^|\n)\s*(import|export)\s+/m.test(content)) {
    return true;
  }
  return /(^|\n)\s*<([A-Z][A-Za-z0-9]*|Tabs|TabItem|details|summary|Mermaid)\b/m.test(content);
}

function setEditorMarkdown(editor: Editor, markdown: string): void {
  const markdownEditor = editor as Editor & {
    markdown?: {
      parse: (content: string) => unknown;
    };
  };
  if (markdownEditor.markdown) {
    editor.commands.setContent(parseEditorMarkdownDocument(editor, markdown) as never, {emitUpdate: false} as never);
    return;
  }
  editor.commands.setContent(markdown, {contentType: 'markdown', emitUpdate: false} as never);
}

function getEditorMarkdown(editor: Editor): string {
  const markdownEditor = editor as Editor & {
    getMarkdown?: () => string;
    markdown?: {
      serialize: (content: unknown) => string;
    };
  };
  const docWithAlignmentMarkers = injectAlignmentPlaceholdersIntoDoc(editor.getJSON() as MarkdownJsonNode);
  if (markdownEditor.markdown) {
    return replaceAlignmentPlaceholdersWithComments(markdownEditor.markdown.serialize(docWithAlignmentMarkers))
      .replace(/\+\+([\s\S]*?)\+\+/g, '<u>$1</u>')
      .replace(/:icon\[([a-z0-9-]+)\]:/gi, '<i data-lucide="$1" className="ue-inline-icon"></i>');
  }
  const markdownFn = markdownEditor.getMarkdown;
  if (typeof markdownFn === 'function') {
    return replaceAlignmentPlaceholdersWithComments(markdownFn.call(editor))
      .replace(/\+\+([\s\S]*?)\+\+/g, '<u>$1</u>')
      .replace(/:icon\[([a-z0-9-]+)\]:/gi, '<i data-lucide="$1" className="ue-inline-icon"></i>');
  }
  return '';
}

function insertTextAtSelection(editor: Editor, text: string): void {
  editor.chain().focus().insertContent(text).run();
}

function splitFrontMatter(content: string): FrontMatterSplit {
  const match = /^(---\r?\n[\s\S]*?\r?\n---)(?:\r?\n)?([\s\S]*)$/.exec(content);
  if (!match) {
    return {
      frontMatterBlock: '',
      body: content,
    };
  }

  return {
    frontMatterBlock: match[1],
    body: match[2] ?? '',
  };
}

function joinFrontMatter(frontMatterBlock: string, body: string): string {
  const trimmedFrontMatter = (frontMatterBlock || '').trim();
  if (!trimmedFrontMatter) {
    return body;
  }

  const normalizedBody = body ?? '';
  if (!normalizedBody.length) {
    return `${trimmedFrontMatter}\n`;
  }

  return `${trimmedFrontMatter}\n\n${normalizedBody}`;
}

function frontMatterHasBoolean(frontMatterBlock: string, key: string): boolean {
  if (!frontMatterBlock.trim()) {
    return false;
  }
  const pattern = new RegExp(`^\\s*${key}\\s*:\\s*(true|false)\\s*$`, 'im');
  const match = frontMatterBlock.match(pattern);
  return (match?.[1] ?? '').toLowerCase() === 'true';
}

function setFrontMatterBoolean(frontMatterBlock: string, key: string, value: boolean): string {
  const trimmed = frontMatterBlock.trim();
  const keyPattern = new RegExp(`^\\s*${key}\\s*:\\s*.+(?:\\r?\\n)?`, 'im');

  if (!trimmed) {
    return value ? `---\n${key}: true\n---` : '';
  }

  const lines = trimmed.split(/\r?\n/);
  if (lines[0] !== '---' || lines[lines.length - 1] !== '---') {
    return frontMatterBlock;
  }

  const bodyLines = lines.slice(1, -1).filter((line) => !keyPattern.test(`${line}\n`));
  if (value) {
    bodyLines.push(`${key}: true`);
  }

  if (bodyLines.length === 0) {
    return '';
  }

  return ['---', ...bodyLines, '---'].join('\n');
}

function getDraftStorageKey(sourceToken: string): string {
  return `ue-docs-editor-draft:${sourceToken}`;
}

function hasLevelOneHeading(content: string): boolean {
  return /^\s*#\s+\S/m.test(content || '');
}

function getHeadingLabelAtSelection(editor: Editor): string | null {
  const {$from} = editor.state.selection;
  for (let depth = $from.depth; depth >= 0; depth -= 1) {
    const node = $from.node(depth);
    if (node.type.name === 'heading') {
      const label = stripHeadingMarkdown(node.textContent || '');
      return label || null;
    }
  }
  return null;
}

type ShortcodeNodeAttrs = {
  kind: ShortcodeKind;
  name: string;
  token: string;
};

type LucideIconNode = Array<[keyof React.JSX.IntrinsicElements, Record<string, string>]>;

function getShortcodeNodeAttrs(token: string): ShortcodeNodeAttrs | null {
  const match = parseShortcodeToken(token);
  if (!match) {
    return null;
  }

  return {
    kind: match.kind,
    name: match.name,
    token: match.token,
  };
}

function renderLucideShortcodeIcon(name: string, className: string): React.ReactElement | null {
  const iconKey = toLucideExportName(name);
  const iconNode = (icons as Record<string, unknown>)[iconKey] as LucideIconNode | undefined;
  if (!Array.isArray(iconNode)) {
    return null;
  }

  return (
    <svg className={className} viewBox="0 0 24 24" aria-hidden="true" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
      {iconNode.map(([tagName, attrs], index) => React.createElement(tagName, {key: `${name}-${index}`, ...attrs}))}
    </svg>
  );
}

function ShortcodeVisual({
  token,
  className,
  iconClassName,
  fallbackToToken = true,
}: {
  token: string;
  className?: string;
  iconClassName?: string;
  fallbackToToken?: boolean;
}): React.ReactElement {
  const match = parseShortcodeToken(token);
  if (!match) {
    return <span className={className}>{fallbackToToken ? token : ''}</span>;
  }

  if (match.kind === 'emoji') {
    return <span className={className}>{EMOJI_MAP[match.name] || (fallbackToToken ? token : '')}</span>;
  }

  const icon = renderLucideShortcodeIcon(match.name, iconClassName || authoringStyles.shortcodeIconSvg);
  if (icon) {
    return <span className={className}>{icon}</span>;
  }

  return <span className={className}>{fallbackToToken ? token : ''}</span>;
}

function ShortcodeNodeView({
  node,
}: {
  node: {attrs: {kind?: ShortcodeKind; name?: string; token?: string}};
}): React.ReactElement {
  const token = String(node.attrs.token || '');
  return (
    <NodeViewWrapper
      as="span"
      className={authoringStyles.shortcodeNode}
      data-ue-shortcode={node.attrs.kind || ''}
      data-ue-shortcode-token={token}
      contentEditable={false}
    >
      <ShortcodeVisual token={token} className={authoringStyles.shortcodeVisual} />
    </NodeViewWrapper>
  );
}

function TocMarkerNodeView({
  deleteNode,
}: {
  deleteNode: () => void;
}): React.ReactElement {
  return (
    <NodeViewWrapper as="div" className={authoringStyles.tocMarkerNode} data-ue-toc-marker="true">
      <div className={authoringStyles.tocMarkerCard}>
        <div>
          <p className={authoringStyles.tocMarkerTitle}>Table of Contents</p>
          <p className={authoringStyles.tocMarkerText}>This marker renders the generated TOC here.</p>
        </div>
        <button
          type="button"
          className={authoringStyles.tocMarkerRemoveButton}
          onMouseDown={(event) => event.preventDefault()}
          onClick={() => deleteNode()}
        >
          Remove
        </button>
      </div>
    </NodeViewWrapper>
  );
}

function ToolbarIcon({name}: {name: IconName}): React.ReactElement {
  const common = {
    className: authoringStyles.toolbarIcon,
    viewBox: '0 0 24 24',
    'aria-hidden': true,
  };
  switch (name) {
    case 'alignCenter':
      return <svg {...common}><path d="M8 6h8M5 10h14M8 14h8M5 18h14" /></svg>;
    case 'alignLeft':
      return <svg {...common}><path d="M4 6h16M4 10h10M4 14h16M4 18h10" /></svg>;
    case 'alignRight':
      return <svg {...common}><path d="M4 6h16M10 10h10M4 14h16M10 18h10" /></svg>;
    case 'bold':
      return <svg {...common}><path d="M7 5h6a3 3 0 0 1 0 6H7zM7 11h7a4 4 0 0 1 0 8H7z" /></svg>;
    case 'bulletList':
      return <svg {...common}><path d="M9 6h11M9 12h11M9 18h11" /><circle cx="4" cy="6" r="1" /><circle cx="4" cy="12" r="1" /><circle cx="4" cy="18" r="1" /></svg>;
    case 'check':
      return <svg {...common}><path d="M20 6 9 17l-5-5" /></svg>;
    case 'clear':
      return <svg {...common}><path d="M4 7h16M9 7V4h6v3M8 11l8 8M16 11l-8 8" /></svg>;
    case 'code':
      return <svg {...common}><path d="m8 9-4 3 4 3M16 9l4 3-4 3M14 5l-4 14" /></svg>;
    case 'codeBlock':
      return <svg {...common}><path d="M5 4h14a2 2 0 0 1 2 2v12a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V6a2 2 0 0 1 2-2z" /><path d="m9 10-2 2 2 2M15 10l2 2-2 2" /></svg>;
    case 'columns':
      return <svg {...common}><path d="M12 3v18M5 5h14v14H5z" /></svg>;
    case 'deleteColumn':
      return <svg {...common}><path d="M12 3v18M5 5h14v14H5zM8 8l8 8M16 8l-8 8" /></svg>;
    case 'deleteRow':
      return <svg {...common}><path d="M5 12h14M5 5h14v14H5zM8 8l8 8M16 8l-8 8" /></svg>;
    case 'divider':
      return <svg {...common}><path d="M4 12h16" /></svg>;
    case 'file':
      return <svg {...common}><path d="M14 2H6a2 2 0 0 0-2 2v16a2 2 0 0 0 2 2h12a2 2 0 0 0 2-2V8z" /><path d="M14 2v6h6" /></svg>;
    case 'italic':
      return <svg {...common}><path d="M10 5h8M6 19h8M14 5l-4 14" /></svg>;
    case 'image':
      return <svg {...common}><path d="M5 3h14a2 2 0 0 1 2 2v14a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2z" /><circle cx="8.5" cy="8.5" r="1.5" /><path d="m21 15-5-5L5 21" /></svg>;
    case 'link':
      return <svg {...common}><path d="M10 13a5 5 0 0 0 7.1 0l2-2a5 5 0 0 0-7.1-7.1l-1.1 1.1" /><path d="M14 11a5 5 0 0 0-7.1 0l-2 2A5 5 0 0 0 12 20.1l1.1-1.1" /></svg>;
    case 'listOrdered':
      return <svg {...common}><path d="M10 6h10M10 12h10M10 18h10M4 6h1v4M4 10h2M4 14h2l-2 4h2" /></svg>;
    case 'logOut':
      return <svg {...common}><path d="M9 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h4M16 17l5-5-5-5M21 12H9" /></svg>;
    case 'minusCircle':
      return <svg {...common}><circle cx="12" cy="12" r="9" /><path d="M8 12h8" /></svg>;
    case 'note':
      return <svg {...common}><path d="M4 4h16v14H7l-3 3z" /><path d="M8 9h8M8 13h6" /></svg>;
    case 'panelLeft':
      return <svg {...common}><path d="M4 5h16v14H4zM9 5v14M6.5 9l-2 3 2 3" /></svg>;
    case 'panelRight':
      return <svg {...common}><path d="M4 5h16v14H4zM15 5v14M17.5 9l2 3-2 3" /></svg>;
    case 'quote':
      return <svg {...common}><path d="M8 21a4 4 0 0 0 4-4v-5H6V7a2 2 0 0 1 2-2M18 21a4 4 0 0 0 4-4v-5h-6V7a2 2 0 0 1 2-2" /></svg>;
    case 'redo':
      return <svg {...common}><path d="M21 7v6h-6" /><path d="M3 17a9 9 0 0 1 15-6l3 2" /></svg>;
    case 'rows':
      return <svg {...common}><path d="M5 12h14M5 5h14v14H5z" /></svg>;
    case 'save':
      return <svg {...common}><path d="M19 21H5a2 2 0 0 1-2-2V5a2 2 0 0 1 2-2h11l5 5v11a2 2 0 0 1-2 2z" /><path d="M17 21v-8H7v8M7 3v5h8" /></svg>;
    case 'sparkles':
      return <svg {...common}><path d="M12 3l1.6 4.4L18 9l-4.4 1.6L12 15l-1.6-4.4L6 9l4.4-1.6zM19 14l.8 2.2L22 17l-2.2.8L19 20l-.8-2.2L16 17l2.2-.8zM5 14l.8 2.2L8 17l-2.2.8L5 20l-.8-2.2L2 17l2.2-.8z" /></svg>;
    case 'strikethrough':
      return <svg {...common}><path d="M5 12h14M16 6.5A4 4 0 0 0 12.5 5H11a3 3 0 0 0-3 3c0 2 2 3 4 3h1M8 17.5A5 5 0 0 0 12 19h1a3 3 0 0 0 3-3" /></svg>;
    case 'table':
      return <svg {...common}><path d="M4 5h16v14H4zM4 10h16M9 5v14M15 5v14" /></svg>;
    case 'taskList':
      return <svg {...common}><path d="m4 7 2 2 4-4M13 7h7M4 17h6M13 17h7" /><path d="M4 14h6v6H4z" /></svg>;
    case 'toc':
      return <svg {...common}><path d="M4 6h16M4 12h10M4 18h16" /></svg>;
    case 'tocIgnore':
      return <svg {...common}><path d="M4 6h16M4 12h10M4 18h16" /><path d="M16 16l4 4M20 16l-4 4" /></svg>;
    case 'trash':
      return <svg {...common}><path d="M4 7h16M9 7V4h6v3M8 11v7M12 11v7M16 11v7" /></svg>;
    case 'underline':
      return <svg {...common}><path d="M7 5v6a5 5 0 0 0 10 0V5M5 21h14" /></svg>;
    case 'unlink':
      return <svg {...common}><path d="M10 13a5 5 0 0 0 7.1 0l1-1M14 11a5 5 0 0 0-7.1 0l-1 1M4 4l16 16" /></svg>;
    default:
      return <svg {...common}><circle cx="12" cy="12" r="9" /></svg>;
  }
}

function IconButton({
  active,
  children,
  disabled,
  icon,
  label,
  onClick,
}: {
  active?: boolean;
  children?: React.ReactNode;
  disabled?: boolean;
  icon?: IconName;
  label: string;
  onClick: () => void;
}): React.ReactElement {
  return (
    <button
      type="button"
      className={clsx(authoringStyles.toolbarButton, active && authoringStyles.activeButton)}
      onPointerDown={(event) => event.preventDefault()}
      onMouseDown={(event) => event.preventDefault()}
      onClick={onClick}
      disabled={disabled}
      aria-label={label}
      title={label}
    >
      {icon ? <ToolbarIcon name={icon} /> : null}
      {children ? <span className={authoringStyles.toolbarText}>{children}</span> : null}
    </button>
  );
}

function useDocTOC(ignoredHeadingLabels: Set<string>) {
  const {frontMatter, toc} = useDoc();
  const hidden = frontMatter.hide_table_of_contents;
  const filteredToc = filterIgnoredTocItems(toc as TocItem[], ignoredHeadingLabels);
  const canRender = !hidden && filteredToc.length > 0;
  const desktop =
    canRender ? (
      <TOC
        toc={filteredToc}
        minHeadingLevel={frontMatter.toc_min_heading_level}
        maxHeadingLevel={frontMatter.toc_max_heading_level}
        className={ThemeClassNames.docs.docTocDesktop}
      />
    ) : undefined;
  return {
    hidden,
    desktop,
  };
}

export default function DocItemLayout({children}: {children: React.ReactNode}): React.ReactElement {
  const [renderIgnoredHeadingLabels, setRenderIgnoredHeadingLabels] = useState<Set<string>>(new Set());
  const docTOC = useDocTOC(renderIgnoredHeadingLabels);
  const {metadata} = useDoc();
  const {requestJson, runtimeAvailable, runtimeReady} = useDocsAuthoringApi();
  const authoringAvailable = runtimeReady && runtimeAvailable;
  const windowSize = useWindowSize();
  const metadataTitle = useMemo(() => (typeof metadata.title === 'string' ? metadata.title.trim() : ''), [metadata.title]);

  const sourceToken = useMemo(() => resolveSourceToken(metadata.source ?? ''), [metadata.source]);
  const pageIsEditable = sourceToken.toLowerCase().endsWith('.md');
  const pageCanManageVisibility = authoringAvailable && !sourceToken.toLowerCase().endsWith('/_category_.json') && !!sourceToken;
  const [leftSidebarCollapsed, setLeftSidebarCollapsed] = useState(() => {
    if (typeof window === 'undefined') {
      return false;
    }
    return window.localStorage.getItem(LEFT_SIDEBAR_COLLAPSED_KEY) === 'true';
  });
  const [rightTocCollapsed, setRightTocCollapsed] = useState(() => {
    if (typeof window === 'undefined') {
      return false;
    }
    const storedRightToc = window.localStorage.getItem(RIGHT_TOC_COLLAPSED_KEY);
    return storedRightToc === null ? window.innerWidth < 2200 : storedRightToc === 'true';
  });
  const [viewportWidth, setViewportWidth] = useState(() => (typeof window === 'undefined' ? 0 : window.innerWidth));
  const [layoutViewportShift, setLayoutViewportShift] = useState(0);
  const [tocAutoVisible, setTocAutoVisible] = useState(true);
  const [tocAutoHideVersion, setTocAutoHideVersion] = useState(0);
  const [tocScrollbarVisible, setTocScrollbarVisible] = useState(false);
  const [tocScrollbarThumb, setTocScrollbarThumb] = useState({height: 0, offset: 0});
  const [tocFixedLayout, setTocFixedLayout] = useState({top: 0, right: 0, height: 0});
  const layoutShellRef = useRef<HTMLDivElement | null>(null);
  const tocRailRef = useRef<HTMLDivElement | null>(null);
  const tocColumnRef = useRef<HTMLDivElement | null>(null);
  const tocScrollbarTimerRef = useRef<number | null>(null);
  const tocAutoHideTimerRef = useRef<number | null>(null);
  const scrollbarRevealTimerRef = useRef<number | null>(null);
  const tocActiveSyncFrameRef = useRef<number | null>(null);
  const tocActiveSyncLastKeyRef = useRef<string | null>(null);
  const tocHoveredRef = useRef(false);
  const narrowDesktopSingleRail = viewportWidth > 996 && viewportWidth <= 1100;

  useEffect(() => {
    if (typeof document === 'undefined' || typeof window === 'undefined') {
      return undefined;
    }

    document.documentElement.dataset.ueDocsUiReady = 'false';
    let cancelled = false;
    let secondFrame = 0;
    const firstFrame = window.requestAnimationFrame(() => {
      secondFrame = window.requestAnimationFrame(() => {
        if (cancelled) {
          return;
        }
        document.documentElement.dataset.ueDocsUiReady = 'true';
      });
    });

    return () => {
      cancelled = true;
      window.cancelAnimationFrame(firstFrame);
      if (secondFrame) {
        window.cancelAnimationFrame(secondFrame);
      }
    };
  }, []);

  useEffect(() => {
    if (typeof window === 'undefined') {
      return undefined;
    }

    const updateViewportWidth = () => setViewportWidth(window.innerWidth);
    updateViewportWidth();
    window.addEventListener('resize', updateViewportWidth);
    return () => {
      window.removeEventListener('resize', updateViewportWidth);
    };
  }, []);

  useEffect(() => {
    if (typeof document === 'undefined') {
      return;
    }

    document.documentElement.dataset.ueDocsLeftSidebarCollapsed = leftSidebarCollapsed ? 'true' : 'false';
    if (typeof window !== 'undefined') {
      window.localStorage.setItem(LEFT_SIDEBAR_COLLAPSED_KEY, leftSidebarCollapsed ? 'true' : 'false');
    }
  }, [leftSidebarCollapsed]);

  useEffect(() => {
    if (typeof window === 'undefined') {
      return;
    }
    window.localStorage.setItem(RIGHT_TOC_COLLAPSED_KEY, rightTocCollapsed ? 'true' : 'false');
  }, [rightTocCollapsed]);

  useEffect(() => {
    if (!narrowDesktopSingleRail) {
      return;
    }
    if (!leftSidebarCollapsed && !rightTocCollapsed) {
      setRightTocCollapsed(true);
    }
  }, [leftSidebarCollapsed, narrowDesktopSingleRail, rightTocCollapsed]);

  useEffect(() => {
    const shell = layoutShellRef.current;
    if (!shell || typeof window === 'undefined') {
      return undefined;
    }

    const updateShift = () => {
      const rect = shell.getBoundingClientRect();
      const shellCenter = rect.left + rect.width / 2;
      const sidebar = document.querySelector<HTMLElement>('.theme-doc-sidebar-container');
      const sidebarVisible = sidebar && window.getComputedStyle(sidebar).display !== 'none';
      const availableLeft = sidebarVisible ? sidebar.getBoundingClientRect().right : 0;
      const desiredCenter = availableLeft + (window.innerWidth - availableLeft) / 2;
      setLayoutViewportShift(desiredCenter - shellCenter);
    };

    updateShift();
    const resizeObserver = new ResizeObserver(() => updateShift());
    resizeObserver.observe(shell);
    window.addEventListener('resize', updateShift);
    return () => {
      resizeObserver.disconnect();
      window.removeEventListener('resize', updateShift);
    };
  }, [leftSidebarCollapsed, rightTocCollapsed]);

  useEffect(() => {
    setRenderIgnoredHeadingLabels(new Set());
    setRenderSourceBody('');
    if (!pageIsEditable || !authoringAvailable) {
      return undefined;
    }

    let cancelled = false;
    void requestJson<DocsContentResponse>(`/api/content?path=${encodeURIComponent(sourceToken)}`)
      .then((payload) => {
        if (!cancelled) {
          const {body} = splitFrontMatter(payload.content.content);
          setRenderSourceBody(body);
          setRenderIgnoredHeadingLabels(collectTocIgnoredHeadingLabels(body));
        }
      })
      .catch(() => {
        // Keep the static Docusaurus TOC if the local authoring API is unavailable.
      });

    return () => {
      cancelled = true;
    };
  }, [authoringAvailable, pageIsEditable, requestJson, sourceToken]);

  const [editMode, setEditMode] = useState(false);
  const [loading, setLoading] = useState(false);
  const [saving, setSaving] = useState(false);
  const [deleting, setDeleting] = useState(false);
  const [statusText, setStatusText] = useState('');
  const [errorText, setErrorText] = useState('');
  const [loadedContent, setLoadedContent] = useState<DocsContentPayload | null>(null);
  const [frontMatterBlock, setFrontMatterBlock] = useState('');
  const [originalSource, setOriginalSource] = useState('');
  const [renderSourceBody, setRenderSourceBody] = useState('');
  const [sourceDraft, setSourceDraft] = useState('');
  const [isDirty, setIsDirty] = useState(false);
  const [advancedMdx, setAdvancedMdx] = useState(false);
  const [richEditorUnavailable, setRichEditorUnavailable] = useState(false);
  const [autoEditApplied, setAutoEditApplied] = useState(false);
  const [editorRevision, setEditorRevision] = useState(0);
  const [editorContentRevision, setEditorContentRevision] = useState(0);
  const [insertFormMode, setInsertFormMode] = useState<InsertFormMode | null>(null);
  const [linkText, setLinkText] = useState('');
  const [linkHref, setLinkHref] = useState('');
  const [imageAlt, setImageAlt] = useState('');
  const [imageSrc, setImageSrc] = useState('');
  const [codeLanguage, setCodeLanguage] = useState('');
  const [insertFormPosition, setInsertFormPosition] = useState<{left: number; top: number} | null>(null);
  const [deleteDialogOpen, setDeleteDialogOpen] = useState(false);
  const [noteMenuOpen, setNoteMenuOpen] = useState(false);
  const [pickerOpen, setPickerOpen] = useState(false);
  const [pickerTab, setPickerTab] = useState<PickerTab>('emoji');
  const [pickerQuery, setPickerQuery] = useState('');
  const editorShellRef = useRef<HTMLDivElement | null>(null);
  const suppressEditorUpdateRef = useRef(false);
  const sourceDraftRef = useRef('');
  const loadedHashRef = useRef('');
  const tocIgnoredHeadingLabelsRef = useRef<Set<string>>(new Set());
  const tocMarkerEnabledRef = useRef(false);
  const pageHiddenFromSite = useMemo(() => frontMatterHasBoolean(frontMatterBlock, 'unlisted'), [frontMatterBlock]);

  useEffect(() => {
    loadedHashRef.current = loadedContent?.hash ?? '';
  }, [loadedContent]);

  const editor = useEditor({
    extensions: [
      DocusaurusMermaid,
      StarterKit.configure({
        heading: false,
        link: false,
        paragraph: false,
        underline: false,
      }),
      Heading.configure({
        levels: [1, 2, 3, 4],
      }),
      Paragraph,
      DocusaurusAdmonition,
      Table.configure({resizable: true}),
      TableRow,
      TableHeader,
      TableCell,
      TaskList,
      TaskItem.configure({nested: true}),
      Underline,
      TextAlign.configure({
        types: ['heading', 'paragraph'],
      }),
      DocusaurusTocMarker,
      DocusaurusShortcode,
      Link.configure({
        autolink: true,
        linkOnPaste: true,
        openOnClick: false,
      }),
      DocsImage.configure({
        allowBase64: true,
        inline: false,
      }),
      Markdown.configure({}),
    ],
    content: '',
    editable: false,
    immediatelyRender: false,
    editorProps: {
      attributes: {
        class: clsx('markdown', authoringStyles.inlineEditorContent),
      },
    },
    onUpdate: ({editor: activeEditor}) => {
      if (suppressEditorUpdateRef.current) {
        return;
      }
      const nextMarkdown = getEditorMarkdown(activeEditor);
      sourceDraftRef.current = nextMarkdown;
      tocMarkerEnabledRef.current = hasExistingTocMarker(nextMarkdown);
      setSourceDraft(nextMarkdown);
      setIsDirty(true);
      setEditorRevision((value) => value + 1);
      if (typeof window !== 'undefined' && pageIsEditable) {
        try {
          window.localStorage.setItem(
            getDraftStorageKey(sourceToken),
            JSON.stringify({
              body: nextMarkdown,
              hash: loadedHashRef.current,
              tocIgnoredHeadingLabels: Array.from(tocIgnoredHeadingLabelsRef.current),
              tocMarkerEnabled: tocMarkerEnabledRef.current,
              savedAt: new Date().toISOString(),
            }),
          );
        } catch {
          // Ignore storage write failures.
        }
      }
    },
    onSelectionUpdate: () => {
      setEditorRevision((value) => value + 1);
    },
  });

  const applyEditorMarkdown = useCallback((targetEditor: Editor, markdown: string) => {
    suppressEditorUpdateRef.current = true;
    sourceDraftRef.current = markdown;
    try {
      setEditorMarkdown(targetEditor, markdown);
    } finally {
      globalThis.setTimeout(() => {
        suppressEditorUpdateRef.current = false;
      }, 0);
    }
  }, []);

  useEffect(() => {
    if (!editor) {
      return;
    }
    editor.setEditable(editMode && !saving && !deleting && !advancedMdx && !richEditorUnavailable);
  }, [advancedMdx, deleting, editMode, editor, richEditorUnavailable, saving]);

  useEffect(() => {
    if (!editor || !editMode || advancedMdx || !loadedContent) {
      return;
    }
    const rawMarkdown = sourceDraftRef.current;
    if (getEditorMarkdown(editor).trim() === rawMarkdown.trim()) {
      return;
    }
    const editorBody = prepareMarkdownForEditor(rawMarkdown);
    applyEditorMarkdown(editor, editorBody);
    globalThis.setTimeout(() => {
      const hydratedMarkdown = getEditorMarkdown(editor).trim();
      const hydratedText = editor.view.dom.textContent?.trim() ?? '';
      if ((!hydratedMarkdown || !hydratedText) && rawMarkdown.trim()) {
        setRichEditorUnavailable(true);
      }
    }, 150);
  }, [advancedMdx, applyEditorMarkdown, editMode, editor, editorContentRevision, loadedContent]);

  useEffect(() => {
    if (typeof window === 'undefined' || !editMode || !pageIsEditable) {
      return;
    }

    const draftKey = getDraftStorageKey(sourceToken);
    if (!isDirty) {
      window.localStorage.removeItem(draftKey);
      return;
    }

    const draftBody = advancedMdx
      ? sourceDraft
      : (editor ? getEditorMarkdown(editor) : sourceDraft);
    try {
      window.localStorage.setItem(
        draftKey,
        JSON.stringify({
          body: draftBody,
          hash: loadedHashRef.current,
          tocIgnoredHeadingLabels: Array.from(tocIgnoredHeadingLabelsRef.current),
          tocMarkerEnabled: tocMarkerEnabledRef.current,
          savedAt: new Date().toISOString(),
        }),
      );
    } catch {
      // Ignore storage write failures.
    }
  }, [advancedMdx, editMode, editor, editorRevision, isDirty, pageIsEditable, sourceDraft, sourceToken]);

  const loadCurrentPage = useCallback(async () => {
    if (!pageIsEditable) {
      return;
    }
      setLoading(true);
      setErrorText('');
      setRichEditorUnavailable(false);
    try {
      const payload = await requestJson<DocsContentResponse>(`/api/content?path=${encodeURIComponent(sourceToken)}`);
      setLoadedContent(payload.content);
      const split = splitFrontMatter(payload.content.content);
      setFrontMatterBlock(split.frontMatterBlock);
      setOriginalSource(split.body);

      let nextDraftBody = split.body;
      let nextIgnoredHeadingLabels = collectTocIgnoredHeadingLabels(split.body);
      let nextTocMarkerEnabled = hasExistingTocMarker(split.body);
      if (typeof window !== 'undefined') {
        try {
          const storedDraftRaw = window.localStorage.getItem(getDraftStorageKey(sourceToken));
          if (storedDraftRaw) {
            const storedDraft = JSON.parse(storedDraftRaw) as {
              body?: string;
              hash?: string;
              savedAt?: string;
              tocIgnoredHeadingLabels?: string[];
              tocMarkerEnabled?: boolean;
            };
            if (typeof storedDraft.body === 'string' && storedDraft.hash === payload.content.hash && storedDraft.body !== split.body) {
              nextDraftBody = storedDraft.body;
              nextIgnoredHeadingLabels = collectTocIgnoredHeadingLabels(storedDraft.body);
              nextTocMarkerEnabled = hasExistingTocMarker(storedDraft.body);
              if (Array.isArray(storedDraft.tocIgnoredHeadingLabels)) {
                nextIgnoredHeadingLabels = new Set([
                  ...Array.from(nextIgnoredHeadingLabels),
                  ...storedDraft.tocIgnoredHeadingLabels,
                ]);
              }
              if (typeof storedDraft.tocMarkerEnabled === 'boolean') {
                nextTocMarkerEnabled = storedDraft.tocMarkerEnabled || nextTocMarkerEnabled;
              }
              setStatusText('Recovered an unsaved local draft.');
            }
          }
        } catch {
          // Ignore malformed draft cache payloads.
        }
      }
      sourceDraftRef.current = nextDraftBody;
      tocIgnoredHeadingLabelsRef.current = nextIgnoredHeadingLabels;
      tocMarkerEnabledRef.current = nextTocMarkerEnabled;
      setRenderSourceBody(nextDraftBody);
      setRenderIgnoredHeadingLabels(nextIgnoredHeadingLabels);
      setSourceDraft(nextDraftBody);
      setEditorContentRevision((value) => value + 1);

      const hasAdvancedMdx = testAdvancedMdx(split.body);
      setAdvancedMdx(hasAdvancedMdx);
      if (!hasAdvancedMdx && editor) {
        const editorBody = prepareMarkdownForEditor(nextDraftBody);
        applyEditorMarkdown(editor, editorBody);
        globalThis.setTimeout(() => {
          const hydratedMarkdown = getEditorMarkdown(editor).trim();
          const hydratedText = editor.view.dom.textContent?.trim() ?? '';
          if ((!hydratedMarkdown || !hydratedText) && editorBody.trim()) {
            setRichEditorUnavailable(true);
          }
        }, 150);
      }
      setIsDirty(nextDraftBody !== split.body);
      if (nextDraftBody === split.body) {
        setStatusText(`Loaded ${payload.content.path}`);
      }
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Failed to load page for editing.');
    } finally {
      setLoading(false);
    }
  }, [editor, pageIsEditable, requestJson, sourceToken]);

  const enterEditMode = useCallback(async () => {
    if (!authoringAvailable) {
      return;
    }
    setEditMode(true);
    await loadCurrentPage();
  }, [authoringAvailable, loadCurrentPage]);

  const discardChanges = useCallback(() => {
    if (!loadedContent) {
      setEditMode(false);
      setIsDirty(false);
      return;
    }
    sourceDraftRef.current = originalSource;
    tocIgnoredHeadingLabelsRef.current = collectTocIgnoredHeadingLabels(originalSource);
    tocMarkerEnabledRef.current = hasExistingTocMarker(originalSource);
    setRenderSourceBody(originalSource);
    setRenderIgnoredHeadingLabels(tocIgnoredHeadingLabelsRef.current);
    setSourceDraft(originalSource);
    setEditorContentRevision((value) => value + 1);
    if (editor && !advancedMdx && !richEditorUnavailable) {
      applyEditorMarkdown(editor, prepareMarkdownForEditor(originalSource));
    }
    if (typeof window !== 'undefined') {
      window.localStorage.removeItem(getDraftStorageKey(sourceToken));
    }
    setIsDirty(false);
    setStatusText('Changes discarded.');
  }, [advancedMdx, editor, loadedContent, originalSource, richEditorUnavailable, sourceToken]);

  const saveChanges = useCallback(async () => {
    if (!loadedContent) {
      return;
    }
    const currentDraft = sourceDraftRef.current;
    const editableBody = richEditorUnavailable ? currentDraft : (editor ? (getEditorMarkdown(editor) || currentDraft) : currentDraft);
    const effectiveIgnoredHeadingLabels = new Set<string>([
      ...renderIgnoredHeadingLabels,
      ...tocIgnoredHeadingLabelsRef.current,
      ...collectTocIgnoredHeadingLabels(currentDraft),
    ]);
    const markdownBody = advancedMdx
      ? currentDraft
      : prepareMarkdownForSave(
          restoreTocIgnoreMarkers(editableBody, effectiveIgnoredHeadingLabels),
          effectiveIgnoredHeadingLabels,
          tocMarkerEnabledRef.current,
        );
    const markdown = joinFrontMatter(frontMatterBlock, markdownBody);
    setSaving(true);
    setErrorText('');
    try {
      const payload = await requestJson<DocsSaveResponse>('/api/content', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          path: sourceToken,
          content: markdown,
          expectedHash: loadedContent.hash,
        }),
      });
      const updated: DocsContentPayload = {
        path: payload.result.path,
        content: markdown,
        hash: payload.result.hash,
        modifiedUtc: payload.result.modifiedUtc,
      };
      setLoadedContent(updated);
      setOriginalSource(markdownBody);
      sourceDraftRef.current = markdownBody;
      tocIgnoredHeadingLabelsRef.current = collectTocIgnoredHeadingLabels(markdownBody);
      tocMarkerEnabledRef.current = hasExistingTocMarker(markdownBody);
      setRenderSourceBody(markdownBody);
      setRenderIgnoredHeadingLabels(tocIgnoredHeadingLabelsRef.current);
      setSourceDraft(markdownBody);
      setEditorContentRevision((value) => value + 1);
      if (editor && !advancedMdx && !richEditorUnavailable) {
        applyEditorMarkdown(editor, prepareMarkdownForEditor(markdownBody));
      }
      if (typeof window !== 'undefined') {
        window.localStorage.removeItem(getDraftStorageKey(sourceToken));
      }
      setIsDirty(false);
      setStatusText(`Saved ${updated.path}`);
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Save failed.');
    } finally {
      setSaving(false);
    }
  }, [advancedMdx, editor, frontMatterBlock, loadedContent, renderIgnoredHeadingLabels, requestJson, richEditorUnavailable, sourceToken]);

  const insertMarkdownAtEnd = useCallback(
    (snippet: string) => {
      if (advancedMdx) {
        setSourceDraft((previous) => {
          const next = previous ? `${previous.trimEnd()}\n\n${snippet}\n` : `${snippet}\n`;
          sourceDraftRef.current = next;
          tocIgnoredHeadingLabelsRef.current = collectTocIgnoredHeadingLabels(next);
          tocMarkerEnabledRef.current = hasExistingTocMarker(next);
          setIsDirty(next !== originalSource);
          return next;
        });
        return;
      }

      if (!editor) {
        return;
      }
      const current = getEditorMarkdown(editor);
      const next = current ? `${current.trimEnd()}\n\n${snippet}\n` : `${snippet}\n`;
      setEditorMarkdown(editor, next);
      setIsDirty(true);
      setStatusText('Inserted snippet.');
    },
    [advancedMdx, editor, originalSource],
  );

  const runEditorCommand = useCallback(
    (command: (activeEditor: Editor) => void) => {
      if (!editor || advancedMdx || saving || loading || deleting) {
        return;
      }
      const firstChild = editor.state.doc.firstChild;
      const docIsSingleEmptyParagraph =
        editor.state.doc.childCount === 1
        && firstChild?.type.name === 'paragraph'
        && firstChild.content.size === 0;
      if (docIsSingleEmptyParagraph && editor.state.selection instanceof AllSelection) {
        editor.commands.setTextSelection(1);
        editor.commands.focus();
      }
      command(editor);
      setIsDirty(true);
      setEditorRevision((value) => value + 1);
    },
    [advancedMdx, deleting, editor, loading, saving],
  );

  const getCursorPanelPosition = useCallback((): {left: number; top: number} => {
    if (!editor) {
      return {left: 12, top: 12};
    }

    const shellRect = editorShellRef.current?.getBoundingClientRect();
    const position = editor.view.coordsAtPos(editor.state.selection.from);
    if (shellRect) {
      return {
        left: Math.max(8, position.left - shellRect.left),
        top: Math.max(8, position.bottom - shellRect.top + 8),
      };
    }

    return {left: 12, top: 12};
  }, [editor]);

  const toggleNoteMenu = useCallback(() => {
    if (!editor || advancedMdx || saving || loading || deleting) {
      return;
    }
    setInsertFormMode(null);
    setPickerOpen(false);
    setNoteMenuOpen((current) => {
      if (!current) {
        setInsertFormPosition(getCursorPanelPosition());
      } else {
        setInsertFormPosition(null);
      }
      return !current;
    });
  }, [advancedMdx, deleting, editor, getCursorPanelPosition, loading, saving]);

  const ensureParagraphAfterTable = useCallback((activeEditor: Editor): boolean => {
    if (!activeEditor.isActive('table')) {
      return false;
    }

    const {$from} = activeEditor.state.selection;
    for (let depth = $from.depth; depth >= 0; depth -= 1) {
      const node = $from.node(depth);
      if (node.type.name !== 'table') {
        continue;
      }
      const after = $from.after(depth);
      activeEditor.chain().focus().insertContentAt(after, {type: 'paragraph'}).setTextSelection(after + 1).run();
      return true;
    }

    return false;
  }, []);

  const togglePickerMenu = useCallback(() => {
    if (!editor || advancedMdx || saving || loading || deleting) {
      return;
    }
    setInsertFormMode(null);
    setNoteMenuOpen(false);
    setPickerOpen((current) => {
      if (!current) {
        setPickerTab('emoji');
        setPickerQuery('');
        setInsertFormPosition(getCursorPanelPosition());
      } else {
        setInsertFormPosition(null);
      }
      return !current;
    });
  }, [advancedMdx, deleting, editor, getCursorPanelPosition, loading, saving]);

  const openInsertForm = useCallback(
    (mode: InsertFormMode) => {
      if (!editor || advancedMdx || saving || loading || deleting) {
        return;
      }

      if (mode === 'link') {
        const {from, to} = editor.state.selection;
        const selectedText = editor.state.doc.textBetween(from, to, ' ').trim();
        setLinkText(selectedText);
        setLinkHref(String(editor.getAttributes('link').href || ''));
      } else if (mode === 'image') {
        setImageAlt('');
        setImageSrc('');
      } else {
        setCodeLanguage(String(editor.getAttributes('codeBlock').language || ''));
      }

      setInsertFormPosition(getCursorPanelPosition());
      setNoteMenuOpen(false);
      setPickerOpen(false);
      setInsertFormMode((current) => (current === mode ? null : mode));
    },
    [advancedMdx, deleting, editor, getCursorPanelPosition, loading, saving],
  );

  const submitLink = useCallback(() => {
    if (!editor || advancedMdx || saving || loading || deleting) {
      return;
    }

    const href = linkHref.trim();
    const text = linkText.trim() || href;
    if (!href || !text) {
      return;
    }

    const firstChild = editor.state.doc.firstChild;
    const docIsSingleEmptyParagraph =
      editor.state.doc.childCount === 1
      && firstChild?.type.name === 'paragraph'
      && firstChild.content.size === 0;
    if (docIsSingleEmptyParagraph && editor.state.selection instanceof AllSelection) {
      editor.commands.setTextSelection(1);
      editor.commands.focus();
    }

    const {from, to, empty} = editor.state.selection;
    const selectedText = editor.state.doc.textBetween(from, to, ' ').trim();
    const clearStoredLinkMark = (position: number) => {
      const linkMark = editor.state.schema.marks.link;
      editor.commands.setTextSelection(position);
      if (!linkMark) {
        return;
      }
      const transaction = editor.state.tr.removeStoredMark(linkMark);
      editor.view.dispatch(transaction);
    };
    if (empty) {
      editor.chain().focus().insertContent({
        type: 'text',
        text,
        marks: [{type: 'link', attrs: {href}}],
      }).run();
      clearStoredLinkMark(from + text.length);
    } else if (selectedText === text) {
      editor.chain().focus().extendMarkRange('link').setLink({href}).run();
      clearStoredLinkMark(to);
    } else {
      editor.chain().focus().insertContentAt({from, to}, {
        type: 'text',
        text,
        marks: [{type: 'link', attrs: {href}}],
      }).run();
      clearStoredLinkMark(from + text.length);
    }

    setLinkText('');
    setLinkHref('');
    setInsertFormMode(null);
    setInsertFormPosition(null);
    setNoteMenuOpen(false);
    setPickerOpen(false);
    setIsDirty(true);
    setEditorRevision((value) => value + 1);
  }, [advancedMdx, deleting, editor, linkHref, linkText, loading, saving]);

  const submitImage = useCallback(() => {
    if (!editor || advancedMdx || saving || loading || deleting) {
      return;
    }

    const src = imageSrc.trim();
    if (!src) {
      return;
    }

    ensureParagraphAfterTable(editor);
    editor.chain().focus().setImage({src, alt: imageAlt.trim()}).createParagraphNear().run();
    setImageAlt('');
    setImageSrc('');
    setInsertFormMode(null);
    setInsertFormPosition(null);
    setNoteMenuOpen(false);
    setPickerOpen(false);
    setIsDirty(true);
    setEditorRevision((value) => value + 1);
  }, [advancedMdx, deleting, editor, ensureParagraphAfterTable, imageAlt, imageSrc, loading, saving]);

  const submitCodeLanguage = useCallback(() => {
    if (!editor || advancedMdx || saving || loading || deleting) {
      return;
    }

    const language = codeLanguage.trim();
    editor.chain().focus().setCodeBlock(language ? {language} : undefined).run();
    setInsertFormMode(null);
    setInsertFormPosition(null);
    setNoteMenuOpen(false);
    setPickerOpen(false);
    setIsDirty(true);
    setEditorRevision((value) => value + 1);
  }, [advancedMdx, codeLanguage, deleting, editor, loading, saving]);

  const insertPickerToken = useCallback((token: string) => {
    if (advancedMdx) {
      insertMarkdownAtEnd(token);
      setInsertFormPosition(null);
      setNoteMenuOpen(false);
      setPickerOpen(false);
      return;
    }
    if (!editor || saving || loading || deleting) {
      return;
    }
    ensureParagraphAfterTable(editor);
    const shortcodeAttrs = getShortcodeNodeAttrs(token);
    if (shortcodeAttrs) {
      editor.chain().focus().insertContent({type: 'docusaurusShortcode', attrs: shortcodeAttrs}).run();
    } else {
      insertTextAtSelection(editor, token);
    }
    setInsertFormPosition(null);
    setNoteMenuOpen(false);
    setPickerOpen(false);
    setIsDirty(true);
    setEditorRevision((value) => value + 1);
  }, [advancedMdx, deleting, editor, ensureParagraphAfterTable, insertMarkdownAtEnd, loading, saving]);

  const insertTocMarker = useCallback(() => {
    const currentMarkdown = advancedMdx
      ? sourceDraft
      : (editor ? getEditorMarkdown(editor) : '');
    if (tocMarkerEnabledRef.current || hasExistingTocMarker(currentMarkdown)) {
      setStatusText('TOC marker already exists.');
      return;
    }

    if (advancedMdx) {
      insertMarkdownAtEnd(TOC_MARKER);
      setStatusText('Inserted TOC marker.');
      return;
    }
    runEditorCommand((activeEditor) => {
      ensureParagraphAfterTable(activeEditor);
      activeEditor.chain().focus().insertContent({type: 'docusaurusTocMarker'}).run();
    });
    setStatusText('Inserted TOC marker.');
  }, [advancedMdx, editor, ensureParagraphAfterTable, insertMarkdownAtEnd, runEditorCommand, sourceDraft]);

  const insertTocIgnoreMarker = useCallback(() => {
    if (advancedMdx) {
      insertMarkdownAtEnd('<!-- toc-ignore -->');
      return;
    }
    runEditorCommand((activeEditor) => {
      const headingLabel = getHeadingLabelAtSelection(activeEditor) || '';
      if (!headingLabel) {
        setStatusText('Place the cursor in a heading to change its TOC state.');
        return;
      }

      const nextIgnoredLabels = new Set(tocIgnoredHeadingLabelsRef.current);
      const nextIgnored = !nextIgnoredLabels.has(headingLabel);
      if (nextIgnored) {
        nextIgnoredLabels.add(headingLabel);
      } else {
        nextIgnoredLabels.delete(headingLabel);
      }
      tocIgnoredHeadingLabelsRef.current = nextIgnoredLabels;
      setRenderIgnoredHeadingLabels(new Set(nextIgnoredLabels));
      setIsDirty(true);
      setEditorRevision((value) => value + 1);
      setStatusText(nextIgnored ? `Ignoring heading in TOC: ${headingLabel}` : `Including heading in TOC: ${headingLabel}`);
    });
  }, [advancedMdx, insertMarkdownAtEnd, runEditorCommand]);

  const insertNote = useCallback((variant: NoteVariant = 'note') => {
    const kind = mapNoteVariantToAdmonitionKind(variant);
    const label = getAdmonitionLabel(kind);
    const placeholderText = `Enter ${label.toLowerCase()} details.`;
    if (advancedMdx) {
      insertMarkdownAtEnd(`:::${kind}\n${placeholderText}\n:::`);
      setInsertFormPosition(null);
      setNoteMenuOpen(false);
      setPickerOpen(false);
      return;
    }
    runEditorCommand((activeEditor) => {
      ensureParagraphAfterTable(activeEditor);
      activeEditor.chain().focus().insertContent({
        type: 'docusaurusAdmonition',
        attrs: {
          kind,
          title: label,
        },
        content: [
          {
            type: 'paragraph',
            content: [{type: 'text', text: placeholderText}],
          },
        ],
      }).run();
    });
    setInsertFormPosition(null);
    setNoteMenuOpen(false);
    setPickerOpen(false);
  }, [advancedMdx, ensureParagraphAfterTable, insertMarkdownAtEnd, runEditorCommand]);

  const applyHeadingLevel = useCallback((level: 1 | 2 | 3 | 4) => {
    runEditorCommand((activeEditor) => {
      ensureParagraphAfterTable(activeEditor);
      const firstChild = activeEditor.state.doc.firstChild;
      const docIsEmpty = activeEditor.state.doc.childCount === 1
        && firstChild?.type.name === 'paragraph'
        && firstChild.content.size === 0;
      const selectionParent = activeEditor.state.selection.$from.parent;
      const chain = activeEditor.chain().focus();
      if (activeEditor.isActive('heading', {level})) {
        chain.setParagraph().run();
        return;
      }
      if (docIsEmpty) {
        activeEditor.commands.setContent({
          type: 'doc',
          content: [
            {
              type: 'heading',
              attrs: {level},
            },
          ],
        } as never);
        activeEditor.commands.setTextSelection(1);
        activeEditor.commands.focus();
        return;
      }
      if (!selectionParent.isTextblock) {
        chain.createParagraphNear().setHeading({level}).run();
        return;
      }
      chain.setHeading({level}).run();
    });
  }, [ensureParagraphAfterTable, runEditorCommand]);

  const insertMermaid = useCallback(() => {
    if (advancedMdx) {
      insertMarkdownAtEnd('```mermaid\ngraph TD\n  A[Start] --> B[Next Step]\n```');
      return;
    }
    runEditorCommand((activeEditor) => {
      ensureParagraphAfterTable(activeEditor);
      activeEditor.chain().focus().insertContent({
        type: 'docusaurusMermaid',
        attrs: {
          code: DEFAULT_MERMAID_SOURCE,
          collapsed: false,
        },
      }).run();
    });
  }, [advancedMdx, ensureParagraphAfterTable, insertMarkdownAtEnd, runEditorCommand]);

  const deleteCurrentPage = useCallback(async () => {
    if (!pageIsEditable || !sourceToken) {
      return;
    }
    setDeleting(true);
    setErrorText('');
    try {
      await requestJson('/api/delete', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          path: sourceToken,
        }),
      });
      if (typeof window !== 'undefined') {
        window.localStorage.removeItem(getDraftStorageKey(sourceToken));
      }
      setDeleteDialogOpen(false);
      window.location.assign('/docs/');
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Delete failed.');
    } finally {
      setDeleting(false);
    }
  }, [pageIsEditable, requestJson, sourceToken]);

  const toggleCurrentPageVisibility = useCallback(async () => {
    if (!pageCanManageVisibility || !sourceToken) {
      return;
    }

    setSaving(true);
    setErrorText('');
    setStatusText('');
    try {
      const payload = await requestJson<DocsVisibilityResponse>('/api/visibility', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify({
          path: sourceToken,
          hidden: !pageHiddenFromSite,
        }),
      });

      setLoadedContent((current) => (current ? {
        ...current,
        hash: payload.result.hash,
        modifiedUtc: payload.result.modifiedUtc,
      } : current));
      setFrontMatterBlock((current) => setFrontMatterBoolean(current, 'unlisted', payload.result.hidden));
      setStatusText(payload.result.hidden ? 'Page hidden from site.' : 'Page shown in site.');
      broadcastDocsStructureChanged();
      if (typeof window !== 'undefined') {
        window.setTimeout(() => window.location.reload(), 250);
      }
    } catch (error) {
      setErrorText(error instanceof Error ? error.message : 'Visibility update failed.');
    } finally {
      setSaving(false);
    }
  }, [pageCanManageVisibility, pageHiddenFromSite, requestJson, sourceToken]);

  const controlsDisabled = saving || loading || deleting;
  const sourceModeRequired = advancedMdx || richEditorUnavailable;
  const canUseTableTools = Boolean(editor && editorRevision >= 0 && editor.isActive('table') && !sourceModeRequired && !saving && !loading && !deleting);
  const currentHeadingLabel = useMemo(() => (editor ? getHeadingLabelAtSelection(editor) : null), [editor, editorRevision]);
  const currentHeadingIgnored = Boolean(currentHeadingLabel && renderIgnoredHeadingLabels.has(currentHeadingLabel));
  const deleteTableWithFallback = useCallback(() => {
    runEditorCommand((activeEditor) => {
      const deletedInSelection = activeEditor.chain().focus().deleteTable().run();
      if (deletedInSelection) {
        return;
      }

      let firstTablePos: number | null = null;
      activeEditor.state.doc.descendants((node, pos) => {
        if (node.type.name === 'table') {
          firstTablePos = pos;
          return false;
        }
        return true;
      });

      if (firstTablePos !== null) {
        activeEditor.chain().focus().setTextSelection(firstTablePos + 1).deleteTable().run();
      }
    });
  }, [runEditorCommand]);

  const pickerItems = useMemo(() => {
    const source = pickerTab === 'emoji' ? EMOJI_ITEMS : ICON_ITEMS;
    const query = pickerQuery.trim().toLowerCase();
    if (!query) {
      return source;
    }
    return source.filter((item) => item.label.toLowerCase().includes(query) || item.token.toLowerCase().includes(query));
  }, [pickerQuery, pickerTab]);

  useEffect(() => {
    if (!authoringAvailable || !pageIsEditable || editMode || autoEditApplied) {
      return;
    }

    const params = new URLSearchParams(window.location.search);
    if (params.get('edit') !== '1') {
      return;
    }

    setAutoEditApplied(true);
    void enterEditMode();
    params.delete('edit');
    const nextSearch = params.toString();
    const nextUrl = `${window.location.pathname}${nextSearch ? `?${nextSearch}` : ''}${window.location.hash}`;
    window.history.replaceState({}, '', nextUrl);
  }, [authoringAvailable, autoEditApplied, editMode, enterEditMode, pageIsEditable]);

  const hasDesktopToc = Boolean(docTOC.desktop);
  const compactEditorLayout = viewportWidth > 0 ? viewportWidth <= 996 : windowSize !== 'desktop' && windowSize !== 'ssr';
  const compactTocLayout = viewportWidth > 0 ? viewportWidth <= 996 : windowSize !== 'desktop' && windowSize !== 'ssr';
  const showInlineRightToc = Boolean(
    hasDesktopToc &&
      !rightTocCollapsed &&
      !compactTocLayout &&
      (!narrowDesktopSingleRail || leftSidebarCollapsed),
  );
  const showOverlayRightToc = Boolean(hasDesktopToc && !rightTocCollapsed && compactTocLayout);
  const showVisibleToc = showInlineRightToc || showOverlayRightToc;
  const showMetadataTitlePreview = editMode && !!metadataTitle && !hasLevelOneHeading(sourceDraft || originalSource);
  const revealGlobalScrollbars = useCallback(() => {
    if (typeof document === 'undefined' || typeof window === 'undefined') {
      return;
    }

    document.documentElement.dataset.ueScrollbarsActive = 'true';
    if (scrollbarRevealTimerRef.current !== null) {
      window.clearTimeout(scrollbarRevealTimerRef.current);
    }
    scrollbarRevealTimerRef.current = window.setTimeout(() => {
      delete document.documentElement.dataset.ueScrollbarsActive;
      scrollbarRevealTimerRef.current = null;
    }, 3500);
  }, []);

  const revealToc = useCallback(() => {
    setTocAutoVisible(true);
    setTocAutoHideVersion((value) => value + 1);
    revealGlobalScrollbars();
  }, [revealGlobalScrollbars]);

  const toggleLeftSidebar = useCallback(() => {
    setLeftSidebarCollapsed((currentLeft) => {
      const nextLeft = !currentLeft;
      if (narrowDesktopSingleRail && !nextLeft) {
        setRightTocCollapsed(true);
      }
      return nextLeft;
    });
  }, [narrowDesktopSingleRail]);

  const toggleRightToc = useCallback(() => {
    setRightTocCollapsed((currentRight) => {
      const nextRight = !currentRight;
      if (narrowDesktopSingleRail && !nextRight) {
        setLeftSidebarCollapsed(true);
      }
      return nextRight;
    });
  }, [narrowDesktopSingleRail]);

  const getTocScrollElement = useCallback((): HTMLDivElement | null => {
    const container = tocColumnRef.current;
    if (!container) {
      return null;
    }

    const desktopScrollElement = container.querySelector<HTMLDivElement>('.theme-doc-toc-desktop');
    return desktopScrollElement ?? container;
  }, []);

  useEffect(() => {
    if (typeof document === 'undefined' || typeof window === 'undefined') {
      return undefined;
    }

    const handleAnyScroll = () => revealGlobalScrollbars();
    document.addEventListener('scroll', handleAnyScroll, {capture: true, passive: true});
    return () => {
      document.removeEventListener('scroll', handleAnyScroll, true);
      if (scrollbarRevealTimerRef.current !== null) {
        window.clearTimeout(scrollbarRevealTimerRef.current);
        scrollbarRevealTimerRef.current = null;
      }
      delete document.documentElement.dataset.ueScrollbarsActive;
    };
  }, [revealGlobalScrollbars]);

  useEffect(() => {
    if (typeof document === 'undefined' || typeof window === 'undefined' || !showInlineRightToc) {
      setTocAutoVisible(true);
      if (tocAutoHideTimerRef.current !== null) {
        window.clearTimeout(tocAutoHideTimerRef.current);
        tocAutoHideTimerRef.current = null;
      }
      return undefined;
    }

    const handleActivity = () => revealToc();
    revealToc();
    document.addEventListener('scroll', handleActivity, {capture: true, passive: true});
    return () => {
      document.removeEventListener('scroll', handleActivity, true);
      if (tocAutoHideTimerRef.current !== null) {
        window.clearTimeout(tocAutoHideTimerRef.current);
        tocAutoHideTimerRef.current = null;
      }
    };
  }, [revealToc, showInlineRightToc]);

  useEffect(() => {
    if (typeof window === 'undefined' || !showInlineRightToc) {
      return undefined;
    }

    if (tocAutoHideTimerRef.current !== null) {
      window.clearTimeout(tocAutoHideTimerRef.current);
    }
    tocAutoHideTimerRef.current = window.setTimeout(() => {
      if (!tocHoveredRef.current) {
        setTocAutoVisible(false);
      }
      tocAutoHideTimerRef.current = null;
    }, 3500);

    return () => {
      if (tocAutoHideTimerRef.current !== null) {
        window.clearTimeout(tocAutoHideTimerRef.current);
        tocAutoHideTimerRef.current = null;
      }
    };
  }, [showInlineRightToc, tocAutoHideVersion]);

  useEffect(() => {
    const rail = tocRailRef.current;
    const shell = layoutShellRef.current;
    const sidebar = document.querySelector<HTMLElement>('.theme-doc-sidebar-container');
    const footer = document.querySelector<HTMLElement>('footer');
    if (!rail || !shell || typeof window === 'undefined' || !showInlineRightToc) {
      return undefined;
    }

    const updateRailLayout = () => {
      const shellRect = shell.getBoundingClientRect();
      const railRect = rail.getBoundingClientRect();
      const footerRect = footer?.getBoundingClientRect();
      const navbarRect = document.querySelector('.navbar')?.getBoundingClientRect();
      const navbarHeight = navbarRect?.height ?? 64;
      const baseTop = navbarHeight + 1.6;
      const defaultHeight = Math.max(0, window.innerHeight - navbarHeight - 12.8);
      const availableHeight = footerRect ? Math.max(0, footerRect.top - baseTop - 12) : defaultHeight;
      const nextLayout = {
        top: baseTop,
        right: Math.max(0, window.innerWidth - shellRect.right),
        height: Math.min(defaultHeight, availableHeight),
      };
      setTocFixedLayout((current) => {
        if (
          Math.abs(current.top - nextLayout.top) < 0.5 &&
          Math.abs(current.right - nextLayout.right) < 0.5 &&
          Math.abs(current.height - nextLayout.height) < 0.5
        ) {
          return current;
        }
        return nextLayout;
      });
    };

    updateRailLayout();
    const resizeObserver = new ResizeObserver(() => updateRailLayout());
    resizeObserver.observe(shell);
    resizeObserver.observe(rail);
    if (sidebar) {
      resizeObserver.observe(sidebar);
    }
    if (footer) {
      resizeObserver.observe(footer);
    }
    window.addEventListener('resize', updateRailLayout);
    window.addEventListener('scroll', updateRailLayout, {passive: true});
    return () => {
      resizeObserver.disconnect();
      window.removeEventListener('resize', updateRailLayout);
      window.removeEventListener('scroll', updateRailLayout);
    };
  }, [leftSidebarCollapsed, rightTocCollapsed, showInlineRightToc]);

  useEffect(() => {
    const tocElement = getTocScrollElement();
    if (!showVisibleToc || !tocElement || typeof window === 'undefined') {
      setTocScrollbarVisible(false);
      setTocScrollbarThumb({height: 0, offset: 0});
      return undefined;
    }

    const updateScrollbarThumb = (reveal: boolean) => {
      const {clientHeight, scrollHeight, scrollTop} = tocElement;
      if (scrollHeight <= clientHeight + 1) {
        setTocScrollbarThumb({height: 0, offset: 0});
        setTocScrollbarVisible(false);
        return;
      }

      const thumbHeight = Math.min(clientHeight, Math.max(36, (clientHeight / scrollHeight) * clientHeight));
      const maxOffset = Math.max(0, clientHeight - thumbHeight);
      const scrollRange = Math.max(1, scrollHeight - clientHeight);
      const offset = (scrollTop / scrollRange) * maxOffset;
      setTocScrollbarThumb({height: thumbHeight, offset});

      if (!reveal) {
        return;
      }

      setTocScrollbarVisible(true);
      if (tocScrollbarTimerRef.current !== null) {
        window.clearTimeout(tocScrollbarTimerRef.current);
      }
      tocScrollbarTimerRef.current = window.setTimeout(() => {
        setTocScrollbarVisible(false);
        tocScrollbarTimerRef.current = null;
      }, 3500);
    };

    const handleScroll = () => {
      revealToc();
      updateScrollbarThumb(true);
    };
    const handleResize = () => updateScrollbarThumb(false);

    updateScrollbarThumb(false);
    window.addEventListener('resize', handleResize);
    tocElement.addEventListener('scroll', handleScroll, {passive: true});
    return () => {
      window.removeEventListener('resize', handleResize);
      tocElement.removeEventListener('scroll', handleScroll);
      setTocScrollbarVisible(false);
      if (tocScrollbarTimerRef.current !== null) {
        window.clearTimeout(tocScrollbarTimerRef.current);
        tocScrollbarTimerRef.current = null;
      }
    };
  }, [getTocScrollElement, revealToc, showVisibleToc]);

  useEffect(() => {
    const tocElement = getTocScrollElement();
    if (!showVisibleToc || !tocElement || typeof window === 'undefined') {
      tocActiveSyncLastKeyRef.current = null;
      return undefined;
    }

    const syncActiveTocItemIntoView = () => {
      tocActiveSyncFrameRef.current = null;

      const activeLink = tocElement.querySelector<HTMLAnchorElement>('.table-of-contents__link--active');
      if (!activeLink) {
        tocActiveSyncLastKeyRef.current = null;
        return;
      }

      const nextKey = activeLink.getAttribute('href') || activeLink.textContent || '';
      if (!nextKey || nextKey === tocActiveSyncLastKeyRef.current) {
        return;
      }

      const start = window.performance.now();
      const areaRect = tocElement.getBoundingClientRect();
      const activeRect = activeLink.getBoundingClientRect();
      const topPadding = 14;
      const bottomPadding = 18;
      let delta = 0;

      if (activeRect.top < areaRect.top + topPadding) {
        delta = activeRect.top - (areaRect.top + topPadding);
      } else if (activeRect.bottom > areaRect.bottom - bottomPadding) {
        delta = activeRect.bottom - (areaRect.bottom - bottomPadding);
      }

      if (Math.abs(delta) > 1) {
        tocElement.scrollTo({
          top: Math.max(0, tocElement.scrollTop + delta),
          behavior: 'auto',
        });
      }

      tocActiveSyncLastKeyRef.current = nextKey;

      const perfTarget = window as Window & {
        __ueDocsTocPerf?: {count: number; totalMs: number; maxMs: number; lastMs: number; lastKey: string; lastDelta: number};
      };
      const duration = window.performance.now() - start;
      const currentPerf = perfTarget.__ueDocsTocPerf ?? {
        count: 0,
        totalMs: 0,
        maxMs: 0,
        lastMs: 0,
        lastKey: '',
        lastDelta: 0,
      };
      perfTarget.__ueDocsTocPerf = {
        count: currentPerf.count + 1,
        totalMs: currentPerf.totalMs + duration,
        maxMs: Math.max(currentPerf.maxMs, duration),
        lastMs: duration,
        lastKey: nextKey,
        lastDelta: delta,
      };
    };

    const scheduleActiveTocSync = () => {
      if (tocActiveSyncFrameRef.current !== null) {
        return;
      }
      tocActiveSyncFrameRef.current = window.requestAnimationFrame(syncActiveTocItemIntoView);
    };

    scheduleActiveTocSync();

    const mutationObserver = new MutationObserver((mutations) => {
      for (const mutation of mutations) {
        if (
          mutation.type === 'attributes' &&
          mutation.attributeName === 'class' &&
          mutation.target instanceof HTMLElement &&
          mutation.target.classList.contains('table-of-contents__link')
        ) {
          scheduleActiveTocSync();
          break;
        }
      }
    });

    mutationObserver.observe(tocElement, {
      subtree: true,
      attributes: true,
      attributeFilter: ['class'],
    });

    return () => {
      mutationObserver.disconnect();
      if (tocActiveSyncFrameRef.current !== null) {
        window.cancelAnimationFrame(tocActiveSyncFrameRef.current);
        tocActiveSyncFrameRef.current = null;
      }
    };
  }, [getTocScrollElement, showVisibleToc]);

  useEffect(() => {
    if (editMode || typeof window === 'undefined') {
      return undefined;
    }

    const shell = layoutShellRef.current;
    const markdownRoot = shell?.querySelector('.theme-doc-markdown');
    if (!(markdownRoot instanceof HTMLElement)) {
      return undefined;
    }

    const sourceForRender = renderSourceBody || sourceDraftRef.current || originalSource;
    if (!sourceForRender.trim()) {
      markdownRoot.querySelectorAll<HTMLElement>('h1, h2, h3, h4, h5, h6, p').forEach((element) => {
        element.style.textAlign = '';
      });
      return undefined;
    }

    const frame = window.requestAnimationFrame(() => {
      const alignments = collectRenderBlockAlignments(sourceForRender);
      const blocks = Array.from(markdownRoot.querySelectorAll<HTMLElement>('h1, h2, h3, h4, h5, h6, p'));
      const alignedBlocks = metadataTitle && !hasLevelOneHeading(sourceForRender) && blocks[0]?.tagName === 'H1'
        ? blocks.slice(1)
        : blocks;

      blocks.forEach((element) => {
        element.style.textAlign = '';
      });
      alignedBlocks.forEach((element, index) => {
        const alignment = alignments[index];
        element.style.textAlign = alignment && alignment !== 'left' ? alignment : '';
      });
    });

    return () => {
      window.cancelAnimationFrame(frame);
    };
  }, [editMode, editorContentRevision, metadataTitle, originalSource, renderSourceBody, sourceDraft]);

  return (
    <div
      ref={layoutShellRef}
      className={clsx(
        authoringStyles.docLayoutRow,
        !showInlineRightToc && authoringStyles.docLayoutNoToc,
        compactEditorLayout && authoringStyles.docLayoutCompactEditor,
      )}
      style={{
        '--doc-viewport-centering-shift': `${layoutViewportShift}px`,
      } as React.CSSProperties}
    >
      <div className={authoringStyles.docContentShell}>
        <div className={authoringStyles.docContentColumn}>
        <ContentVisibility metadata={metadata} />
        <DocVersionBanner />
        <div>
          <article>
            <div className={authoringStyles.docHeaderRow}>
              <DocBreadcrumbs />
              {!editMode ? (
                <div className={authoringStyles.viewModeActions} aria-label="Documentation layout controls">
                  <div className={authoringStyles.layoutControls}>
                    <button
                      type="button"
                      className={clsx(authoringStyles.layoutToggleButton, leftSidebarCollapsed && authoringStyles.layoutToggleButtonActive)}
                      aria-label={leftSidebarCollapsed ? 'Show pages sidebar' : 'Hide pages sidebar'}
                      title={leftSidebarCollapsed ? 'Show pages sidebar' : 'Hide pages sidebar'}
                      onClick={toggleLeftSidebar}
                    >
                      <ToolbarIcon name="panelLeft" />
                      <span>Pages</span>
                    </button>
                    <button
                      type="button"
                      className={clsx(authoringStyles.layoutToggleButton, rightTocCollapsed && authoringStyles.layoutToggleButtonActive)}
                      aria-label={rightTocCollapsed ? 'Show table of contents sidebar' : 'Hide table of contents sidebar'}
                      title={rightTocCollapsed ? 'Show table of contents sidebar' : 'Hide table of contents sidebar'}
                      onClick={toggleRightToc}
                    >
                      <ToolbarIcon name="panelRight" />
                      <span>TOC</span>
                    </button>
                  </div>
                  {((pageIsEditable && authoringAvailable) || pageCanManageVisibility) ? (
                    <div className={authoringStyles.editActions}>
                      {pageCanManageVisibility ? (
                        <button type="button" className={authoringStyles.secondaryButton} onClick={() => void toggleCurrentPageVisibility()} disabled={saving || loading || deleting}>
                          {pageHiddenFromSite ? 'Show In Site' : 'Hide From Site'}
                        </button>
                      ) : null}
                      {pageIsEditable && authoringAvailable ? (
                        <button type="button" className={authoringStyles.primaryButton} onClick={() => void enterEditMode()}>
                          Edit
                        </button>
                      ) : null}
                    </div>
                  ) : null}
                </div>
              ) : null}
            </div>
            <DocVersionBadge />
            {pageIsEditable && authoringAvailable && editMode && sourceModeRequired ? (
              <div className={authoringStyles.editActions}>
                <div className={authoringStyles.editModeToolbar}>
                  <IconButton icon="save" label="Save changes" onClick={() => void saveChanges()} disabled={!isDirty || controlsDisabled} />
                  <IconButton icon="redo" label="Discard changes" onClick={() => discardChanges()} disabled={controlsDisabled} />
                  <IconButton icon="trash" label="Delete page" onClick={() => setDeleteDialogOpen(true)} disabled={controlsDisabled} />
                  <IconButton icon="logOut" label="Exit edit mode" onClick={() => setEditMode(false)} disabled={controlsDisabled} />
                </div>
              </div>
            ) : null}

            {!editMode ? (
              <DocItemContent>{children}</DocItemContent>
            ) : (
              <div className={authoringStyles.editModeSurface}>
                {loading ? <p className={authoringStyles.statusText}>Loading page content...</p> : null}
                {showMetadataTitlePreview ? (
                  <div className={clsx('markdown', authoringStyles.editorMetadataTitlePreview)}>
                    <h1>{metadataTitle}</h1>
                  </div>
                ) : null}
                {sourceModeRequired ? (
                  <div className={authoringStyles.warningPanel}>
                    <strong>Source Mode Required</strong>
                    <p>
                      Rich editing is disabled to protect content fidelity.
                    </p>
                    <textarea
                      className={authoringStyles.sourceTextarea}
                      value={sourceDraft}
                      onChange={(event) => {
                        const next = event.target.value;
                        sourceDraftRef.current = next;
                        tocIgnoredHeadingLabelsRef.current = collectTocIgnoredHeadingLabels(next);
                        tocMarkerEnabledRef.current = hasExistingTocMarker(next);
                        setSourceDraft(next);
                        setIsDirty(next !== originalSource);
                      }}
                      disabled={controlsDisabled}
                    />
                  </div>
                ) : (
                  <div className={authoringStyles.editorShell} ref={editorShellRef}>
                    <aside className={authoringStyles.editorToolbarRail}>
                      <div className={authoringStyles.editorToolbar} aria-label="Editor toolbar">
                        <div className={clsx(authoringStyles.toolbarGroup, authoringStyles.toolbarGroupPinned)}>
                          <IconButton icon="save" label="Save changes" onClick={() => void saveChanges()} disabled={!isDirty || controlsDisabled} />
                          <IconButton icon="redo" label="Discard changes" onClick={() => discardChanges()} disabled={controlsDisabled} />
                          <IconButton icon="trash" label="Delete page" onClick={() => setDeleteDialogOpen(true)} disabled={controlsDisabled} />
                          <IconButton icon="logOut" label="Exit edit mode" onClick={() => setEditMode(false)} disabled={controlsDisabled} />
                        </div>
                        <div className={authoringStyles.toolbarGroup}>
                          <IconButton icon="bold" label="Bold" active={editor?.isActive('bold')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleBold().run())} disabled={controlsDisabled} />
                          <IconButton icon="italic" label="Italic" active={editor?.isActive('italic')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleItalic().run())} disabled={controlsDisabled} />
                          <IconButton icon="underline" label="Underline" active={editor?.isActive('underline')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleUnderline().run())} disabled={controlsDisabled} />
                          <IconButton icon="strikethrough" label="Strikethrough" active={editor?.isActive('strike')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleStrike().run())} disabled={controlsDisabled} />
                          <IconButton icon="code" label="Inline code" active={editor?.isActive('code')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleCode().run())} disabled={controlsDisabled} />
                          <IconButton icon="codeBlock" label="Code block" active={editor?.isActive('codeBlock')} onClick={() => runEditorCommand((activeEditor) => { ensureParagraphAfterTable(activeEditor); activeEditor.chain().focus().toggleCodeBlock().run(); })} disabled={controlsDisabled} />
                          <IconButton icon="clear" label="Clear formatting" onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().unsetAllMarks().clearNodes().run())} disabled={controlsDisabled} />
                        </div>
                        <div className={authoringStyles.toolbarGroup}>
                          <IconButton label="Heading 1" active={editor?.isActive('heading', {level: 1})} onClick={() => applyHeadingLevel(1)} disabled={controlsDisabled}>
                            H1
                          </IconButton>
                          <IconButton label="Heading 2" active={editor?.isActive('heading', {level: 2})} onClick={() => applyHeadingLevel(2)} disabled={controlsDisabled}>
                            H2
                          </IconButton>
                          <IconButton label="Heading 3" active={editor?.isActive('heading', {level: 3})} onClick={() => applyHeadingLevel(3)} disabled={controlsDisabled}>
                            H3
                          </IconButton>
                          <IconButton label="Heading 4" active={editor?.isActive('heading', {level: 4})} onClick={() => applyHeadingLevel(4)} disabled={controlsDisabled}>
                            H4
                          </IconButton>
                        </div>
                        <div className={authoringStyles.toolbarGroup}>
                          <IconButton icon="bulletList" label="Bulleted list" active={editor?.isActive('bulletList')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleBulletList().run())} disabled={controlsDisabled} />
                          <IconButton icon="listOrdered" label="Numbered list" active={editor?.isActive('orderedList')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleOrderedList().run())} disabled={controlsDisabled} />
                          <IconButton icon="taskList" label="Task list" active={editor?.isActive('taskList')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleTaskList().run())} disabled={controlsDisabled} />
                          <IconButton icon="quote" label="Quote" active={editor?.isActive('blockquote')} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().toggleBlockquote().run())} disabled={controlsDisabled} />
                        </div>
                        <div className={authoringStyles.toolbarGroup}>
                          <IconButton icon="link" label="Insert link" active={editor?.isActive('link')} onClick={() => openInsertForm('link')} disabled={controlsDisabled} />
                          <IconButton icon="unlink" label="Remove link" onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().extendMarkRange('link').unsetLink().run())} disabled={controlsDisabled || !editor?.isActive('link')} />
                          <IconButton icon="image" label="Insert image" onClick={() => openInsertForm('image')} disabled={controlsDisabled} />
                        </div>
                        <div className={authoringStyles.toolbarGroup}>
                          <IconButton icon="alignLeft" label="Align left" active={editor?.isActive({textAlign: 'left'})} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().setTextAlign('left').run())} disabled={controlsDisabled} />
                          <IconButton icon="alignCenter" label="Align center" active={editor?.isActive({textAlign: 'center'})} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().setTextAlign('center').run())} disabled={controlsDisabled} />
                          <IconButton icon="alignRight" label="Align right" active={editor?.isActive({textAlign: 'right'})} onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().setTextAlign('right').run())} disabled={controlsDisabled} />
                        </div>
                        <div className={authoringStyles.toolbarGroup}>
                          <IconButton icon="toc" label="Table of contents marker" onClick={() => insertTocMarker()} disabled={controlsDisabled} />
                          <IconButton icon="tocIgnore" label="Toggle heading TOC ignore" active={currentHeadingIgnored} onClick={() => insertTocIgnoreMarker()} disabled={controlsDisabled} />
                          <IconButton icon="table" label="Insert table" onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().insertTable({rows: 3, cols: 3, withHeaderRow: true}).run())} disabled={controlsDisabled} />
                          <IconButton icon="columns" label="Add table column" onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().addColumnAfter().run())} disabled={!canUseTableTools} />
                          <IconButton icon="deleteColumn" label="Delete table column" onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().deleteColumn().run())} disabled={!canUseTableTools} />
                          <IconButton icon="rows" label="Add table row" onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().addRowAfter().run())} disabled={!canUseTableTools} />
                          <IconButton icon="deleteRow" label="Delete table row" onClick={() => runEditorCommand((activeEditor) => activeEditor.chain().focus().deleteRow().run())} disabled={!canUseTableTools} />
                          <IconButton icon="minusCircle" label="Delete table" onClick={() => deleteTableWithFallback()} disabled={!canUseTableTools} />
                        </div>
                        <div className={authoringStyles.toolbarGroup}>
                          <IconButton icon="divider" label="Divider" onClick={() => runEditorCommand((activeEditor) => { ensureParagraphAfterTable(activeEditor); activeEditor.chain().focus().setHorizontalRule().run(); })} disabled={controlsDisabled} />
                          <IconButton
                            icon="note"
                            label="Note block variants"
                            active={noteMenuOpen}
                            onClick={() => toggleNoteMenu()}
                            disabled={controlsDisabled}
                          />
                          <IconButton icon="sparkles" label="Mermaid diagram" onClick={() => insertMermaid()} disabled={controlsDisabled} />
                          <IconButton
                            icon="file"
                            label="Emoji and icon picker"
                            active={pickerOpen}
                            onClick={() => togglePickerMenu()}
                            disabled={controlsDisabled}
                          />
                          <IconButton icon="codeBlock" label="Set code language" onClick={() => openInsertForm('code')} disabled={controlsDisabled} />
                        </div>
                      </div>
                    </aside>
                    <div className={authoringStyles.editorCanvas}>
                    {noteMenuOpen ? (
                      <div
                        className={authoringStyles.noteMenu}
                        style={insertFormPosition ? {left: `${insertFormPosition.left}px`, top: `${insertFormPosition.top}px`} : undefined}
                        role="dialog"
                        aria-modal="true"
                      >
                        <button type="button" className={authoringStyles.noteMenuButton} data-variant="info" onClick={() => insertNote('info')} disabled={controlsDisabled}>
                          <span className={authoringStyles.noteMenuDot} aria-hidden="true" />
                          Info
                        </button>
                        <button type="button" className={authoringStyles.noteMenuButton} data-variant="note" onClick={() => insertNote('note')} disabled={controlsDisabled}>
                          <span className={authoringStyles.noteMenuDot} aria-hidden="true" />
                          Note
                        </button>
                        <button type="button" className={authoringStyles.noteMenuButton} data-variant="success" onClick={() => insertNote('success')} disabled={controlsDisabled}>
                          <span className={authoringStyles.noteMenuDot} aria-hidden="true" />
                          Success
                        </button>
                        <button type="button" className={authoringStyles.noteMenuButton} data-variant="warning" onClick={() => insertNote('warning')} disabled={controlsDisabled}>
                          <span className={authoringStyles.noteMenuDot} aria-hidden="true" />
                          Warning
                        </button>
                        <button type="button" className={authoringStyles.noteMenuButton} data-variant="error" onClick={() => insertNote('error')} disabled={controlsDisabled}>
                          <span className={authoringStyles.noteMenuDot} aria-hidden="true" />
                          Error
                        </button>
                      </div>
                    ) : null}
                    {insertFormMode === 'link' ? (
                      <form
                        className={authoringStyles.insertForm}
                        style={insertFormPosition ? {left: `${insertFormPosition.left}px`, top: `${insertFormPosition.top}px`} : undefined}
                        onSubmit={(event) => {
                          event.preventDefault();
                          submitLink();
                        }}
                      >
                        <input
                          className={authoringStyles.insertInput}
                          aria-label="Link text"
                          placeholder="Text"
                          value={linkText}
                          onChange={(event) => setLinkText(event.target.value)}
                          disabled={controlsDisabled}
                        />
                        <input
                          className={authoringStyles.insertInput}
                          aria-label="Link URL"
                          placeholder="https://example.com or /docs/page"
                          value={linkHref}
                          onChange={(event) => setLinkHref(event.target.value)}
                          disabled={controlsDisabled}
                        />
                        <div className={authoringStyles.insertFormActions}>
                          <IconButton icon="save" label="Apply link" onClick={submitLink} disabled={!linkHref.trim() || controlsDisabled} />
                          <IconButton
                            icon="minusCircle"
                            label="Cancel insert"
                            onClick={() => {
                              setInsertFormMode(null);
                              setInsertFormPosition(null);
                            }}
                            disabled={controlsDisabled}
                          />
                        </div>
                      </form>
                    ) : null}
                    {insertFormMode === 'image' ? (
                      <form
                        className={authoringStyles.insertForm}
                        style={insertFormPosition ? {left: `${insertFormPosition.left}px`, top: `${insertFormPosition.top}px`} : undefined}
                        onSubmit={(event) => {
                          event.preventDefault();
                          submitImage();
                        }}
                      >
                        <input
                          className={authoringStyles.insertInput}
                          aria-label="Image URL"
                          placeholder="/img/example.png or https://..."
                          value={imageSrc}
                          onChange={(event) => setImageSrc(event.target.value)}
                          disabled={controlsDisabled}
                        />
                        <input
                          className={authoringStyles.insertInput}
                          aria-label="Image alt text"
                          placeholder="Alt text"
                          value={imageAlt}
                          onChange={(event) => setImageAlt(event.target.value)}
                          disabled={controlsDisabled}
                        />
                        <div className={authoringStyles.insertFormActions}>
                          <IconButton icon="save" label="Insert image" onClick={submitImage} disabled={!imageSrc.trim() || controlsDisabled} />
                          <IconButton
                            icon="minusCircle"
                            label="Cancel insert"
                            onClick={() => {
                              setInsertFormMode(null);
                              setInsertFormPosition(null);
                            }}
                            disabled={controlsDisabled}
                          />
                        </div>
                      </form>
                    ) : null}
                    {insertFormMode === 'code' ? (
                      <form
                        className={authoringStyles.insertForm}
                        style={insertFormPosition ? {left: `${insertFormPosition.left}px`, top: `${insertFormPosition.top}px`} : undefined}
                        onSubmit={(event) => {
                          event.preventDefault();
                          submitCodeLanguage();
                        }}
                      >
                        <input
                          className={authoringStyles.insertInput}
                          aria-label="Code block language"
                          placeholder="Select language"
                          list="ue-docs-code-languages"
                          value={codeLanguage}
                          onChange={(event) => setCodeLanguage(event.target.value)}
                          disabled={controlsDisabled}
                        />
                        <datalist id="ue-docs-code-languages">
                          {CODE_LANGUAGE_OPTIONS.map((option) => (
                            <option value={option} key={option}>
                              {option || '(none)'}
                            </option>
                          ))}
                        </datalist>
                        <div className={authoringStyles.insertFormActions}>
                          <IconButton icon="save" label="Apply code language" onClick={submitCodeLanguage} disabled={controlsDisabled} />
                          <IconButton
                            icon="minusCircle"
                            label="Cancel insert"
                            onClick={() => {
                              setInsertFormMode(null);
                              setInsertFormPosition(null);
                            }}
                            disabled={controlsDisabled}
                          />
                        </div>
                      </form>
                    ) : null}
                    {pickerOpen ? (
                      <div className={authoringStyles.pickerModal} style={insertFormPosition ? {left: `${insertFormPosition.left}px`, top: `${insertFormPosition.top}px`} : undefined} role="dialog" aria-modal="true">
                        <div className={authoringStyles.pickerTabs}>
                          <button type="button" className={clsx(authoringStyles.pickerTabButton, pickerTab === 'emoji' && authoringStyles.pickerTabButtonActive)} onClick={() => setPickerTab('emoji')} disabled={controlsDisabled}>
                            Emoji
                          </button>
                          <button type="button" className={clsx(authoringStyles.pickerTabButton, pickerTab === 'icon' && authoringStyles.pickerTabButtonActive)} onClick={() => setPickerTab('icon')} disabled={controlsDisabled}>
                            Icons
                          </button>
                        </div>
                        <input
                          className={authoringStyles.pickerSearch}
                          value={pickerQuery}
                          onChange={(event) => setPickerQuery(event.target.value)}
                          placeholder="Search"
                          aria-label="Search emoji and icons"
                          disabled={controlsDisabled}
                        />
                        <div className={authoringStyles.pickerGrid}>
                          {pickerItems.map((item) => (
                            <button type="button" key={item.token} className={authoringStyles.pickerItem} onClick={() => insertPickerToken(item.token)} disabled={controlsDisabled}>
                              <span className={authoringStyles.pickerItemPreview}>
                                <ShortcodeVisual token={item.token} className={authoringStyles.pickerItemGlyph} iconClassName={authoringStyles.pickerItemIcon} />
                              </span>
                              <span className={authoringStyles.pickerItemLabel}>{item.label}</span>
                              <span className={authoringStyles.pickerItemToken}>{item.token}</span>
                            </button>
                          ))}
                        </div>
                      </div>
                    ) : null}
                    <EditorContent editor={editor} />
                  </div>
                  </div>
                )}
                {errorText ? <p className={authoringStyles.errorText}>{errorText}</p> : null}
                {statusText ? <p className={authoringStyles.statusText}>{statusText}</p> : null}
                {deleteDialogOpen ? (
                  <div className={authoringStyles.dialogBackdrop} onMouseDown={() => !controlsDisabled && setDeleteDialogOpen(false)}>
                    <div className={authoringStyles.dialogCard} role="dialog" aria-modal="true" onMouseDown={(event) => event.stopPropagation()}>
                      <h3 className={authoringStyles.dialogTitle}>Delete Page</h3>
                      <p className={authoringStyles.dialogBody}>
                        Delete this page from the docs tree? This action removes the source file.
                      </p>
                      <div className={authoringStyles.dialogActions}>
                        <IconButton icon="trash" label="Delete page" onClick={() => void deleteCurrentPage()} disabled={controlsDisabled} />
                        <IconButton icon="minusCircle" label="Cancel delete" onClick={() => setDeleteDialogOpen(false)} disabled={controlsDisabled} />
                      </div>
                    </div>
                  </div>
                ) : null}
              </div>
            )}

            <DocItemFooter />
          </article>
          <DocItemPaginator />
        </div>
      </div>
      </div>
      {showOverlayRightToc ? (
        <button type="button" className={authoringStyles.docTocOverlayBackdrop} aria-label="Close table of contents overlay" onClick={() => setRightTocCollapsed(true)} />
      ) : null}
      {docTOC.desktop ? (
        <div
          ref={tocRailRef}
          aria-label="Table of contents sidebar"
          className={clsx(
            authoringStyles.docTocColumn,
            showOverlayRightToc && authoringStyles.docTocColumnOverlay,
            !showVisibleToc && authoringStyles.docTocColumnHidden,
            showInlineRightToc && !tocAutoVisible && authoringStyles.docTocColumnIdleHidden,
          )}
          onMouseEnter={() => {
            tocHoveredRef.current = true;
            if (showInlineRightToc) {
              revealToc();
            }
          }}
          onMouseLeave={() => {
            tocHoveredRef.current = false;
            if (showInlineRightToc) {
              setTocAutoHideVersion((value) => value + 1);
            }
          }}
        >
          <div
            className={authoringStyles.docTocStickyFrame}
            style={
              showInlineRightToc
                ? {
                    top: `${tocFixedLayout.top}px`,
                    right: `${tocFixedLayout.right}px`,
                    height: `${tocFixedLayout.height}px`,
                  }
                : undefined
            }
          >
            <div ref={tocColumnRef} tabIndex={0} className={authoringStyles.docTocScrollArea}>
              {docTOC.desktop}
            </div>
            {tocScrollbarThumb.height > 0 ? (
              <div aria-hidden="true" className={clsx(authoringStyles.docTocScrollbar, tocScrollbarVisible && authoringStyles.docTocScrollbarVisible)}>
                <div
                  className={authoringStyles.docTocScrollbarThumb}
                  style={{height: `${tocScrollbarThumb.height}px`, transform: `translateY(${tocScrollbarThumb.offset}px)`}}
                />
              </div>
            ) : null}
          </div>
        </div>
      ) : null}
    </div>
  );
}
