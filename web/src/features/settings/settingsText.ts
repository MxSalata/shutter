import type { AgentItem, Costs, ModelPrice, Settings } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { formatUsd, humanize, plural } from '@/lib/format';
import { MEMBERS } from '@/lib/hues';
import { PROOF, type Proof } from '@/lib/proof';
import { PROVENANCE } from '@/lib/status';
import type { Status } from '@/lib/tone';

/**
 * The words of the Settings and costs page, apart from the page: how the agents answer, who each item is, the costs
 * sentence, the price source in short and the by-case summary. Pure, so each is tested on its own.
 */

/** How the page's agents answer as a whole. */
export type Answering = 'replay' | 'live' | 'record' | 'mimic' | 'mixed' | 'other';

/** The agents of the instance: the production items that run an agent and are switched on. */
export const agentsOf = (s: Pick<Settings, 'agentItems'>): AgentItem[] =>
  s.agentItems.filter((a) => a.agentClass && a.enabled !== false);

/** The mode an item answers in now: what `auto` resolved to, else the mode as set. */
export const effectiveModeOf = (a: AgentItem): string => a.effectiveMode || a.mode || '';

/**
 * How the instance's agents answer, from the modes they run in now. Under the API mimic (a test fixture) a live item is
 * still live, but no model answers it. Different modes, or none, read as `mixed`.
 */
export function answeringOf(s: Pick<Settings, 'agentItems' | 'mock'>): { kind: Answering; mode: string } {
  const modes = [...new Set(agentsOf(s).map(effectiveModeOf))];
  if (modes.length !== 1) return { kind: 'mixed', mode: '' };
  const mode = modes[0];
  if (mode === 'replay') return { kind: 'replay', mode };
  if (mode === 'live') return { kind: s.mock ? 'mimic' : 'live', mode };
  if (mode === 'record') return { kind: 'record', mode };
  return { kind: 'other', mode };
}

/**
 * Whether the spent tile reads as a replay: the trial, where every answer is one, or an instance whose agents all replay
 * and that has spent nothing. An instance that replays now but spent on real runs before reads as spending.
 */
export function replayTile(s: Settings | undefined, spent: number | undefined): boolean {
  if (TRIAL) return true;
  return !!s && answeringOf(s).kind === 'replay' && !(spent && spent > 0);
}

/**
 * The Agents section's sentence when the agents do not replay (today's, kept): how many and how they answer. A
 * replaying instance has its own sentence, `replayIntro`.
 */
export function agentsSentence(s: Settings): string {
  const agents = agentsOf(s);
  const { kind, mode } = answeringOf(s);
  const how =
    kind === 'mimic'
      ? 'running live against the API mimic (tests/mock): no model is called and the runs cost nothing'
      : kind === 'live'
        ? 'running live on the configured model provider'
        : kind === 'record'
          ? 'running live and recording each run'
          : kind === 'replay'
            ? 'replaying recorded runs'
            : kind === 'other'
              ? humanize(mode).toLowerCase()
              : 'in different modes, as the table shows';
  return `${agents.length} ${s.aiHubPresent ? 'AI Hub ' : ''}${agents.length === 1 ? 'agent' : 'agents'}, ${how}`;
}

/**
 * What a replaying instance says about where its answers come from (F3, N7): the build of IRIS AI Hub and the models
 * of the runs the replays reuse, from the evaluation. The pieces the document cannot give are left out.
 */
export function replayFacts(proof: Pick<Proof, 'recordedOn' | 'models'> = PROOF): {
  build: string | null;
  models: string[];
} {
  return { build: proof.recordedOn?.number ?? null, models: proof.models };
}

/** The badge in the Agents section's header: how the agents answer, in words a newcomer reads. */
export function answeringBadge(kind: Answering): Status | null {
  switch (kind) {
    case 'replay':
      return {
        tone: 'neutral',
        label: 'Replay',
        hint: 'Each answer is a run recorded with the real agents; no model is called now',
        icon: PROVENANCE.replay.icon,
      };
    case 'live':
      return { tone: 'info', label: 'Runs with real agents', icon: PROVENANCE.live.icon };
    case 'record':
      return { tone: 'info', label: 'Records real runs', icon: PROVENANCE.live.icon };
    case 'mimic':
      return { tone: 'neutral', label: 'API mimic', icon: PROVENANCE.rules.icon };
    case 'mixed':
      return { tone: 'neutral', label: 'Mixed modes' };
    default:
      return null;
  }
}

/** One item's badge: its mode now, from the provenance vocabulary (live info, replay neutral). */
export function itemBadge(a: AgentItem, mock: boolean): Status {
  if (a.enabled === false)
    return { tone: 'neutral', label: 'Disabled', hint: 'Switched off in the production' };
  const mode = effectiveModeOf(a);
  if (mode === 'replay')
    return {
      tone: 'neutral',
      label: 'Replay',
      hint: PROVENANCE.replay.hint,
      icon: PROVENANCE.replay.icon,
    };
  if (mode === 'live' && mock)
    return {
      tone: 'neutral',
      label: 'API mimic',
      hint: 'No model is called: the API mimic answers',
      icon: PROVENANCE.rules.icon,
    };
  if (mode === 'live') return { ...PROVENANCE.live, label: 'Live' };
  if (mode === 'record')
    return {
      tone: 'info',
      label: 'Recording',
      hint: 'Runs live and records each run',
      icon: PROVENANCE.live.icon,
    };
  return { tone: 'neutral', label: mode ? humanize(mode) : 'Not set' };
}

