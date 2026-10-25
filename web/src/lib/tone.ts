import {
  IconAlertCircle,
  IconAlertTriangle,
  IconCircleCheck,
  IconInfoCircle,
  IconMinus,
  type Icon,
} from '@tabler/icons-react';

/**
 * The five tones every status in the app is drawn in, and nothing else: neutral for what is simply so (closed, a
 * disposition, a recorded replay), information while something runs or for a fact worth seeing, positive only for a
 * passed check or an effect verified at the receiver, attention when a person is needed (an escalation, an approval
 * waiting), blocking when a write was refused or something failed. A tone never stands alone: every badge carries an
 * icon and its words, so the meaning survives without colour.
 */
export type Tone = 'neutral' | 'info' | 'positive' | 'attention' | 'blocking';

/**
 * Each tone's Mantine colour. These are the colours whose text, outline, light and filled tokens styles.css tunes to
 * 4.5:1 on every surface of the five appearances, so a status badge needs no contrast rule of its own.
 */
export const TONE_COLOURS: Record<Tone, string> = {
  neutral: 'gray',
  info: 'blue',
  positive: 'green',
  attention: 'yellow',
  blocking: 'red',
};

/** The icon a status takes when its own table names none. */
export const TONE_ICONS: Record<Tone, Icon> = {
  neutral: IconMinus,
  info: IconInfoCircle,
  positive: IconCircleCheck,
  attention: IconAlertTriangle,
  blocking: IconAlertCircle,
};

/** A status as a badge shows it: its tone, its words, the icon beside them and the longer explanation. */
export interface Status {
  tone: Tone;
  label: string;
  hint?: string;
  icon?: Icon;
}

/** The text colour token of a tone, for an icon or a short line drawn in it. */
export const toneText = (tone: Tone) => `var(--mantine-color-${TONE_COLOURS[tone]}-text)`;
