import type { Budget, LiveStatus } from '@/api/types';
import { budgetText, resetsHourly } from '@/lib/budget';
import { humanize, keyLabel, plural } from '@/lib/format';
import type { Proof } from '@/lib/proof';
import type { Tone } from '@/lib/tone';

/**
 * The readiness report (Shutter.Setup.Doctor) in the order a reader asks: is it ready, what is not there and does it
 * matter, where is the detail. Everything here is pure: the verdict from the core checks, the groups, each row's mark
 * and tone, the licence sentence, the agents badge and the provenance list, so the page only draws them and a test
 * reads them without drawing anything.
 */
export type Report = Record<string, unknown>;

/** A value the report really sent: not missing, null or empty. */
export const sent = (v: unknown): boolean => v !== undefined && v !== null && v !== '';

// ---- the groups ----

export interface GroupDef {
  id: string;
  title: string;
  /** The report's keys in the order the group shows them. */
  keys: readonly string[];
}

/** The report's keys by group, in order; a key listed nowhere goes to the last group, "Other", so nothing is hidden. */
export const GROUPS: readonly GroupDef[] = [
  {
    id: 'production',
    title: 'Production',
    keys: [
      'interoperability',
      'production_class',
      'production_state',
      'ward_classes',
      'shutter_production',
      'production',
      'adt_in',
      'mode',
      'edition',
      'missing_items',
      'disabled_items',
    ],
  },
  {
    id: 'web-applications',
    title: 'Web applications',
    keys: ['api_webapp', 'ui_webapp', 'wards_webapp', 'webapps_checked'],
  },
  {
    id: 'credentials',
    title: 'Stored credentials',
    keys: ['credentials_ok', 'credentials_state', 'credentials_checked_at', 'credentials'],
  },
  {
    id: 'agents',
    title: 'Agents and AI Hub',
    keys: [
      'ai_hub_present',
      'aihub_runner',
      'board_members',
      'recordings',
      'mock_config',
      'provider',
      'wallet_secret',
      'provider_config',
    ],
  },
  {
    id: 'cases',
    title: 'Cases and housekeeping',
    keys: ['cases', 'working_cases', 'abandon_after_minutes', 'purge_task'],
  },
  {
    id: 'installation',
    title: 'Installation and licence',
    keys: ['namespace', 'version', 'installed_at', 'demo', 'license'],
  },
];

const OTHER: GroupDef = { id: 'other', title: 'Other', keys: [] };

/** The key that holds the report's provenance: never a row, it is the "Where this report comes from" list. */
const PROVENANCE_KEY = 'recorded';

/** The report's keys in words; any other key is humanized by `keyLabel`. */
const LABELS: Record<string, string> = {
  installed_at: 'Installed',
  demo: 'Demo installation',
  adt_in: 'ADT inbound folder',
  interoperability: 'Interoperability enabled in the namespace',
  production_class: 'Production class compiled',
  production_state: 'Production state',
  aihub_runner: 'AI Hub runner compiled',
  ai_hub_present: 'AI Hub installed',
  mock_config: 'API mimic setting',
  provider: 'Model provider configured',
  wallet_secret: 'Provider key in the wallet',
  provider_config: 'Provider configuration in the Config Store',
  recordings: 'Recorded agent runs',
  working_cases: 'Cases still in progress',
  abandon_after_minutes: 'Abandon allowed after (minutes)',
  license: 'Licence',
  api_webapp: 'REST API web application',
  ui_webapp: 'Web app (this page)',
  wards_webapp: 'Downstream system web application',
  webapps_checked: 'Web applications checked from',
  edition: 'Edition',
  missing_items: 'Missing items',
  disabled_items: 'Disabled items',
  credentials_ok: 'Stored credentials sign in',
  credentials_state: 'Credential check',
  credentials_checked_at: 'Credentials checked',
  credentials: 'Credentials tried',
  budget: 'Model budget',
  receivers: 'Receivers, as last read',
  receivers_ok: 'Every receiver read lately answered',
  watched_ok: 'Every watched namespace can be heard',
};

/** What to do when a stored credential no longer signs in (a rebuild that kept the data volume, a changed password). */
const CREDENTIALS_TODO =
  'A stored credential no longer signs in: run the install again (or Shutter.Setup.RefreshCredentialCache(1)), then GET /health?refresh=1 as an operator who may write, and reload.';
