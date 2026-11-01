import {
  IconAffiliate,
  IconBuildingHospital,
  IconCircleDashed,
  IconCode,
  IconFileCheck,
  IconFileDescription,
  IconHistory,
  IconMapPin,
  IconTimeline,
  IconUser,
  IconUsersGroup,
  type Icon,
} from '@tabler/icons-react';

/**
 * Identity hues: which thing something is (a navigation section, a board member, a run mode, a receiver category),
 * never how it stands, which is the five status tones' work (tone.ts). They are the validated --shutter-hue-* tokens of
 * styles.css, drawn only as graphics (icons, avatars, dots, edges, bars) beside words in the text colour; gray is "none
 * in particular". Teal never colours a badge, where it would read as green.
 */
export type Hue = 'cyan' | 'indigo' | 'pink' | 'violet' | 'teal' | 'gray';

/** The CSS value of a hue: its token, which turns to the text colour under high contrast. */
export const hueVar = (hue: Hue) => `var(--shutter-hue-${hue})`;

/** A board member's identity: its name, hue and avatar icon. */
export interface MemberIdentity {
  name: string;
  hue: Hue;
  icon: Icon;
}

/**
 * The board's members in their fixed order (Conformance, Encounter Integrity, Impact Analysis, Coordinator), never
 * cycled, the single investigator apart in gray; the board as a whole takes the coordinator's violet. A site's added
 * specialist takes gray until it is given a slot.
 */
export const MEMBERS: Record<string, MemberIdentity> = {
  conformance: { name: 'Conformance', hue: 'cyan', icon: IconFileCheck },
  encounter: { name: 'Encounter Integrity', hue: 'indigo', icon: IconTimeline },
  impact: { name: 'Impact Analysis', hue: 'pink', icon: IconAffiliate },
  coordinator: { name: 'Coordinator', hue: 'violet', icon: IconUsersGroup },
  generalist: { name: 'Single Investigator', hue: 'gray', icon: IconUser },
  board: { name: 'The board', hue: 'violet', icon: IconUsersGroup },
};

/** The specialists, in the order their dots and columns take. */
export const SPECIALISTS = ['conformance', 'encounter', 'impact'] as const;

/** A member's identity by its code, gray for one the app does not know. */
export const memberIdentity = (code: string, name?: string): MemberIdentity =>
  MEMBERS[code] ?? { name: name || code, hue: 'gray', icon: IconUser };

/** Who investigated a case, by run mode: the board violet, the site's policy teal, the others gray. */
export const MODE_IDENTITY: Record<string, { label: string; hue: Hue; icon: Icon }> = {
  board: { label: 'Board', hue: 'violet', icon: IconUsersGroup },
  policy: { label: 'Site policy', hue: 'teal', icon: IconFileDescription },
  single: { label: 'Single investigator', hue: 'gray', icon: IconUser },
  rules: { label: 'Rules only', hue: 'gray', icon: IconCode },
};

/**
 * A receiver category's mark (its words are categories.ts's): current state cyan, history of record indigo, and any
 * category Shutter does not model yet (orders and results) gray, with a dashed edge.
 */
export const CATEGORY_MARKS: Record<string, { hue: Hue; icon: Icon; dashed?: boolean }> = {
  current_state: { hue: 'cyan', icon: IconMapPin },
  history_of_record: { hue: 'indigo', icon: IconHistory },
};
export const categoryMark = (category: string) =>
  CATEGORY_MARKS[category] ?? { hue: 'gray' as Hue, icon: IconCircleDashed, dashed: true };

/** The site's own identity mark (the site profile's section). */
export const SITE_ICON = IconBuildingHospital;
