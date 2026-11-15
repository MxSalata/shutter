import type { SiteProfile, SiteReceiver } from '@/api/types';
import { diffProfiles } from '../profile';
import { QUESTIONS, answerText } from './fields';

/** What the Site profile page's band says of a draft handed over by Set up the site. */

export const SETUP_DRAFT_TITLE_ID = 'site-setup-draft-title';

/** One row of the band's table: a setting, its value in the version in force and its value in the draft. */
export interface DraftRow {
  setting: string;
  now: string;
  draft: string;
}

const said = (text: string) => text || 'not answered';

/** The paths of a receiver's change that the checklist's rows already say. */
const CHECKLIST_PATHS = new Set([
  'system',
  'category',
  'tier',
  'applies',
  'resend_timestamp',
  'cancels',
  'merges',
  'history_policy',
]);

/**
 * The draft's changes as rows. A receiver's checklist answers read side by side (the value in force, the value in the
 * draft, in the page's own words); a receiver added reads "not in the profile" on the left; any other change keeps the
 * review's own sentence.
 */
export function draftRows(base: SiteProfile, draft: SiteProfile): DraftRow[] {
  const rows: DraftRow[] = [];
  const before = new Map(base.receivers.map((r) => [r.name, r]));
  // A receiver whose own history policy was changed keeps the review's sentence for it
  const override = new Set<string>();
  for (const r of draft.receivers) {
    const was: SiteReceiver | undefined = before.get(r.name);
    if (was && was.history_policy !== r.history_policy) override.add(r.name);
    for (const q of QUESTIONS) {
      if (q.id === 'name') continue;
      const to = answerText(q, r);
      const from = was ? answerText(q, was) : '';
      if (was ? from === to : !to) continue;
      rows.push({
        setting: `${r.name || 'unnamed'}: ${q.short.toLowerCase()}`,
        now: was ? said(from) : 'not in the profile',
        draft: said(to),
      });
    }
  }
  for (const c of diffProfiles(base, draft)) {
    const of = draft.receivers.find((r) => c.text.startsWith(`${r.name || 'a receiver'}, `));
    if (of && CHECKLIST_PATHS.has(c.path) && !(c.path === 'history_policy' && override.has(of.name)))
      continue;
    rows.push({ setting: c.text, now: '', draft: '' });
  }
  return rows;
}
