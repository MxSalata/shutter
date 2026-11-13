import type { Health } from '@/api/types';
import recording from '@/mocks/fixtures.json';
import onboarding from '@/mocks/onboarding.json';

/**
 * Health reports (`GET /health`) for the installs an empty cases list can be on, for the tests. The demo's is the
 * recorded demo install's own answer; the sites' carry `demo` false and the Doctor's `watched_namespaces`, whose rows
 * are the ones recorded on real productions (mocks/onboarding.json, CONTRACTS 11.1).
 */

const watched = (namespace: keyof typeof onboarding.namespaces) =>
  onboarding.namespaces[namespace].watched as Record<string, unknown>;

/** A demo install: scenarios open cases. */
export const DEMO_INSTALL = recording.health as unknown as Health;

/** A site with two namespaces onboarded, each forwarding its failures, and no problem reported. */
export const SITE_WITH_INTAKE: Health = {
  demo: false,
  production_state: 'running',
  watched_ok: true,
  watched_namespaces: [watched('PATHOLOGY'), watched('DOCUMENTS')],
};

/** The same site with a problem at one of them: its forwarder is in place, and the report's `ok` is false. */
export const SITE_WITH_TROUBLED_INTAKE: Health = {
  demo: false,
  production_state: 'running',
  watched_ok: false,
  watched_namespaces: [
    watched('PATHOLOGY'),
    { ...watched('DOCUMENTS'), ok: false, problems: ['The item Shutter Forwarder is disabled'] },
  ],
};

/** A site nobody has onboarded a namespace on yet: installed and running, with nothing forwarding to it. */
export const SITE_AWAITING_SETUP: Health = {
  demo: false,
  production_state: 'running',
  watched_ok: null,
  watched_namespaces: [],
};

/**
 * A site whose only watched namespaces forward nothing: one taken off again, and one a case named that was never
 * onboarded here. Neither is an intake.
 */
export const SITE_WITH_NOTHING_FORWARDING: Health = {
  demo: false,
  production_state: 'running',
  watched_namespaces: [
    { ...watched('PATHOLOGY'), removed: true },
    { ...watched('DOCUMENTS'), onboarded: false, forwarder: false },
  ],
};
