import type { Can, Health } from '@/api/types';

/**
 * What kind of install an empty cases list is on, read from what the install says of itself and never from its address
 * or the signed-in name:
 *
 * - `trial`: the recorded cases answered in the browser (the build and `?trial`, env/mode.ts);
 * - `demo`: a demo install (`GET /health`, `demo` true), where scenarios open cases;
 * - `site-intake`: a site (`demo` false) with a watched namespace that forwards its failures: one the Doctor lists in
 *   `watched_namespaces` as onboarded, not taken off, with its forwarder in place (CONTRACTS 11.1);
 * - `site-setup`: a site whose report lists no such namespace yet;
 * - `unknown`: the report is not read yet, could not be read, or comes without the field (a server before v1.42 sends
 *   no `watched_namespaces`): nothing is guessed.
 */
export type EmptyInstall = 'trial' | 'demo' | 'site-intake' | 'site-setup' | 'unknown';

/** The fields of a `watched_namespaces` row this reads (CONTRACTS 11.1 lists the rest). */
interface Watched {
  namespace?: unknown;
  onboarded?: unknown;
  removed?: unknown;
  forwarder?: unknown;
  ok?: unknown;
}

/**
 * The watched namespaces that forward their failures to Shutter, as the health report lists them, each with whether
 * the report finds a problem there; null when the report has no such list.
 */
export function forwardingNamespaces(
  health: Health | undefined,
): { namespace: string; ok: boolean }[] | null {
  const watched = health?.watched_namespaces;
  if (!Array.isArray(watched)) return null;
  return (watched as (Watched | null)[])
    .filter((w): w is Watched => !!w && w.onboarded === true && w.removed !== true && w.forwarder === true)
    .map((w) => ({ namespace: String(w.namespace ?? ''), ok: w.ok !== false }));
}

export function emptyInstall(trial: boolean, health: Health | undefined): EmptyInstall {
  if (trial) return 'trial';
  if (typeof health?.demo !== 'boolean') return 'unknown';
  if (health.demo) return 'demo';
  const forwarding = forwardingNamespaces(health);
  if (forwarding === null) return 'unknown';
  return forwarding.length > 0 ? 'site-intake' : 'site-setup';
}

/** "HOSPITAL", "HOSPITAL and LAB", "HOSPITAL, LAB and 2 more": a list short enough for one sentence. */
function named(names: string[]): string {
  const known = names.filter(Boolean);
  if (known.length === 0) return 'a watched namespace';
  if (known.length <= 2) return known.join(' and ');
  return `${known[0]}, ${known[1]} and ${known.length - 2} more`;
}

export interface EmptyGuidance {
  kind: EmptyInstall;
  /** What the empty list says. */
  words: string;
  /** The one link: the next step for this install, and only one this person can use. */
  link: { to: string; label: string };
}

/**
 * What an empty cases list with no filter says, and the one link under it. A demo or the trial offers a scenario, and
 * only to someone who may run one. A site is never told to make a failure: with a namespace forwarding, nothing has
 * failed yet and Health shows the intake; with none, the missing step is named, with the page that does it for someone
 * who may configure the site and Health for anyone else.
 */
export function emptyGuidance({
  trial,
  health,
  can,
}: {
  trial: boolean;
  health: Health | undefined;
  can: Pick<Can, 'scenarios' | 'configure'>;
}): EmptyGuidance {
  const kind = emptyInstall(trial, health);
  if (kind === 'trial' || kind === 'demo') {
    if (!can.scenarios)
      return {
        kind,
        words: 'No cases yet. An operator, approver or judge opens one by playing a scenario.',
        link: { to: '/scenarios', label: 'See the scenarios' },
      };
    return {
      kind,
      words:
        kind === 'trial'
          ? 'No cases yet. Play a recorded scenario to open one.'
          : 'No cases yet. Play a scenario to open one.',
      link: { to: '/scenarios', label: 'Play a scenario' },
    };
  }
  if (kind === 'site-intake') {
    const forwarding = forwardingNamespaces(health) ?? [];
    const troubled = forwarding.filter((w) => !w.ok).map((w) => w.namespace);
    if (troubled.length > 0)
      return {
        kind,
        words: `No failed delivery has reached Shutter yet, and Health reports a problem with ${named(troubled)}.`,
        link: { to: '/health', label: 'Open Health' },
      };
    return {
      kind,
      words: `No failed delivery has reached Shutter yet. It watches ${named(forwarding.map((w) => w.namespace))}.`,
      link: { to: '/health', label: 'If one was expected, check Health' },
    };
  }
  if (kind === 'site-setup')
    return can.configure
      ? {
          kind,
          words: 'No cases yet. No watched namespace reports its failures here.',
          link: { to: '/settings/namespaces', label: 'Set up a watched namespace' },
        }
      : {
          kind,
          words:
            'No cases yet. No watched namespace reports its failures here; someone who may configure Shutter sets one up.',
          link: { to: '/health', label: 'See what Health reports' },
        };
  return { kind, words: 'No cases yet.', link: { to: '/health', label: 'Open Health' } };
}