/** What to do when the Doctor's credential check threw instead of answering (credentials_state "error: ..."). */
const CREDENTIALS_ERROR_TODO =
  'The credential check could not run, so nothing is known about the stored credentials: read the error in the Credential check row, then GET /health?refresh=1 as an operator who may write, and reload.';

/** Whether the Doctor's credential check threw: it then answers credentials_ok true with the error as the state. */
const credentialCheckFailed = (report: Report) =>
  typeof report.credentials_state === 'string' && report.credentials_state.startsWith('error');

/** What to do about the install items the Doctor found missing, disabled, or on the wrong image. */
const MISSING_ITEMS_TODO = 'Run the install again: these items are missing from the production.';
const DISABLED_ITEMS_TODO = 'Enable these items in the production, or run the install again.';
const BROKEN_EDITION_TODO =
  'Run the install again on the matching image: the aihub module and AI Hub go together, or neither.';

// ---- the core checks and the verdict ----

interface CoreDef {
  key: string;
  /** The short label under the verdict. */
  label: string;
  /** A downstream-system check: core only on a demo installation. */
  demoOnly?: boolean;
  /** A check a report before v1.38 does not carry: core only when the report sends its key, never "not reported". */
  since138?: boolean;
  passes?: (v: unknown, report: Report) => boolean;
  /** What to do when it fails. */
  todo: (v: unknown, report: Report) => string;
}

/** The core checks, in the order the verdict lists them. */
const CORE: readonly CoreDef[] = [
  {
    key: 'interoperability',
    label: 'Interoperability on',
    todo: () => 'Enable Interoperability in the namespace, then reload.',
  },
  {
    key: 'production_class',
    label: 'Production compiled',
    todo: () => 'Compile the production class, then reload.',
  },
  {
    key: 'production_state',
    label: 'Running',
    passes: (v) => v === 'running',
    todo: (v) => `Start the production, then reload. It is ${String(v)}.`,
  },
  {
    key: 'api_webapp',
    label: 'API web app',
    todo: () => 'Create the REST API web application, then reload.',
  },
  {
    key: 'ui_webapp',
    label: 'UI web app',
    todo: () => 'Create the web application for this page, then reload.',
  },
  {
    key: 'ward_classes',
    label: 'Downstream classes',
    demoOnly: true,
    todo: () => "Load the downstream system's classes, then reload.",
  },
  {
    key: 'wards_webapp',
    label: 'Downstream web app',
    demoOnly: true,
    todo: () => "Create the downstream system's web application, then reload.",
  },
  {
    key: 'credentials_ok',
    label: 'Stored credentials sign in',
    since138: true,
    // A check that threw says nothing about the credentials, whatever credentials_ok says
    passes: (v, report) => v === true && !credentialCheckFailed(report),
    todo: (_v, report) => (credentialCheckFailed(report) ? CREDENTIALS_ERROR_TODO : CREDENTIALS_TODO),
  },
];

/** One core check the report sent, and how it stands. */
export interface CoreResult {
  key: string;
  label: string;
  passed: boolean;
  /** What to do, when it failed. */
  todo?: string;
  /** The group it belongs to. */
  group: string;
}

export type VerdictKind = 'ready' | 'attention' | 'not-ready' | 'not-reported';

export interface Verdict {
  kind: VerdictKind;
  tone: Tone;
  /** The verdict in a word, the hero's region name. */
  word: string;
  /** Every core check the report sent, in order. */
  results: CoreResult[];
  passed: number;
  failing: CoreResult[];
  /** Core checks the report did not send, which the count leaves out. */
  notSent: number;
  /** Whether the report says the production is running. */
  running: boolean;
  /** What the core checks do not cover and the report found wrong: a receiver not answering, a namespace that cannot be heard. */
  attention: Attention[];
}

// ---- the receivers and the watched namespaces ----

/** One receiver as the Doctor last saw it (Shutter.Util.ReceiverHealth): from what Shutter's own reads left, with no probe. */
export interface ReceiverReading {
  name: string;
  state: string;
  at: string;
  httpStatus: number | null;
  error: string;
  lastAnswerAt: string;
  lastFailureAt: string;
  failuresHour: number;
  incident: string;
}

/** The report's receivers as typed records: a field it did not send is empty. */
export function receiverReadings(value: unknown): ReceiverReading[] {
  if (!Array.isArray(value)) return [];
  const str = (v: unknown) => (typeof v === 'string' ? v : '');
  return value.map((v) => {
    const r = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>;
    return {
      name: str(r.name),
      state: str(r.state),
      at: str(r.at),
      httpStatus: typeof r.http_status === 'number' ? r.http_status : null,
      error: str(r.error),
      lastAnswerAt: str(r.last_answer_at),
      lastFailureAt: str(r.last_failure_at),
      failuresHour: typeof r.failures_hour === 'number' ? r.failures_hour : 0,
      incident: str(r.incident),
    };
  });
}

