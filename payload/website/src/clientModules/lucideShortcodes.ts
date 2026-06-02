import {createIcons, icons} from 'lucide';
import type {ClientModule} from '@docusaurus/types';
import {EMOJI_MAP, SHORTCODE_REGEX} from '../theme/authoring/shortcodes';

function canRewriteNode(node: Node): boolean {
  const parent = node.parentElement;
  if (!parent) {
    return false;
  }

  const blockedSelectors = ['code', 'pre', 'script', 'style', 'textarea', '.ue-editor-ignore-shortcodes'];
  return !blockedSelectors.some((selector) => parent.closest(selector));
}

function replaceShortcodes(root: Element): void {
  const walker = document.createTreeWalker(root, NodeFilter.SHOW_TEXT);
  const targets: Text[] = [];
  while (walker.nextNode()) {
    const textNode = walker.currentNode as Text;
    if (!textNode.nodeValue || textNode.nodeValue.indexOf(':') === -1) {
      continue;
    }
    if (!canRewriteNode(textNode)) {
      continue;
    }
    targets.push(textNode);
  }

  for (const textNode of targets) {
    const source = textNode.nodeValue ?? '';
    SHORTCODE_REGEX.lastIndex = 0;
    if (!SHORTCODE_REGEX.test(source)) {
      continue;
    }

    SHORTCODE_REGEX.lastIndex = 0;
    const fragment = document.createDocumentFragment();
    let cursor = 0;
    let match: RegExpExecArray | null;
    while ((match = SHORTCODE_REGEX.exec(source)) !== null) {
      if (match.index > cursor) {
        fragment.append(document.createTextNode(source.slice(cursor, match.index)));
      }

      const iconName = match[1];
      const emojiName = match[2];
      if (iconName) {
        const iconNode = document.createElement('i');
        iconNode.setAttribute('data-lucide', iconName);
        iconNode.className = 'ue-inline-icon';
        fragment.append(iconNode);
      } else if (emojiName && EMOJI_MAP[emojiName]) {
        fragment.append(document.createTextNode(EMOJI_MAP[emojiName]));
      } else {
        fragment.append(document.createTextNode(match[0]));
      }
      cursor = match.index + match[0].length;
    }

    if (cursor < source.length) {
      fragment.append(document.createTextNode(source.slice(cursor)));
    }

    textNode.parentNode?.replaceChild(fragment, textNode);
  }
}

function refreshShortcodes(): void {
  const docRoots = document.querySelectorAll('.theme-doc-markdown, .markdown, article');
  for (const root of Array.from(docRoots)) {
    replaceShortcodes(root);
  }

  createIcons({
    icons,
    attrs: {
      class: 'ue-inline-icon-svg',
      'stroke-width': '2',
    },
  });
}

const moduleImpl: ClientModule = {
  onRouteDidUpdate() {
    window.requestAnimationFrame(() => {
      refreshShortcodes();
    });
  },
};

export default moduleImpl;
