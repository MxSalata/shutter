import type { AgentRun } from '@/api/types';
import { formatInt } from '@/lib/format';
import { memberIdentity, SPECIALISTS } from '@/lib/hues';

/**
 * When each agent of a board pass worked, from the stored rows alone (CONTRACTS 9, "The run's own clock", v1.35): each
 * run's start and duration, and its tool calls' times. The picture is drawn only when the rows can carry it honestly:
 * every run has a start and a duration, and the coordinator, which reads the specialists' findings, starts no earlier
 * than the last of them ended. A pass whose clock contradicts itself fails that test, and then nothing is drawn rather
 * than a wrong picture.
 *
 * A replayed pass (every run a replay) is the one exception, drawn by its own rule (`replayedClock`): a replay calls no
 * model and answers at once, so its runs all start within the same moment, while each keeps the recording's duration
 * and, since v1.35, the recording's tool calls at their times moved with the run's start. Its starts say nothing about
 * the recording's pace, so they are not used: the specialists are drawn from 0, as the case workflow sends them their
 * requests together, and the coordinator from when the slowest of them ended, as the workflow waits for every answer
 * before it asks the coordinator. The picture says it is a replay with the times as recorded.
 */

/** A tool call on its run's bar, in milliseconds from the pass's first start. */
export interface ClockMark {
  seq: number;
  name: string;
  from: number;
  to: number;
  durationMs: number;
  /** The authorisation policy refused it before it ran (`denied`). */
  refused: boolean;
}

/** One run of the pass, in milliseconds from the pass's first start. */
export interface ClockRow {
  key: string;
  member: string;
  name: string;
  role: 'specialist' | 'coordinator';
  start: number;
  end: number;
  durationMs: number;
  /** The calls the run made, the ones the policy refused, and the marks of those whose times fit the run's bar. */
  calls: number;
  refused: number;
  marks: ClockMark[];
  llmMs?: number;
  toolMs?: number;
  reasoningTokens?: number;
}

export interface PassClock {
  /** The specialists in member order, then any other specialist, then the coordinator. */
  rows: ClockRow[];
  /** The pass's first start. */
  startedAt: string;
  /** From the first start to the last end. */
  totalMs: number;
  /** `ms` when every run carries its start to the millisecond; `s` when a start is to the second only. */
  precision: 'ms' | 's';
  /** How the specialists' runs lay against each other. */
  overlap: 'one' | 'together' | 'apart' | 'partly';
  /**
   * A replayed pass, drawn from the recording's durations and tool-call times as the workflow runs a pass, its own
   * starts left out (`replayedClock`); `startedAt` is then when the replay ran.
   */
  replayed: boolean;
}

/** How far a time may stray at each precision before the rows are taken to contradict each other. */
const TOLERANCE = { ms: 250, s: 1000 } as const;
/**
 * How far a replayed call may stray from its run's bar: a recording made before v1.35 kept its start to the second, and
 * the replay moved the recorded calls by the time from that start, so a call can sit up to a second late in its run.
 */
const REPLAY_TOLERANCE = 1000;

const timeOf = (iso: string | null | undefined): number | undefined => {
  if (!iso) return undefined;
  const t = Date.parse(iso);
  return Number.isFinite(t) ? t : undefined;
};

/** A counter from the run row: a number, or nothing when the build gave none (never read as zero). */
const counter = (v: number | null | undefined): number | undefined =>
  v === null || v === undefined || (v as unknown) === '' || !Number.isFinite(Number(v))
    ? undefined
    : Number(v);

/**
 * The investigation's runs: the case's agent runs without those that answered a question (Ask about this case), which
 * the server stores as the case's rows too (CONTRACTS 5 and 14). The board, the plan's provenance and the evidence's
 * citations read the investigation; a question's runs are the question's own.
 */
export function investigationRuns(runs: AgentRun[] | null | undefined): AgentRun[] {
  return (runs ?? []).filter((r) => !r.questionId);
}

/**
 * The runs of the board's latest pass: the last coordinator's, with the specialists that read the same snapshot (the
 * last run of each), Ask's runs left out. A pass with no coordinator yet has none.
 */
