import type { ScreenContext } from '@/api/types';

/**
 * What the Ask Shutter panel sends with a question about a page: the page's name and a short structured summary of what is
 * in view, ids and labels only, built from the page itself (the main region's heading, its lead, its section headings and
 * the things it links to by id), never from the server. The server holds the summary to the same limits
 * (Shutter.Util.PageQuestion: plain keys, three levels, forty entries in one place, texts of 200 characters, 4000 characters
 * in all), so these caps keep every summary inside them.
 */

/** The longest summary, in characters of its JSON as the server measures it (summarySize), under the server's 4000. */
export const CONTEXT_MAX_CHARS = 3600;

/**
 * A summary's size as the server counts it (Shutter.Util.PageQuestion.AsData): its JSON, with each &, < and > written as
 * a six-character \u escape, so a page full of "A&E" labels is measured as the server will measure it.
 */
export function summarySize(summary: object): number {
  const json = JSON.stringify(summary);
  return json.length + 5 * (json.match(/[&<>]/g)?.length ?? 0);
}
/** The most items in one list, the server's limit. */
export const MAX_ITEMS = 40;
/** The longest text, the server's limit. */
export const MAX_TEXT = 200;
/** The most section headings kept. */
export const MAX_HEADINGS = 20;

/** The ids a page shows and the panel may cite: a case, an incident, a production review, a scenario, a question. */
const ID = /\b(C-\d{6}|I-\d{6}|PR-\d{6}|Q-\d{6}|S\d{1,2}[a-z]?)\b/;

const KINDS: [RegExp, string][] = [
  [/^C-/, 'case'],
  [/^I-/, 'incident'],
  [/^PR-/, 'review'],
  [/^Q-/, 'question'],
  [/^S/, 'scenario'],
];

export interface ScreenItem {
  id: string;
  kind: string;
  label: string;
}

/** The summary's shape: one level of texts and lists of items with an id, a kind and a label. */
export interface ScreenSummary extends ScreenContext {
  title: string;
  lead?: string;
  headings: string[];
  items: ScreenItem[];
}

/**
 * The page's name for the server (a lower-case word with hyphens): the first segment of the path, singular for a detail
 * page (a case, an incident, a review), `home` for the root.
 */
export function pageNameOf(pathname: string): string {
  const parts = pathname.split('/').filter(Boolean);
  const first = (parts[0] ?? 'home').toLowerCase().replace(/[^a-z0-9-]/g, '');
  if (!first) return 'home';
  if (parts.length > 1) {
    if (first === 'cases') return 'case';
    if (first === 'incidents') return 'incident';
    if (first === 'reviews') return 'review';
  }
  return first.slice(0, 40);
}

/** One text of the summary: whitespace folded, cut at the server's limit. */
const text = (s: string | null | undefined): string =>
  (s ?? '').replace(/\s+/g, ' ').trim().slice(0, MAX_TEXT);

/** Whether a node is part of the page, not of the panel (beside it or as a drawer), the guide's card or a hidden template. */
function onPage(el: Element): boolean {
  return !el.closest(
    '#ask-panel, .assistant-aside, [role="dialog"], [data-guide-card], [data-guide-dock], [aria-hidden="true"], template',
  );
}

const kindOf = (id: string) => KINDS.find(([re]) => re.test(id))?.[1] ?? 'id';

/**
 * The summary of what is on the screen, from the page's own markup: the h1 as the title, the first paragraph as the lead,
 * the h2 and h3 headings, and each link whose text or address names an id, as `{id, kind, label}`, once per id. Nothing
 * else is read: no table cell, no form value, no text of the page beyond those. Capped at CONTEXT_MAX_CHARS, items first
 * and headings next dropped from the end until it fits.
 */
export function summariseScreen(root: ParentNode | null | undefined, page: string): ScreenSummary {
  const summary: ScreenSummary = { page, title: '', headings: [], items: [] };
  if (!root) return summary;
  const h1 = Array.from(root.querySelectorAll('h1')).find(onPage);
  summary.title = text(h1?.textContent);
  const lead = Array.from(root.querySelectorAll('p')).find(
    (p) => onPage(p) && text(p.textContent).length >= 20,
  );
  if (lead) summary.lead = text(lead.textContent);
  const headings = new Set<string>();
  for (const h of Array.from(root.querySelectorAll('h2, h3'))) {
    if (!onPage(h)) continue;
    const t = text(h.textContent);
    if (t) headings.add(t);
    if (headings.size >= MAX_HEADINGS) break;
  }
  summary.headings = [...headings];
  const seen = new Set<string>();
  for (const a of Array.from(root.querySelectorAll('a[href]'))) {
    if (!onPage(a)) continue;
    const label = text(a.textContent);
    const id = ID.exec(label)?.[1] ?? ID.exec(decodeURIComponent(a.getAttribute('href') ?? ''))?.[1];
    if (!id || seen.has(id)) continue;
    seen.add(id);
    summary.items.push({ id, kind: kindOf(id), label: label || id });
    if (summary.items.length >= MAX_ITEMS) break;
  }
  return fitted(summary);
}

/** The summary cut to its length: items from the end, then headings, then the lead. */
export function fitted(summary: ScreenSummary): ScreenSummary {
  const out: ScreenSummary = { ...summary, headings: [...summary.headings], items: [...summary.items] };
  const size = () => summarySize(out);
  while (size() > CONTEXT_MAX_CHARS && out.items.length) out.items.pop();
  while (size() > CONTEXT_MAX_CHARS && out.headings.length) out.headings.pop();
  if (size() > CONTEXT_MAX_CHARS) delete out.lead;
  if (size() > CONTEXT_MAX_CHARS) out.title = out.title.slice(0, 40);
  return out;
}