/** The states that say a receiver is in trouble, in words; answering, not_read and no_api are not among them. */
const TROUBLE: Record<string, (r: ReceiverReading) => string> = {
  no_answer: () => 'no answer',
  server_error: (r) => `server error, HTTP ${r.httpStatus ?? '?'},`,
  refused: (r) => `refused Shutter's sign-in, HTTP ${r.httpStatus ?? '?'},`,
  failing: (r) => (r.at ? failingSinceAnswer(r) : failedLately(r)),
};

/** Deliveries fail although the receiver's newest reading was an answer. */
function failingSinceAnswer(r: ReceiverReading): string {
  return `deliveries failing since it last answered at ${utcMinute(r.lastAnswerAt || r.at)}`;
}

/** Nothing has read this receiver, so its failures in the last hour are all that is known of it. */
function failedLately(r: ReceiverReading): string {
  const count =
    r.failuresHour === 1 ? '1 delivery' : r.failuresHour ? `${r.failuresHour} deliveries` : 'deliveries';
  const words = `${count} failed in the last hour`;
  if (!r.lastFailureAt) return words;
  return `${words}, ${r.failuresHour === 1 ? 'at' : 'the last at'} ${utcMinute(r.lastFailureAt)}`;
}

/** A receiver in one line: its state and when, when it last answered, and the incident that holds its failures. */
export function receiverLine(r: ReceiverReading): string {
  const word = TROUBLE[r.state]?.(r) ?? (r.state === 'answering' ? 'answered' : r.state.replace(/_/g, ' '));
  // A failing line carries its own times
  const failing = r.state === 'failing';
  const parts = [`${r.name}: ${word}${r.at && !failing ? ` at ${utcMinute(r.at)}` : ''}.`];
  if (r.lastAnswerAt && r.state !== 'answering' && !failing)
    parts.push(`Last answered ${utcMinute(r.lastAnswerAt)}.`);
  if (r.incident) parts.push(`Incident ${r.incident}.`);
  return parts.join(' ');
}

/** A problem's words in the hero, with its whole text in the Other group: a refused forward can run to 200 characters. */
const PROBLEM_WORDS = 20;
function clipped(problem: string): string {
  const words = problem.split(/\s+/);
  return words.length > PROBLEM_WORDS ? `${words.slice(0, PROBLEM_WORDS).join(' ')}...` : problem;
}

export interface Attention {
  key: 'receivers' | 'watched_namespaces';
  /** A receiver's state, for the hero's sentence. */
  state?: string;
  /** The line the hero lists, which names the receiver or the namespace. */
  line: string;
}

/**
 * What the report found wrong beyond the core checks. A dead receiver is not a fault in the installation, so `ok` and the
 * core checks stay as they are; but the page must not read as all clear while one is dead.
 */
export function attentionOf(report: Report): Attention[] {
  const out: Attention[] = [];
  for (const r of receiverReadings(report.receivers))
    if (TROUBLE[r.state]) out.push({ key: 'receivers', state: r.state, line: receiverLine(r) });
  if (Array.isArray(report.watched_namespaces))
    for (const v of report.watched_namespaces as Record<string, unknown>[]) {
      const problems = Array.isArray(v?.problems) ? (v.problems as unknown[]).map(String) : [];
      if (v?.ok !== false || !problems.length) continue;
      const more = problems.length > 1 ? ` (and ${problems.length - 1} more)` : '';
      out.push({
        key: 'watched_namespaces',
        line: `${String(v.namespace)}: ${clipped(problems[0])}${more}.`,
      });
    }
  return out;
}

/** How many of those the hero lists: a site that is down must not cost more words than the page has. The rest are counted. */
export const HERO_ATTENTION_LINES = 2;

const groupOf = (key: string) => GROUPS.find((g) => g.keys.includes(key))?.id ?? OTHER.id;

/**
 * The core checks that count on this report: five, the downstream system's two on a demo installation, and the stored
 * credentials on a report that carries the check (v1.38; the trial's recording predates it).
 */
const coreFor = (report: Report) =>
  CORE.filter((c) => (!c.demoOnly || report.demo === true) && (!c.since138 || c.key in report));