export function passRuns(runs: AgentRun[]): AgentRun[] {
  const investigation = investigationRuns(runs);
  const coordinators = investigation.filter((r) => r.role === 'coordinator');
  const coordinator = coordinators.at(-1);
  if (!coordinator) return [];
  const snapshot = coordinator.snapshotId;
  const pass =
    snapshot !== undefined && snapshot !== null && snapshot !== ''
      ? investigation.filter((r) => String(r.snapshotId) === String(snapshot))
      : // Without the snapshot the pass is known only when the case has had one
        coordinators.length === 1
        ? investigation
        : [];
  const last = new Map<string, AgentRun>();
  for (const r of pass) if (r.role === 'specialist') last.set(r.memberCode, r);
  return pass.length ? [...last.values(), coordinator] : [];
}

/** The specialists' order on the picture: Conformance, Encounter Integrity, Impact Analysis, then any other. */
const rank = (member: string) => {
  const i = (SPECIALISTS as readonly string[]).indexOf(member);
  return i < 0 ? SPECIALISTS.length : i;
};

/** The pass's clock, or null when the rows cannot draw it honestly. */
export function passClock(runs: AgentRun[] | null | undefined): PassClock | null {
  const pass = passRuns(runs ?? []);
  const specialists = pass.filter((r) => r.role === 'specialist');
  const coordinator = pass.find((r) => r.role === 'coordinator');
  if (!coordinator || !specialists.length) return null;
  if (pass.every((r) => r.mode === 'replay')) return replayedClock(pass);
  // Every start to the millisecond, or every start to the second: a replay's two stamps can come from two clocks
  const precise = pass.every((r) => timeOf(r.startedAtMs) !== undefined);
  const precision = precise ? 'ms' : 's';
  const tolerance = TOLERANCE[precision];
  const starts = pass.map((r) => timeOf(precise ? r.startedAtMs : r.startedAt));
  const durations = pass.map((r) => Number(r.durationMs));
  if (starts.some((t) => t === undefined) || durations.some((d) => !Number.isFinite(d) || d <= 0))
    return null;
  const first = Math.min(...(starts as number[]));
  const last = Math.max(...pass.map((_, i) => (starts[i] as number) + durations[i]));
  const ordered = pass
    .map((r, i) => ({ r, start: (starts[i] as number) - first, durationMs: durations[i] }))
    .sort((a, b) =>
      a.r.role === b.r.role
        ? rank(a.r.memberCode) - rank(b.r.memberCode)
        : a.r.role === 'coordinator'
          ? 1
          : -1,
    );
  const coordinatorStart = ordered.at(-1)!.start;
  const specialistsEnd = Math.max(...ordered.slice(0, -1).map((x) => x.start + x.durationMs));
  // The coordinator weighs the specialists' findings, so it cannot have started before the last of them ended
  if (coordinatorStart < specialistsEnd - tolerance) return null;

  const rows: ClockRow[] = ordered.map(({ r, start, durationMs }) => {
    const end = start + durationMs;
    const calls = r.toolCalls ?? [];
    // Marks only on a clock to the millisecond, and only when every call with a time fits inside its run's bar: the
    // row is written when the tool has answered, so a call ran from `at` minus its duration to `at`
    let marks: ClockMark[] = [];
    if (precise) {
      for (const call of calls) {
        const at = timeOf(call.at);
        if (at === undefined) continue;
        const took = Math.max(0, Number(call.durationMs) || 0);
        const to = at - first;
        const from = to - took;
        if (from < start - tolerance || to > end + tolerance) {
          marks = [];
          break;
        }
        marks.push({
          seq: call.seq,
          name: call.name,
          from: Math.max(start, from),
          to: Math.min(end, Math.max(to, from)),
          durationMs: took,
          refused: !!call.denied,
        });
      }
    }
    return rowOf(r, start, durationMs, marks);
  });

  // A run whose calls are not drawn would read as the model's time alone beside runs that show theirs: then no run has
  // marks, and the legend says why
  if (rows.some((r) => r.calls > 0 && !r.marks.length)) for (const r of rows) r.marks = [];

  return {
    rows,
    startedAt: new Date(first).toISOString(),
    totalMs: last - first,
    precision,
    overlap: overlapOf(rows, tolerance),
    replayed: false,
  };
}

