export type ShortcodeKind = 'icon' | 'emoji';

export type ShortcodeMatch = {
  kind: ShortcodeKind;
  name: string;
  token: string;
};

export const EMOJI_MAP: Record<string, string> = {
  smile: '😄',
  rocket: '🚀',
  warning: '⚠️',
  check: '✅',
  x: '❌',
  fire: '🔥',
  sparkle: '✨',
  info: 'ℹ️',
  bug: '🐛',
  lock: '🔒',
  unlock: '🔓',
  idea: '💡',
  tools: '🛠️',
  pin: '📌',
  note: '📝',
  clock: '⏱️',
  eyes: '👀',
  star: '⭐',
  package: '📦',
  folder: '📁',
  file: '📄',
  target: '🎯',
  white_check_mark: '✅',
  bulb: '💡',
  memo: '📝',
  gear: '⚙️',
  bookmark: '🔖',
  chart_with_upwards_trend: '📈',
  wrench: '🔧',
};

export const SHORTCODE_REGEX = /:icon\[([a-z0-9-]+)\]:|:([a-z0-9_+\-]+):/gi;
export const SHORTCODE_EXACT_REGEX = /^(?::icon\[([a-z0-9-]+)\]:|:([a-z0-9_+\-]+):)$/i;
export const SHORTCODE_INPUT_REGEX = /(?::icon\[([a-z0-9-]+)\]:|:([a-z0-9_+\-]+):)$/i;
export const SHORTCODE_PASTE_REGEX = /(?::icon\[([a-z0-9-]+)\]:|:([a-z0-9_+\-]+):)/gi;

export function parseShortcodeToken(value: string): ShortcodeMatch | null {
  const trimmed = (value || '').trim();
  const match = SHORTCODE_EXACT_REGEX.exec(trimmed);
  if (!match) {
    return null;
  }

  if (match[1]) {
    return {
      kind: 'icon',
      name: match[1].toLowerCase(),
      token: `:icon[${match[1].toLowerCase()}]:`,
    };
  }

  const emojiName = match[2]?.toLowerCase();
  if (emojiName && EMOJI_MAP[emojiName]) {
    return {
      kind: 'emoji',
      name: emojiName,
      token: `:${emojiName}:`,
    };
  }

  return null;
}

export function toLucideExportName(name: string): string {
  return (name || '')
    .split('-')
    .filter(Boolean)
    .map((part) => part.charAt(0).toUpperCase() + part.slice(1))
    .join('');
}
