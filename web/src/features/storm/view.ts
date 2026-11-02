import type { LiveStorm, StormPatient } from '@/api/types';
import { isApiError } from '@/lib/errors';
import { formatTime, parseTime, plural, zoneLabel } from '@/lib/format';
import type { Tone } from '@/lib/tone';

/**
 * "Break the feed" (CONTRACTS 4.4, v1.35): what the live hospital's storm record says, in the strip's words, and what a
 * refusal of the press says. Pure, so the banner, the Incidents page and the tests read one rule.
 */

/** "Ward A" for the demo hospital's `WARD-A`; any other code as it is. */
export function wardLabel(code: string | undefined | null): string {
  if (!code) return '';
  const m = /^ward[-_ ]?(.+)$/i.exec(code.trim());
  return m ? `Ward ${m[1]}` : code;
}

/** "Ward A to Ward C", or the first ward alone before the transfer is planned. */
export function patientWards(p: StormPatient): string {
  const from = wardLabel(p.ward);
  const to = wardLabel(p.toWard);
  return to && to !== from ? `${from} to ${to}` : from;
}

/** The storm's patients once the player has planned them; none while the press waits for the player. */
export function stormPatients(storm: LiveStorm): StormPatient[] {
  return Array.isArray(storm.patients) ? storm.patients : [];
}

export type StepKey = 'down' | 'cases' | 'incident' | 'release' | 'end';

/**
 * Where a step stands: passed, the one now playing, not reached yet, passed over (no incident was recorded, or the
 * storm failed before it), or the last step's two endings.
 */
export type StepStatus = 'done' | 'current' | 'pending' | 'skipped' | 'finished' | 'stopped';

export interface StormStep {
  key: StepKey;
  status: StepStatus;
  /** The step's words; a step not reached yet says what will happen, with no figures. */
  words: string;
  /** The current step's progress: "3 of 8 movements sent", "5 of 8 resolved". */
  detail?: string;
  /** Step 3's incident, which the strip links to. */
  incidentId?: string;
}

export interface StormView {
  steps: StormStep[];
  /** The current step's place, 0 to 4. */
  current: number;
  /** The step line: "Step 2 of 5: 8 deliveries failed; Shutter opened 8 cases". */
  line: string;
  /** The strip's status word and tone: playing (information), done (positive), stopped (blocking). */
  status: { tone: Tone; label: string };
}

const KEYS: StepKey[] = ['down', 'cases', 'incident', 'release', 'end'];

/** The words of a step not reached yet: what it will be, with no figure the record does not hold. */
const PENDING: Record<StepKey, string> = {
  down: 'The bed manager is down',
  cases: 'Deliveries fail; Shutter opens a case for each',
  incident: 'Grouped into one incident',
  release: 'The bed manager is back; releasing in order',
  end: 'Done',
};

/** The current step by the storm's state: the player's own, and Shutter's incident once its cases joined one. */
function currentStep(storm: LiveStorm): number {
  switch (storm.state) {
    case 'requested':
    case 'sending':
      return 0;
    case 'waiting_receiver':
      return storm.incidentId ? 2 : 1;
    case 'releasing':
      return 3;
    default:
      return 4;
  }
}

/** For a failed storm, which steps the record shows it reached. */
function reached(storm: LiveStorm, key: StepKey): boolean {
  switch (key) {
    case 'down':
      return (storm.sent ?? 0) > 0;
    case 'cases':
      return (storm.cases ?? 0) > 0;
    case 'incident':
      return !!storm.incidentId;
    case 'release':
      return !!storm.receiverUpAt;
    default:
      return true;
  }
}