/**
 * Whether it is ready: every core check the report sent passes (Ready), any fails (Not ready), or it sent none of
 * them (Checks not reported). A key the report leaves out is left out of the count.
 */
export function verdictOf(report: Report): Verdict {
  const defs = coreFor(report);
  const results: CoreResult[] = defs
    .filter((c) => sent(report[c.key]))
    .map((c) => {
      const passed = c.passes ? c.passes(report[c.key], report) : report[c.key] === true;
      return {
        key: c.key,
        label: c.label,
        passed,
        todo: passed ? undefined : c.todo(report[c.key], report),
        group: groupOf(c.key),
      };
    });
  const failing = results.filter((r) => !r.passed);
  const attention = attentionOf(report);
  const kind: VerdictKind =
    results.length === 0
      ? 'not-reported'
      : failing.length
        ? 'not-ready'
        : attention.length
          ? 'attention'
          : 'ready';
  return {
    kind,
    tone: kind === 'ready' ? 'positive' : kind === 'not-ready' ? 'blocking' : 'attention',
    word:
      kind === 'ready'
        ? 'Ready'
        : kind === 'attention'
          ? 'Needs a look'
          : kind === 'not-ready'
            ? 'Not ready'
            : 'Checks not reported',
    results,
    passed: results.length - failing.length,
    failing,
    notSent: defs.length - results.length,
    running: results.some((r) => r.key === 'production_state' && r.passed),
    attention,
  };
}

const needsLook = (trial: boolean, verb: 'needs' | 'need') => `${trial ? 'needed' : verb} a look`;

/**
 * The hero's statement. Live it speaks of this installation; in the trial it is a recording of another one, so it is
 * in the past tense and says which ("The recorded instance was ready").
 */
export function verdictStatement(v: Verdict, trial: boolean): string {
  const of = `${v.passed} of ${v.results.length}`;
  if (v.kind === 'ready') {
    const engine = v.running
      ? trial
        ? 'its message engine was running and every core check passed'
        : 'the message engine is running and every core check passes'
      : trial
        ? 'every core check passed'
        : 'every core check passes';
    return trial ? `The recorded instance was ready: ${engine} (${of}).` : `Ready: ${engine} (${of}).`;
  }
  if (v.kind === 'attention') {
    const troubled = v.attention.filter((a) => a.key === 'receivers');
    const receivers = troubled.length;
    const namespaces = v.attention.length - receivers;
    // A 401, a 503 or a failed delivery is not silence: only a receiver that gave no answer is said to give none
    const silent = troubled.every((a) => a.state === 'no_answer');
    const parts: string[] = [];
    if (receivers === 1)
      parts.push(
        `a receiver ${silent ? `${trial ? 'was' : 'is'} not answering` : needsLook(trial, 'needs')}`,
      );
    if (receivers > 1)
      parts.push(
        `${receivers} receivers ${silent ? `${trial ? 'were' : 'are'} not answering` : needsLook(trial, 'need')}`,
      );
    if (namespaces === 1) parts.push(`a watched namespace ${trial ? 'had' : 'has'} a problem`);
    if (namespaces > 1) parts.push(`${namespaces} watched namespaces ${trial ? 'had' : 'have'} a problem`);
    return `${trial ? 'The recorded instance was running' : 'Running'}, but ${parts.join(' and ')}.`;
  }
  if (v.kind === 'not-ready') {
    const n = v.failing.length;
    return trial
      ? `The recorded instance was not ready: ${plural(n, 'core check')} failed.`
      : `Not ready: ${plural(n, 'core check')} ${n === 1 ? 'fails' : 'fail'}.`;
  }
  return 'Checks not reported: this report has none of the core checks.';
}

// ---- the rows ----

/** A row's mark: a check, a cross, a dash or nothing (a name, a path or a number). */
export type Mark = 'check' | 'x' | 'dash' | 'none';

export interface Reason {
  /** The chip, 3 to 5 words. */
  chip: string;
  /** The full note, in the chip's tooltip and in the group's detail. */
  note: string;
  tone: Tone;
}

export interface RowInfo {
  mark: Mark;
  /** The tone of the mark; null when the row has no mark. */
  tone: Tone | null;
  /** The report did not send it. */
  missing: boolean;
  /** What to do, on a core check that failed. */
  todo?: string;
  reason?: Reason;
}