/** Who an item is: its board member's code (for the hue and the icon) and the name to show beside it. */
export function memberOfItem(a: AgentItem): { code: string; name: string } {
  const last = a.agentClass?.split('.').pop()?.toLowerCase();
  if (last && MEMBERS[last]) return { code: last, name: MEMBERS[last].name };
  if (a.agentClass) return { code: last ?? 'agent', name: humanize(last) };
  // The board's runner has no agent class of its own: the one gray row
  return { code: 'runner', name: `${a.name.replace(/^Agent\s+/, '')} (runner)` };
}

/** How a run was made, in a word: no "live" inside the trial, where every answer is a recording. */
export function runWord(mode: string | undefined): string {
  if (mode === 'replay') return 'replayed';
  if (mode === 'record') return 'recorded';
  if (mode === 'live') return TRIAL ? 'real' : 'live';
  return mode ?? '';
}

type Totals = NonNullable<Costs['totals']>;

/**
 * The costs in sentences: what was spent (in the trial, "spent here" with every answer a replay; elsewhere, on how
 * many live runs), what the replays cost, the runs against the API mimic, and the production reviews' agent runs,
 * listed apart. The first sentence's figure is bold on the page, so it comes back apart from its sentence.
 */
export function costsSentences(t: Totals, trial: boolean): { spent: string; rest: string } {
  const spent = formatUsd(t.spentUsd);
  const parts = [
    trial ? ' spent here: every answer is a replay.' : ` spent on ${plural(t.liveRuns, 'live agent run')}.`,
  ];
  if (t.replayedRuns)
    parts.push(
      `${plural(t.replayedRuns, 'replayed run')} ${t.replayedRuns === 1 ? 'costs' : 'cost'} nothing.`,
    );
  if (t.mockRuns)
    parts.push(
      `${plural(t.mockRuns, 'run')} against the API mimic ${t.mockRuns === 1 ? 'costs' : 'cost'} nothing, since no model answered ${t.mockRuns === 1 ? 'it' : 'them'}.`,
    );
  if (t.reviewRuns)
    parts.push(
      `The production reviews' agent answered ${t.reviewRuns} ${t.reviewRuns === 1 ? 'time' : 'times'}, listed apart below.`,
    );
  return { spent, rest: parts.join(' ') };
}

const MONTHS = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];

/** "16 Oct 2026" for a stored "2026-10-16"; anything else as it came. */
export function dayWords(day: string): string {
  const m = /^(\d{4})-(\d{2})-(\d{2})/.exec(day);
  return m ? `${Number(m[3])} ${MONTHS[Number(m[2]) - 1] ?? m[2]} ${m[1]}` : day;
}

/** A price's source in full, as stored: its text, with its date when the text does not carry it. */
export const fullSource = (p: Pick<ModelPrice, 'source' | 'asOf'>): string =>
  p.asOf && !p.source.includes(p.asOf) ? `${p.source} (${p.asOf})` : p.source;

/**
 * A price's source in short: "List price, read 16 Oct 2026" for the providers' list prices, which every stored source
 * says at length; any other source as it was stored.
 */
export function shortSource(p: Pick<ModelPrice, 'source' | 'asOf'>): string {
  if (!/list price/i.test(p.source)) return fullSource(p);
  return p.asOf ? `List price, read ${dayWords(p.asOf)}` : 'List price';
}

/** The distinct stored sources with the models each prices, in the order they first appear. */
export function sourcesOf(
  prices: Pick<ModelPrice, 'model' | 'source' | 'asOf'>[],
): { source: string; models: string[] }[] {
  const by = new Map<string, string[]>();
  for (const p of prices) by.set(fullSource(p), [...(by.get(fullSource(p)) ?? []), p.model]);
  return [...by].map(([source, models]) => ({ source, models }));
}

type CaseRow = Costs['byCase'][number];

/** "a, b and c". */
const joinAnd = (words: string[]): string =>
  words.length < 2 ? words.join('') : `${words.slice(0, -1).join(', ')} and ${words[words.length - 1]}`;

/**
 * One line for the cases when they are alike, so the table need not be read to learn it: every case replayed (or
 * none) at the same cost, with the usual number of runs and at most three cases that have another. "Every case (15):
 * 4 runs each, all replayed, $0.00, except C-000007 (8 runs)". Null when the cases differ more than that, or when
 * there are fewer than two: the table itself then shows them.
 */
export function sameCases(rows: CaseRow[]): string | null {
  if (rows.length < 2) return null;
  const replays = (r: CaseRow) => {
    const n = r.replayedRuns ?? 0;
    return n === 0 ? 'none' : n === r.runs ? 'all' : 'some';
  };
  const first = rows[0];
  const how = replays(first);
  if (how === 'some') return null;
  if (!rows.every((r) => replays(r) === how && formatUsd(r.costUsd) === formatUsd(first.costUsd)))
    return null;
  const counts = new Map<number, number>();
  for (const r of rows) counts.set(r.runs, (counts.get(r.runs) ?? 0) + 1);
  const usual = [...counts].sort((a, b) => b[1] - a[1] || a[0] - b[0])[0][0];
  const others = rows.filter((r) => r.runs !== usual);
  if (others.length > 3) return null;
  const except = others.length
    ? `, except ${joinAnd(others.map((r) => `${r.caseId} (${plural(r.runs, 'run')})`))}`
    : '';
  return `Every case (${rows.length}): ${plural(usual, 'run')} each, ${how === 'all' ? 'all' : 'none'} replayed, ${formatUsd(first.costUsd)}${except}`;
}

/** The board pass's cost range: "$0.34 to $0.50", or one figure when both round the same. */
export function costRange(min: number, max: number): string {
  const a = formatUsd(min);
  const b = formatUsd(max);
  return a === b ? a : `${a} to ${b}`;
}
