import type { IncidentDetail, IncidentEvent } from '@/api/types';

/** The words the workflow's error starts with when it could not raise an approval task and waits for a person. */
export const NO_TASK = 'No approval task could be raised for ';

/** An approval task that could not be raised and is still not there: the incident's shared one (seq null) or a chain's. */
export interface TaskNotRaised {
  seq: number | null;
  text: string;
}

/** How many of the errors the banner quotes; the rest are on the timeline. */
export const QUOTED = 3;

/**
 * The approval tasks the timeline says could not be raised and that the incident still lacks, each with its latest
 * error, the shared one first and then by chain. A task is found by the subject the workflow gives it: "Shutter <id>:"
 * for the shared one, "Shutter <id>/<seq>:" for a chain's own. A closed incident waits for nobody.
 */
export function tasksNotRaised(inc: IncidentDetail, events: IncidentEvent[]): TaskNotRaised[] {
  if (inc.state === 'closed') return [];
  const latest = new Map<string, TaskNotRaised>();
  for (const e of events) {
    if (e.kind !== 'error' || !e.text.startsWith(NO_TASK)) continue;
    const chain = /^chain (\d+) of incident /.exec(e.text.slice(NO_TASK.length));
    const seq = chain ? Number(chain[1]) : null;
    latest.set(String(seq), { seq, text: e.text });
  }
  return [...latest.values()]
    .filter(({ seq }) => {
      const prefix = `Shutter ${inc.incidentId}${seq === null ? '' : `/${seq}`}:`;
      return !inc.tasks.some((t) => t.subject.startsWith(prefix));
    })
    .sort((a, b) => (a.seq ?? 0) - (b.seq ?? 0));
}

function numbers(seqs: number[]): string {
  const shown = seqs.length > 5 ? seqs.slice(0, 5) : seqs;
  const rest = seqs.length - shown.length;
  if (rest) return `${shown.join(', ')} and ${rest} more`;
  if (shown.length === 1) return String(shown[0]);
  return `${shown.slice(0, -1).join(', ')} and ${shown[shown.length - 1]}`;
}

/** The banner's title: who is waiting for a person, naming each chain whose own task is missing. */
export function notRaisedTitle(missing: TaskNotRaised[]): string {
  const shared = missing.some((m) => m.seq === null);
  const seqs = missing.flatMap((m) => (m.seq === null ? [] : [m.seq]));
  if (!seqs.length) return 'This incident is waiting for a person';
  const chains = `${seqs.length === 1 ? 'chain' : 'chains'} ${numbers(seqs)}`;
  if (shared) return `This incident and its ${chains} are waiting for a person`;
  const Chains = chains.charAt(0).toUpperCase() + chains.slice(1);
  return `${Chains} of this incident ${seqs.length === 1 ? 'is' : 'are'} waiting for a person`;
}