/** What a No means in the trial, for the pieces the instance the trial was recorded on did not have. */
const ABSENT_IN_TRIAL: Record<string, string> = {
  ai_hub_present:
    "This report is from the instance that served the cases, which had no AI Hub. The board's runs were recorded with the real agents on the AI Hub build and replay here.",
  aihub_runner:
    "This report is from the instance that served the cases, which had not compiled the class that runs agents through AI Hub. The board's runs were recorded with the real agents on the AI Hub build and replay here.",
  purge_task:
    'The recorded instance had no message purge task. An installation makes one when SHUTTER_MESSAGE_PURGE asks for it.',
};

const NOT_ON_RECORDED = 'Not on the recorded instance';

/**
 * The provider's two pieces live in IRISSYS behind their own rights (the wallet's Shutter_Secrets, the Config Store's
 * %Admin_ConfigStore). The Doctor sends null where the reader may not look, and in the replay edition, which has
 * neither; a null is then a fact about the reader or the edition, not a gap in the report.
 */
const PROVIDER_PIECES = new Set(['wallet_secret', 'provider_config']);
const NOT_VISIBLE = 'Not visible to you';
const NOT_VISIBLE_NOTES: Record<string, string> = {
  wallet_secret:
    'The provider key lives in the IRIS wallet, which answers only a reader with the resource Shutter_Secrets, so this report cannot say whether it is there. The production checks it at every start and writes it again from ANTHROPIC_API_KEY when it is gone; the Event Log shows that check.',
  provider_config:
    'The provider configuration lives in the Config Store, which answers only a reader with %Admin_ConfigStore, so this report cannot say whether it is there. The production checks it at every start, with the key; the Event Log shows that check.',
};
const NOT_IN_EDITION = 'Not in this edition';
const NOT_IN_EDITION_NOTE =
  'The replay edition has no wallet and no Config Store: its agents replay recorded runs, so there is no provider to configure and no provider key to hold.';

/**
 * The provider is the name the install recorded, "" until ConfigureProvider has run: on the AI Hub edition that is a
 * setting (no key was given, so the agents replay recordings), and in the replay edition it is the edition.
 */
const NOT_CONFIGURED = 'Not configured';
const NOT_CONFIGURED_NOTE =
  'No model provider is recorded. The install configures one from ANTHROPIC_API_KEY when it is set; until then the agents replay recorded runs.';

/** The credential check threw instead of answering: the state carries the error, and the check says nothing. */
const CHECK_FAILED = 'Check did not run';
const CHECK_FAILED_NOTE =
  'The Doctor could not run the credential check, so this report says nothing about whether the stored credentials sign in. The state is the error it met.';

/** Shutter reads a receiver only when a case or a delivery needs it, so nothing may have read it yet. */
const NOT_KNOWN = 'Not known yet';
const NOT_KNOWN_NOTE =
  'Shutter reads a receiver only when a case or a delivery needs it, and it has not read one yet. It sends no probe of its own.';

const NO_PURGE_NOTE =
  'Nothing deletes old messages. An installation makes the task when SHUTTER_MESSAGE_PURGE asks for it.';

/**
 * A row's mark, tone and reason, by the row rule: a core check that passes is positive and one that fails is blocking
 * with what to do; another yes is positive; another no is neutral, with the reason chip where the trial's recording
 * lacked the piece, and attention for a missing message purge task on a live installation; a value the report did not
 * send is attention ("Not reported"); an install item missing from the production or an edition that is broken is
 * blocking with what to do, a disabled item attention, and a stored credential that does not sign in blocking; a provider
 * the install has not configured is neutral, and a credential check that threw is attention; a name, a path or a number
 * has no mark.
 */
