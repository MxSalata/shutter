import {
  IconBooks,
  IconBuildingHospital,
  IconChartBar,
  IconClipboardSearch,
  IconFlask2,
  IconHeartbeat,
  IconListDetails,
  IconSettings,
  IconStack2,
} from '@tabler/icons-react';
import { useCases } from '@/api/hooks';
import type { Hue } from '@/lib/hues';

/** The navigation's hues: each section's identity (DESIGN.md 2.5), never a status colour. */
export type NavHue = Exclude<Hue, 'gray'>;

export interface SectionItem {
  to: string;
  label: string;
  icon: typeof IconFlask2;
  hue: NavHue;
  /** The count of cases that need a person stands beside it. */
  count?: true;
  /** What the section is for, for the Home page: one sentence of at most 15 words, close to its page's own lead. */
  about: string;
}

export interface SectionGroup {
  group: 'Operate' | 'Results' | 'Configure';
  /** What a visit to the group is for, for the Home page. */
  about: string;
  items: SectionItem[];
}

/**
 * The app's sections in three groups, by what a visit is for: running and following the recovery, the results that show
 * whether it works, and configuring it. The navigation shows the short labels and the Home page adds what each is for,
 * from this one list, so a section cannot be in one and missing from the other. Each entry's icon carries its section's
 * hue, the same on its page's header.
 */
export const SECTIONS: SectionGroup[] = [
  {
    group: 'Operate',
    about: 'Run the recovery and follow it.',
    items: [
      {
        to: '/scenarios',
        label: 'Scenarios',
        icon: IconFlask2,
        hue: 'cyan',
        about: 'Known failures replayed, to show what Shutter does and who decides.',
      },
      {
        to: '/cases',
        label: 'Cases',
        icon: IconListDetails,
        hue: 'indigo',
        count: true,
        about: 'Each failed delivery: what happened, the plan, who decided and what was written.',
      },
      {
        to: '/incidents',
        label: 'Incidents',
        icon: IconStack2,
        hue: 'pink',
        about: 'Many failures to one receiver, handled together and released in order.',
      },
      {
        to: '/reviews',
        label: 'Production review',
        icon: IconClipboardSearch,
        hue: 'violet',
        about: "A read-only check of a production's settings and recent errors, tied to the cases.",
      },
    ],
  },
  {
    group: 'Results',
    about: 'See whether it works.',
    items: [
      {
        to: '/evaluation',
        label: 'Evaluation',
        icon: IconChartBar,
        hue: 'teal',
        about: 'How the board decides, measured on runs recorded with the real agents.',
      },
      {
        to: '/health',
        label: 'Health',
        icon: IconHeartbeat,
        hue: 'indigo',
        about: 'The installation checks itself: its message engine, web pages, agents and licence.',
      },
    ],
  },
  {
    group: 'Configure',
    about: 'Say how it behaves at this site.',
    items: [
      {
        to: '/site-profile',
        label: 'Site profile',
        icon: IconBuildingHospital,
        hue: 'teal',
        about: "This hospital's answers: they decide what Shutter may do at each receiver.",
      },
      {
        to: '/library',
        label: 'Agent library',
        icon: IconBooks,
        hue: 'violet',
        about: 'What each agent on the board is told, and the questions it answers.',
      },
      {
        to: '/settings',
        label: 'Settings and costs',
        icon: IconSettings,
        hue: 'cyan',
        about: 'How the agents answer, the prices used for costs, and what was spent.',
      },
    ],
  },
];

/** The cases that need a person: waiting for an approval, escalated or blocked, as the Cases page's tiles count them. */
const NEED_A_PERSON = ['awaiting_approval', 'escalated', 'blocked'] as const;

/** How many cases need a person, from the same queries as the Cases page's tiles; null while any is still loading. */
export function useNeedAPerson(): number | null {
  const a = useCases({ state: NEED_A_PERSON[0], limit: 1 });
  const b = useCases({ state: NEED_A_PERSON[1], limit: 1 });
  const c = useCases({ state: NEED_A_PERSON[2], limit: 1 });
  if (!a.data || !b.data || !c.data) return null;
  return a.data.total + b.data.total + c.data.total;
}