/** How the specialists' bars lie against each other: one, together, one after another or partly together. */
function overlapOf(rows: ClockRow[], tolerance: number): PassClock['overlap'] {
  const specialistRows = rows.filter((r) => r.role === 'specialist');
  if (specialistRows.length < 2) return 'one';
  const latestStart = Math.max(...specialistRows.map((r) => r.start));
  const earliestEnd = Math.min(...specialistRows.map((r) => r.end));
  const byStart = [...specialistRows].sort((a, b) => a.start - b.start);
  const separate = byStart.every((r, i) => i === 0 || r.start >= byStart[i - 1].end - tolerance);
  return latestStart < earliestEnd ? 'together' : separate ? 'apart' : 'partly';
}

/** A row of the picture, from its run and where its bar lies. */
function rowOf(r: AgentRun, start: number, durationMs: number, marks: ClockMark[]): ClockRow {
  const calls = r.toolCalls ?? [];
  const identity = memberIdentity(r.memberCode, r.member?.name);
  return {
    key: String(r.id ?? r.memberCode),
    member: r.memberCode,
    name: r.role === 'coordinator' ? 'Coordinator' : (r.member?.name ?? identity.name),
    role: r.role === 'coordinator' ? 'coordinator' : 'specialist',
    start,
    end: start + durationMs,
    durationMs,
    calls: calls.length || Number(r.toolCallCount) || 0,
    refused: calls.filter((c) => c.denied).length,
    marks,
    llmMs: counter(r.llmMs),
    toolMs: counter(r.toolMs),
    reasoningTokens: counter(r.reasoningTokens),
  };
}

/**
 * A replayed pass as the recording ran it: each run for its recorded duration, the specialists from 0 and the
 * coordinator from the slowest specialist's end, as the case workflow runs a pass. A run's tool calls are drawn at
 * their times from its own start, which the replay moved together (v1.35), so only when every run has its start to the
 * millisecond, and only when every call fits its bar; otherwise the bars carry no marks. Null when a run has no
 * duration.
 */
function replayedClock(pass: AgentRun[]): PassClock | null {
  const durations = pass.map((r) => Number(r.durationMs));
  if (durations.some((d) => !Number.isFinite(d) || d <= 0)) return null;
  const ordered = pass
    .map((r, i) => ({ r, durationMs: durations[i] }))
    .sort((a, b) =>
      a.r.role === b.r.role
        ? rank(a.r.memberCode) - rank(b.r.memberCode)
        : a.r.role === 'coordinator'
          ? 1
          : -1,
    );
  const slowest = Math.max(...ordered.slice(0, -1).map((x) => x.durationMs));
  // The tool calls only when every run kept its start to the millisecond: the replay moved its calls with it
  const own = ordered.map(({ r }) => timeOf(r.startedAtMs));
  const precise = own.every((t) => t !== undefined);
  const rows = ordered.map(({ r, durationMs }, i) => {
    const start = r.role === 'coordinator' ? slowest : 0;
    let marks: ClockMark[] = [];
    if (precise) {
      for (const call of r.toolCalls ?? []) {
        const at = timeOf(call.at);
        if (at === undefined) continue;
        const took = Math.max(0, Number(call.durationMs) || 0);
        const to = at - (own[i] as number);
        const from = to - took;
        if (from < -REPLAY_TOLERANCE || to > durationMs + REPLAY_TOLERANCE) {
          marks = [];
          break;
        }
        // Within the tolerance, a call before its run's start or past its end is drawn at that edge of the bar
        const within = (t: number) => Math.min(durationMs, Math.max(0, t));
        marks.push({
          seq: call.seq,
          name: call.name,
          from: start + within(from),
          to: start + within(Math.max(to, from)),
          durationMs: took,
          refused: !!call.denied,
        });
      }
    }
    return rowOf(r, start, durationMs, marks);
  });
  if (rows.some((r) => r.calls > 0 && !r.marks.length)) for (const r of rows) r.marks = [];
  const starts = pass
    .map((r) => timeOf(r.startedAtMs) ?? timeOf(r.startedAt))
    .filter((t): t is number => t !== undefined);
  const coordinator = rows.at(-1)!;
  return {
    rows,
    startedAt: starts.length ? new Date(Math.min(...starts)).toISOString() : '',
    totalMs: coordinator.end,
    precision: 'ms',
    overlap: overlapOf(rows, TOLERANCE.ms),
    replayed: true,
  };
}