export function rowInfo(key: string, value: unknown, report: Report, trial: boolean): RowInfo {
  // The API mimic's switch is "" when it is off: a setting, not a missing value
  if (key === 'mock_config' && value === '') return { mark: 'none', tone: null, missing: false };
  // No time when the portal was never hardened, the case on any instance but the public demo: not a missing value
  if (key === 'portal_hardened_at' && value === '') return { mark: 'none', tone: null, missing: false };
  // The latest start's hardening errors: "" when it succeeded or was never asked for; a failed hardening is attention
  if (key === 'portal_hardening_errors')
    return value === ''
      ? { mark: 'none', tone: null, missing: false }
      : { mark: 'dash', tone: 'attention', missing: false };
  // The provider is "" until the install has configured one: not configured, or not in the replay edition
  if (key === 'provider' && value === '')
    return report.ai_hub_present === true
      ? {
          mark: 'dash',
          tone: 'neutral',
          missing: false,
          reason: { chip: NOT_CONFIGURED, note: NOT_CONFIGURED_NOTE, tone: 'neutral' },
        }
      : {
          mark: 'dash',
          tone: 'neutral',
          missing: false,
          reason: { chip: NOT_IN_EDITION, note: NOT_IN_EDITION_NOTE, tone: 'neutral' },
        };
  // Null: nothing has read a receiver yet, or the reading itself failed. A fact, not a gap in the report
  if (key === 'receivers_ok' && value === null)
    return {
      mark: 'dash',
      tone: 'neutral',
      missing: false,
      reason: { chip: NOT_KNOWN, note: NOT_KNOWN_NOTE, tone: 'neutral' },
    };
  if ((key === 'receivers_ok' || key === 'watched_ok') && value === false)
    return { mark: 'x', tone: 'attention', missing: false };
  // A credential check that threw is attention: its state is the error, not a word
  if (key === 'credentials_state' && credentialCheckFailed(report))
    return {
      mark: 'dash',
      tone: 'attention',
      missing: false,
      reason: { chip: CHECK_FAILED, note: CHECK_FAILED_NOTE, tone: 'attention' },
    };
  // A null for the provider's pieces is the Doctor's own answer: this reader may not look, or the edition has none
  if (PROVIDER_PIECES.has(key) && value === null) {
    return report.ai_hub_present === true
      ? {
          mark: 'dash',
          tone: 'neutral',
          missing: false,
          reason: { chip: NOT_VISIBLE, note: NOT_VISIBLE_NOTES[key], tone: 'neutral' },
        }
      : {
          mark: 'dash',
          tone: 'neutral',
          missing: false,
          reason: { chip: NOT_IN_EDITION, note: NOT_IN_EDITION_NOTE, tone: 'neutral' },
        };
  }
  if (!sent(value)) return { mark: 'dash', tone: 'attention', missing: true };
  const core = coreFor(report).find((c) => c.key === key);
  if (core) {
    const passed = core.passes ? core.passes(value, report) : value === true;
    return passed
      ? { mark: 'check', tone: 'positive', missing: false }
      : { mark: 'x', tone: 'blocking', missing: false, todo: core.todo(value, report) };
  }
  if (typeof value === 'boolean') {
    if (value) return { mark: 'check', tone: 'positive', missing: false };
    const note = trial ? ABSENT_IN_TRIAL[key] : undefined;
    if (note)
      return {
        mark: 'dash',
        tone: 'neutral',
        missing: false,
        reason: { chip: NOT_ON_RECORDED, note, tone: 'neutral' },
      };
    if (key === 'purge_task')
      return {
        mark: 'dash',
        tone: 'attention',
        missing: false,
        reason: { chip: 'No message purge task', note: NO_PURGE_NOTE, tone: 'attention' },
      };
    return { mark: 'dash', tone: 'neutral', missing: false };
  }
  if (key === 'missing_items' && Array.isArray(value) && value.length)
    return { mark: 'x', tone: 'blocking', missing: false, todo: MISSING_ITEMS_TODO };
  if (key === 'disabled_items' && Array.isArray(value) && value.length)
    return { mark: 'dash', tone: 'attention', missing: false, todo: DISABLED_ITEMS_TODO };
  if (key === 'edition' && typeof value === 'string' && value.startsWith('broken'))
    return { mark: 'x', tone: 'blocking', missing: false, todo: BROKEN_EDITION_TODO };
  if (key === 'credentials' && Array.isArray(value) && value.length)
    return credentialChecks(value).every((c) => c.ok)
      ? { mark: 'check', tone: 'positive', missing: false }
      : { mark: 'x', tone: 'blocking', missing: false };
  return { mark: 'none', tone: null, missing: false };
}

/** One stored credential the Doctor tried, as the report lists it. */
export interface CredentialCheck {
  namespace: string;
  name: string;
  user: string;
  status: string;
  detail: string;
  ok: boolean;
}

/** The report's credential checks as typed records: a field it did not send is empty, ok only when it is true. */
export function credentialChecks(value: unknown): CredentialCheck[] {
  if (!Array.isArray(value)) return [];
  const str = (v: unknown) => (typeof v === 'string' ? v : v === undefined || v === null ? '' : String(v));
  return value.map((v) => {
    const c = (v && typeof v === 'object' ? v : {}) as Record<string, unknown>;
    return {
      namespace: str(c.namespace),
      name: str(c.name),
      user: str(c.user),
      status: str(c.status),
      detail: str(c.detail),
      ok: c.ok === true,
    };
  });
}