/** The five steps, the current one and the step line, from the storm's record. */
export function stormView(storm: LiveStorm): StormView {
  const failed = storm.state === 'failed';
  const done = storm.state === 'done';
  const current = currentStep(storm);
  const movements = storm.movements ?? 8;
  const sent = storm.sent ?? 0;
  const cases = storm.cases ?? 0;
  const resolved = storm.resolved ?? 0;
  const steps = KEYS.map((key, i): StormStep => {
    let status: StepStatus;
    if (i === 4 && (failed || done)) status = failed ? 'stopped' : 'finished';
    else if (failed) status = reached(storm, key) ? 'done' : 'skipped';
    else if (i < current) status = key === 'incident' && !storm.incidentId ? 'skipped' : 'done';
    else if (i === current) status = 'current';
    else status = 'pending';
    const shown = status === 'done' || status === 'current' || status === 'finished' || status === 'stopped';
    if (!shown)
      return {
        key,
        status,
        words: key === 'incident' && status === 'skipped' && !failed ? 'No incident recorded' : PENDING[key],
      };
    switch (key) {
      case 'down':
        return {
          key,
          status,
          words: 'The bed manager is down',
          detail: status === 'current' ? `${sent} of ${plural(movements, 'movement')} sent` : undefined,
        };
      case 'cases':
        return {
          key,
          status,
          words: `${plural(sent, 'delivery', 'deliveries')} failed; Shutter opened ${plural(cases, 'case')}`,
        };
      case 'incident':
        return {
          key,
          status,
          words: `Grouped into incident ${storm.incidentId}`,
          incidentId: storm.incidentId ?? '',
        };
      case 'release':
        return {
          key,
          status,
          words: 'The bed manager is back; releasing in order',
          detail: status === 'current' ? `${resolved} of ${cases || movements} resolved` : undefined,
        };
      default:
        return {
          key,
          status,
          words: failed
            ? `Stopped: ${storm.error || 'the storm did not finish'}`
            : `Done: ${plural(cases, 'case')}, ${resolved} resolved`,
        };
    }
  });
  const now = steps[current];
  return {
    steps,
    current,
    line: `Step ${current + 1} of 5: ${now.words}`,
    status: failed
      ? { tone: 'blocking', label: 'Stopped' }
      : done
        ? { tone: 'positive', label: 'Done' }
        : { tone: 'info', label: 'Playing' },
  };
}

/** "04:12 GMT": when the next storm may start, as the app shows times (the feed's zone, named). */
export function cooldownTime(
  until: string | undefined,
  retryAfterSeconds?: number,
  now: number = Date.now(),
): string {
  const at =
    parseTime(until)?.toISOString() ??
    (retryAfterSeconds && retryAfterSeconds > 0
      ? new Date(now + retryAfterSeconds * 1000).toISOString()
      : '');
  if (!at) return '';
  return `${formatTime(at).slice(0, 5)} ${zoneLabel(at)}`;
}

/** A refusal of `POST /live/storm`: the live hospital is off, a storm plays, the cooldown, or no hospital here. */
export type StormRefusal =
  | { code: 'live_off' }
  | { code: 'storm_in_progress'; stormId?: string; state?: string }
  | { code: 'cooldown'; until?: string; retryAfterSeconds?: number }
  | { code: 'no_service' };

const text = (v: unknown) => (typeof v === 'string' && v ? v : undefined);

/** The refusal an error is (409 live_off, storm_in_progress or cooldown; 503 no_service), or null for any other error. */
export function stormRefusal(error: unknown): StormRefusal | null {
  if (!isApiError(error)) return null;
  const body = (error.body && typeof error.body === 'object' ? error.body : {}) as Record<string, unknown>;
  if (error.status === 409 && error.code === 'live_off') return { code: 'live_off' };
  if (error.status === 409 && error.code === 'storm_in_progress')
    return { code: 'storm_in_progress', stormId: text(body.stormId), state: text(body.state) };
  if (error.status === 409 && error.code === 'cooldown')
    return {
      code: 'cooldown',
      until: text(body.until),
      retryAfterSeconds: typeof body.retryAfterSeconds === 'number' ? body.retryAfterSeconds : undefined,
    };
  if (error.status === 503 && error.code === 'no_service') return { code: 'no_service' };
  return null;
}

/** A refusal in the banner's words: calm, one sentence, never an error. */
export function refusalWords(r: StormRefusal, now: number = Date.now()): string {
  switch (r.code) {
    case 'live_off':
      return 'The live hospital is off.';
    case 'storm_in_progress':
      return 'A storm is already playing; watch it here.';
    case 'cooldown': {
      const at = cooldownTime(r.until, r.retryAfterSeconds, now);
      return at ? `The next storm can start at ${at}.` : 'The next storm can start in a few minutes.';
    }
    default:
      return "The demo hospital isn't installed here.";
  }
}