/** How a replayed pass is drawn, in Technical's words (`passClock`, `replayedClock`). */
export const REPLAYED_WORDS =
  "A replay calls no model and answers at once, so its own starts are left out. Each bar is the recorded run's duration and each mark a recorded tool call at its time in that run, to within a second, since a recording made before v1.35 kept its start to the second. The specialists are drawn from 0, as the case workflow sends them their requests together, and the coordinator from when the slowest of them ended, as the workflow waits for every finding before it asks the coordinator.";

/** Small counts in words, as the board's note says them. */
const COUNTS: Record<number, string> = { 2: 'two', 3: 'three', 4: 'four', 5: 'five' };

/** "24 s" for the pass as a whole: whole seconds from 10 s, one decimal below, minutes past one. */
export function passSeconds(ms: number): string {
  if (ms >= 60_000) return `${Math.floor(ms / 60_000)} min ${Math.round((ms % 60_000) / 1000)} s`;
  return ms >= 10_000 ? `${Math.round(ms / 1000)} s` : `${(ms / 1000).toFixed(1)} s`;
}

/** "11.2 s" for a part of a run, "17 ms" below a tenth of a second. */
export function partSeconds(ms: number): string {
  return ms < 100 ? `${Math.round(ms)} ms` : `${(ms / 1000).toFixed(1)} s`;
}

/** A start on the axis, as precise as the clock: "14.6 s" to the millisecond, "16 s" to the second. */
export function offsetSeconds(ms: number, precision: PassClock['precision']): string {
  return precision === 'ms' ? `${(ms / 1000).toFixed(1)} s` : `${Math.round(ms / 1000)} s`;
}

/** The specialists as the sentence names them: "The specialist", "The three specialists". */
function specialistsWord(n: number): string {
  return n === 1 ? 'The specialist' : `The ${COUNTS[n] ?? formatInt(n)} specialists`;
}

/** How they worked, as the sentence says it. */
const HOW: Record<PassClock['overlap'], string> = {
  one: 'worked first',
  together: 'worked at the same time',
  apart: 'worked one after another',
  partly: 'worked partly at the same time',
};

/**
 * The picture in Plain words: "The three specialists worked at the same time, then the coordinator wrote the plan. The
 * pass took 24 s." A replayed pass's time is the recording's: "... The recorded pass took 24 s."
 */
export function clockSentence(clock: PassClock): string {
  const n = clock.rows.filter((r) => r.role === 'specialist').length;
  const pass = clock.replayed ? 'The recorded pass' : 'The pass';
  return `${specialistsWord(n)} ${HOW[clock.overlap]}, then the coordinator wrote the plan. ${pass} took ${passSeconds(clock.totalMs)}.`;
}

/** The picture's name for a screen reader, in one sentence. */
export function clockLabel(clock: PassClock): string {
  const n = clock.rows.filter((r) => r.role === 'specialist').length;
  const how = HOW[clock.overlap].replace(/^worked /, '');
  const what = `${specialistsWord(n).toLowerCase()} ${how}, then the coordinator`;
  if (clock.replayed)
    return `When each agent worked, replayed with the times as recorded: ${what}; the recorded pass took ${passSeconds(clock.totalMs)}.`;
  return `When each agent worked: ${what}; the pass took ${passSeconds(clock.totalMs)}.`;
}

/** A row's figures when AI Hub gave no counter for its run. */
export const NO_FIGURES = 'timings as recorded';

/**
 * A row's split in Technical: "model 11.2 s, tools 0.8 s, 1,240 reasoning tokens" from AI Hub's counters, those it
 * gave; "timings as recorded" when it gave none (a replay, or a build without them).
 */
export function rowFigures(row: ClockRow): string {
  const parts = [
    row.llmMs !== undefined ? `model ${partSeconds(row.llmMs)}` : '',
    row.toolMs !== undefined ? `tools ${partSeconds(row.toolMs)}` : '',
    row.reasoningTokens !== undefined ? `${formatInt(row.reasoningTokens)} reasoning tokens` : '',
  ].filter(Boolean);
  return parts.length ? parts.join(', ') : NO_FIGURES;
}