export interface Row {
  key: string;
  label: string;
  value: unknown;
  info: RowInfo;
  /** A row that is not a report key: the default board, drawn from the agent library. */
  virtual?: 'default-board';
}

export interface GroupStatus {
  tone: Tone;
  label: string;
}

export interface Group {
  def: GroupDef;
  rows: Row[];
  /**
   * The group's count: its core checks passing (and the rows to fix besides them), else the rows to fix, else the pieces
   * missing from the recording, else rows to look at.
   */
  status: GroupStatus | null;
  /** The tone of a group that needs a look (a core check or a row is blocking, or a row is attention); null otherwise. */
  edge: Tone | null;
  /** Core checks in the group, as the group links count them. */
  checks: CoreResult[];
}

/** A row's label in words. */
function labelFor(key: string, report: Report): string {
  if (key === 'production')
    return sent(report.shutter_production) && report.shutter_production !== report.production
      ? 'Production running now'
      : 'Production';
  return LABELS[key] ?? keyLabel(key);
}

/** The report in groups: each key where the table puts it, the rest in Other, the provenance nowhere. */
export function groupReport(report: Report, trial: boolean): { verdict: Verdict; groups: Group[] } {
  const verdict = verdictOf(report);
  const keys = Object.keys(report).filter((k) => k !== PROVENANCE_KEY);
  const placed = new Set(GROUPS.flatMap((g) => g.keys));
  const defs = [...GROUPS, { ...OTHER, keys: keys.filter((k) => !placed.has(k)) }];
  const groups: Group[] = [];
  for (const def of defs) {
    const rows: Row[] = [];
    for (const key of def.keys) {
      if (!(key in report)) continue;
      // The same name twice says nothing more: the running production is Shutter's own
      if (
        key === 'production' &&
        sent(report.shutter_production) &&
        report.shutter_production === report.production
      )
        continue;
      rows.push({
        key,
        label: labelFor(key, report),
        value: report[key],
        info: rowInfo(key, report[key], report, trial),
      });
      if (key === 'board_members')
        rows.push({
          key: 'default_board',
          label: 'Default board',
          value: null,
          info: { mark: 'none', tone: null, missing: false },
          virtual: 'default-board',
        });
    }
    if (!rows.length) continue;
    const checks = verdict.results.filter((r) => def.keys.includes(r.key));
    const absent = rows.filter((r) => r.info.reason?.chip === NOT_ON_RECORDED).length;
    const look = rows.filter((r) => r.info.tone === 'attention').length;
    // A row that is blocking on its own, apart from the core checks: an item missing from the production
    const fix = rows.filter((r) => r.info.tone === 'blocking' && !checks.some((c) => c.key === r.key)).length;
    let status: GroupStatus | null = null;
    if (checks.length) {
      const ok = checks.filter((c) => c.passed).length;
      const pass = `${ok} of ${checks.length} pass`;
      status = {
        tone: ok === checks.length && !fix ? 'positive' : 'blocking',
        label: ok === checks.length && fix ? `${pass}, ${fix} to fix` : pass,
      };
    } else if (fix) {
      status = { tone: 'blocking', label: `${fix} to fix` };
    } else if (absent) {
      status = { tone: 'neutral', label: `${absent} not on the recorded instance` };
    } else if (look) {
      status = { tone: 'attention', label: `${look} to check` };
    }
    groups.push({
      def,
      rows,
      status,
      edge: checks.some((c) => !c.passed) || fix ? 'blocking' : look ? 'attention' : null,
      checks,
    });
  }
  return { verdict, groups };
}

// ---- values ----

/** The sentence a licence object makes: its fields as the report names them, with no sum worked out. */
export function licenceSentence(license: unknown): string | null {
  if (!license || typeof license !== 'object' || Array.isArray(license)) return null;
  const l = license as Record<string, unknown>;
  const num = (v: unknown) => (typeof v === 'number' && Number.isFinite(v) ? v : null);
  const consumed = num(l.units_consumed);
  const available = num(l.units_available);
  const max = num(l.max_connections);
  const clauses = [
    consumed !== null ? `${plural(consumed, 'unit')} consumed` : '',
    available !== null ? `${available} available` : '',
    max !== null ? `up to ${plural(max, 'connection')}` : '',
  ].filter(Boolean);
  const type = typeof l.license_type === 'string' && l.license_type ? `${l.license_type} licence` : '';
  if (type && clauses.length) return `${type}: ${clauses.join(', ')}`;
  if (clauses.length) return `Licence: ${clauses.join(', ')}`;
  if (typeof l.error === 'string' && l.error) return 'The licence could not be read.';
  return type || null;
}

/** An object's fields as lines of words ("Enabled: true"), for the keys the page has no sentence for. */
export function objectLines(value: Record<string, unknown>): string[] {
  return Object.entries(value).map(
    ([field, v]) =>
      `${humanize(field)}: ${typeof v === 'object' && v !== null ? JSON.stringify(v) : String(v)}`,
  );
}

/** The model budget in words, as the Settings page says it (on the public demo it is per reset, never "today"). */
export function budgetLine(budget: unknown, report: Report): string | null {
  if (!budget || typeof budget !== 'object' || Array.isArray(budget)) return null;
  const hourly = resetsHourly({ live: report.live as LiveStatus | undefined });
  const words = budgetText(budget as Budget, { resetsHourly: hourly });
  return words ? [words.today, words.share].filter(Boolean).join('. ') : null;
}

/** Whether a value is too long to sit beside its label on a phone. */
export function isLong(value: unknown): boolean {
  if (value && typeof value === 'object') return true;
  return typeof value === 'string' && value.length > 24;
}

// ---- the agents badge ----

export interface AgentsBadge {
  kind: 'on-hub' | 'recorded' | 'replays';
  tone: Tone;
  label: string;
  hint?: string;
}

/**
 * What the report says of the agents' home, never as part of the verdict: they run on IRIS AI Hub; or, where the
 * instance has no AI Hub, the board's runs were recorded on it and replay here (the trial and the demo build), or the
 * installation replays recordings and needs AI Hub to run them. Never "AI Hub not needed".
 */
export function agentsBadge(
  report: Report,
  trial: boolean,
  recordedOn: Proof['recordedOn'],
): AgentsBadge | null {
  const hub = report.ai_hub_present;
  const runner = report.aihub_runner;
  if (hub === true && runner === true)
    return { kind: 'on-hub', tone: 'info', label: 'Agents run on IRIS AI Hub' };
  if (hub !== false && runner !== false) return null;
  if (trial)
    return {
      kind: 'recorded',
      tone: 'neutral',
      label: recordedOn?.number
        ? `Board runs recorded on IRIS AI Hub (build ${recordedOn.number}); replayed here`
        : 'Board runs recorded on IRIS AI Hub; replayed here',
      hint: recordedOn ? `Recorded on ${recordedOn.image}` : undefined,
    };
  return {
    kind: 'replays',
    tone: 'info',
    label: 'Agents replay recordings; running them needs IRIS AI Hub',
  };
}

// ---- the provenance ----

const ISO = /\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}Z/g;

const MINUTE = new Intl.DateTimeFormat('en-GB', {
  day: 'numeric',
  month: 'short',
  year: 'numeric',
  hour: '2-digit',
  minute: '2-digit',
  hourCycle: 'h23',
  timeZone: 'UTC',
});

/** "20 Oct 2026, 17:55 UTC": a moment to the minute, in UTC, as the hero and the provenance say it. */
export function utcMinute(iso: string): string {
  const d = new Date(iso);
  return Number.isNaN(d.getTime()) ? iso : `${MINUTE.format(d)} UTC`;
}

/** When the recording was read: the first time the `recorded` text names. */
export function recordedAt(recorded: unknown): string | null {
  return typeof recorded === 'string' ? (recorded.match(ISO)?.[0] ?? null) : null;
}

const upper = (s: string) => s.charAt(0).toUpperCase() + s.slice(1);

/**
 * The `recorded` text as a list, one fact per line: when it was read and from where, what it holds, what was recorded
 * later and from where. Its times are written the way the hero writes them.
 */
export function provenanceFacts(recorded: unknown): string[] {
  if (typeof recorded !== 'string' || !recorded.trim()) return [];
  const text = recorded.replace(ISO, (t) => utcMinute(t));
  const sentences = text.split(/(?<=\.)\s+(?=[A-Z])/).map((s) => s.trim());
  const [first, ...rest] = sentences;
  // The first sentence runs "Recorded from ... at TIME: WHAT; AND WHAT": its colon and semicolon are fact breaks
  const head = first
    .replace(/\.$/, '')
    .split(/:\s+|;\s+/)
    .map(upper);
  return [...head, ...rest].filter(Boolean);
}
