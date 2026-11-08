import { describe, expect, it } from 'vitest';
import {
  agentsBadge,
  budgetLine,
  credentialChecks,
  groupReport,
  licenceSentence,
  provenanceFacts,
  recordedAt,
  rowInfo,
  utcMinute,
  verdictOf,
  verdictStatement,
  type Report,
} from './report';

/** The report the trial was recorded from: a demo installation without AI Hub or a purge task. */
const RECORDED: Report = {
  recorded:
    "Recorded from Shutter's REST API at 2026-10-20T17:55:04Z: 53 cases (14 by rules alone, 26 in site-policy mode, 13 by the board of specialists) and 2 incidents; the board's 64 agent runs are replays of recorded runs. S22's two cases, one per receiver, were recorded at 2026-10-26T02:13:13Z in site-policy mode from a test instance with the patient records system. The demo serves these answers in the browser; nothing in it reaches an IRIS instance.",
  namespace: 'SHUTTER',
  version: '0.1.0',
  installed_at: '2026-10-20T03:11:47Z',
  demo: true,
  mode: 'rules',
  adt_in: '/usr/irissys/mgr/shutter/in/',
  interoperability: true,
  shutter_production: 'Shutter.Production',
  production_class: true,
  production: 'Shutter.Production',
  production_state: 'running',
  ward_classes: true,
  aihub_runner: false,
  ai_hub_present: false,
  board_members: 5,
  recordings: 100,
  cases: 53,
  license: { license_type: 'Concurrent User', units_consumed: 1, units_available: 7, max_connections: 25 },
  api_webapp: true,
  ui_webapp: true,
  wards_webapp: true,
  purge_task: false,
  webapps_checked: 'install record',
};

const without = (r: Report, ...keys: string[]): Report =>
  Object.fromEntries(Object.entries(r).filter(([k]) => !keys.includes(k)));

/** The stored credentials the Doctor tried (v1.38): one that signs in and one that no longer does. */
const CREDENTIALS = [
  {
    namespace: 'SHUTTER',
    name: 'DownstreamAPI',
    user: 'downstream-api',
    status: 'refused',
    detail:
      'downstream-api does not sign in with the stored password (ERROR #798): the credential and the user disagree',
    ok: false,
  },
  {
    namespace: 'HOSPITAL',
    name: 'ShutterIntake',
    user: 'forwarder',
    status: 'ok',
    detail: 'forwarder signs in with the stored password',
    ok: true,
  },
];

const RECORDED_ON = {
  image: 'irishealth-community:2026.3.0AI.154.0',
  build: '2026.3.0AI.154.0',
  number: '154',
};

describe('the verdict', () => {
  it('is Ready when every core check passes: seven on a demo installation, five elsewhere', () => {
    const demo = verdictOf(RECORDED);
    expect(demo).toMatchObject({ kind: 'ready', tone: 'positive', word: 'Ready', passed: 7, notSent: 0 });
    expect(demo.results.map((r) => r.label)).toEqual([
      'Interoperability on',
      'Production compiled',
      'Running',
      'API web app',
      'UI web app',
      'Downstream classes',
      'Downstream web app',
    ]);
    const site = verdictOf({ ...RECORDED, demo: false });
    expect(site).toMatchObject({ kind: 'ready', passed: 5 });
    expect(site.results.map((r) => r.key)).not.toContain('ward_classes');
    expect(site.results.map((r) => r.key)).not.toContain('wards_webapp');
  });

  it('is Not ready when any core check fails, naming each failing check and what to do', () => {
    const v = verdictOf({ ...RECORDED, production_class: false, production_state: 'stopped' });
    expect(v).toMatchObject({ kind: 'not-ready', tone: 'blocking', word: 'Not ready', passed: 5 });
    expect(v.failing.map((f) => f.label)).toEqual(['Production compiled', 'Running']);
    expect(v.failing[0].todo).toBe('Compile the production class, then reload.');
    expect(v.failing[1].todo).toBe('Start the production, then reload. It is stopped.');
    expect(verdictStatement(v, false)).toBe('Not ready: 2 core checks fail.');
    expect(verdictStatement(verdictOf({ ...RECORDED, api_webapp: false }), false)).toBe(
      'Not ready: 1 core check fails.',
    );
  });

  it('leaves a core check the report did not send out of the count, and says so when none was sent', () => {
    const partial = verdictOf(without(RECORDED, 'ui_webapp', 'api_webapp'));
    expect(partial).toMatchObject({ kind: 'ready', passed: 5, notSent: 2 });
    expect(verdictOf({ ...RECORDED, ui_webapp: null })).toMatchObject({ passed: 6, notSent: 1 });
    const none = verdictOf({ namespace: 'SHUTTER', version: '0.1.0', demo: true });
    expect(none).toMatchObject({ kind: 'not-reported', tone: 'attention', word: 'Checks not reported' });
    expect(verdictStatement(none, false)).toBe(
      'Checks not reported: this report has none of the core checks.',
    );
  });

  it('is Not ready when a stored credential no longer signs in, saying what to do and where to refresh', () => {
    const v = verdictOf({
      ...RECORDED,
      credentials_ok: false,
      credentials_state: 'fresh',
      credentials_checked_at: '2026-11-03T10:00:00Z',
      credentials: [CREDENTIALS[0]],
    });
    expect(v).toMatchObject({ kind: 'not-ready', tone: 'blocking', word: 'Not ready', passed: 7 });
    expect(v.failing.map((f) => f.label)).toEqual(['Stored credentials sign in']);
    expect(v.failing[0].group).toBe('credentials');
    expect(v.failing[0].todo).toContain('run the install again');
    expect(v.failing[0].todo).toContain('GET /health?refresh=1');
    expect(verdictStatement(v, false)).toBe('Not ready: 1 core check fails.');
    expect(verdictOf({ ...RECORDED, credentials_ok: true, credentials: [CREDENTIALS[1]] })).toMatchObject({
      kind: 'ready',
      passed: 8,
    });
    // The trial's recording predates the credential checks and sends none of their keys: the check is not counted,
    // not even as "not reported"; a report that sends the key as null is one that left it out
    expect(verdictOf(RECORDED)).toMatchObject({ kind: 'ready', passed: 7, notSent: 0 });
    expect(verdictOf({ ...RECORDED, credentials_ok: null })).toMatchObject({ passed: 7, notSent: 1 });
  });

  it('does not count a credential check that threw as passing, whatever credentials_ok says', () => {
    // The Doctor's catch leaves credentials_ok true and puts the error in the state
    const v = verdictOf({
      ...RECORDED,
      credentials_ok: true,
      credentials_state: 'error: <THROW> reading the credential cache',
      credentials_checked_at: '',
      credentials: [],
    });
    expect(v).toMatchObject({ kind: 'not-ready', passed: 7 });
    expect(v.failing.map((f) => f.key)).toEqual(['credentials_ok']);
    expect(v.failing[0].todo).toContain('could not run');
    expect(v.failing[0].todo).toContain('GET /health?refresh=1');
  });

  it('counts a production that is not running as a failure, not as a pass', () => {
    expect(verdictOf({ ...RECORDED, production_state: 'another production running' }).kind).toBe('not-ready');
    expect(verdictOf({ ...RECORDED, production_state: undefined }).running).toBe(false);
  });

  it('states it plainly live and as a recording in the trial, with the counts', () => {
    const v = verdictOf(RECORDED);
    expect(verdictStatement(v, false)).toBe(
      'Ready: the message engine is running and every core check passes (7 of 7).',
    );
    expect(verdictStatement(v, true)).toBe(
      'The recorded instance was ready: its message engine was running and every core check passed (7 of 7).',
    );
    expect(verdictStatement(verdictOf({ ...RECORDED, api_webapp: false }), true)).toBe(
      'The recorded instance was not ready: 1 core check failed.',
    );
    // Without the production's state the sentence does not claim the engine runs
    const noState = verdictOf(without(RECORDED, 'production_state'));
    expect(verdictStatement(noState, false)).toBe('Ready: every core check passes (6 of 6).');
  });
});

describe('the groups', () => {
  it('puts each key in its group in the table order, and the production name once', () => {
    const { groups } = groupReport(RECORDED, true);
    expect(groups.map((g) => g.def.title)).toEqual([
      'Production',
      'Web applications',
      'Agents and AI Hub',
      'Cases and housekeeping',
      'Installation and licence',
    ]);
    const keys = (title: string) => groups.find((g) => g.def.title === title)!.rows.map((r) => r.key);
    expect(keys('Production')).toEqual([
      'interoperability',
      'production_class',
      'production_state',
      'ward_classes',
      'shutter_production',
      'adt_in',
      'mode',
    ]);
    expect(keys('Web applications')).toEqual(['api_webapp', 'ui_webapp', 'wards_webapp', 'webapps_checked']);
    // The default board follows the enabled agents
    expect(keys('Agents and AI Hub')).toEqual([
      'ai_hub_present',
      'aihub_runner',
      'board_members',
      'default_board',
      'recordings',
    ]);
    expect(keys('Cases and housekeeping')).toEqual(['cases', 'purge_task']);
    expect(keys('Installation and licence')).toEqual([
      'namespace',
      'version',
      'installed_at',
      'demo',
      'license',
    ]);
  });

  it('never makes the provenance a row, and puts a key it does not know in Other', () => {
    const { groups } = groupReport({ ...RECORDED, second_parser: { jar: true }, brand_new: 'x' }, false);
    const rows = groups.flatMap((g) => g.rows.map((r) => r.key));
    expect(rows).not.toContain('recorded');
    const other = groups[groups.length - 1];
    expect(other.def.title).toBe('Other');
    expect(other.rows.map((r) => r.key)).toEqual(['second_parser', 'brand_new']);
    expect(other.rows[1].label).toBe('Brand new');
    expect(groupReport(RECORDED, false).groups.some((g) => g.def.title === 'Other')).toBe(false);
  });

  it('puts the install items and the edition in Production, and the stored credentials in their own group', () => {
    const { groups } = groupReport(
      {
        ...RECORDED,
        edition: 'core',
        missing_items: [],
        disabled_items: [],
        credentials_ok: true,
        credentials_state: 'fresh',
        credentials_checked_at: '2026-11-03T10:00:00Z',
        credentials: [CREDENTIALS[1]],
      },
      false,
    );
    expect(groups.map((g) => g.def.title)).toEqual([
      'Production',
      'Web applications',
      'Stored credentials',
      'Agents and AI Hub',
      'Cases and housekeeping',
      'Installation and licence',
    ]);
    const production = groups[0];
    expect(production.rows.map((r) => r.key).slice(-3)).toEqual([
      'edition',
      'missing_items',
      'disabled_items',
    ]);
    expect(production.rows.map((r) => r.label).slice(-3)).toEqual([
      'Edition',
      'Missing items',
      'Disabled items',
    ]);
    // Nothing missing and nothing disabled is a value with no mark, not a gap
    expect(production.rows.find((r) => r.key === 'missing_items')!.info).toEqual({
      mark: 'none',
      tone: null,
      missing: false,
    });
    expect(production.status).toEqual({ tone: 'positive', label: '4 of 4 pass' });
    expect(production.edge).toBeNull();
    const credentials = groups[2];
    expect(credentials.rows.map((r) => r.key)).toEqual([
      'credentials_ok',
      'credentials_state',
      'credentials_checked_at',
      'credentials',
    ]);
    expect(credentials.rows[0].label).toBe('Stored credentials sign in');
    expect(credentials.rows[0].info).toMatchObject({ mark: 'check', tone: 'positive' });
    expect(credentials.rows[3].info).toMatchObject({ mark: 'check', tone: 'positive' });
    expect(credentials.status).toEqual({ tone: 'positive', label: '1 of 1 pass' });
    expect(credentials.edge).toBeNull();
  });

  it('marks an item missing from the production and a broken edition as blocking, with the group edged and counted', () => {
    const missing = groupReport(
      { ...RECORDED, missing_items: ['Scenario Player'], disabled_items: [], edition: 'core' },
      false,
    ).groups[0];
    const row = missing.rows.find((r) => r.key === 'missing_items')!;
    expect(row.info).toEqual({
      mark: 'x',
      tone: 'blocking',
      missing: false,
      todo: 'Run the install again: these items are missing from the production.',
    });
    expect(missing.edge).toBe('blocking');
    expect(missing.status).toEqual({ tone: 'blocking', label: '4 of 4 pass, 1 to fix' });
    const broken = groupReport(
      { ...RECORDED, edition: 'broken: the aihub module is loaded on an image without AI Hub' },
      false,
    ).groups[0];
    expect(broken.rows.find((r) => r.key === 'edition')!.info).toMatchObject({ mark: 'x', tone: 'blocking' });
    expect(broken.edge).toBe('blocking');
    // A disabled item is a row to look at, except the Second Parser, which the report leaves out when its jar is absent
    const disabled = groupReport({ ...RECORDED, disabled_items: ['Case Releaser'] }, false).groups[0];
    expect(disabled.rows.find((r) => r.key === 'disabled_items')!.info).toMatchObject({
      mark: 'dash',
      tone: 'attention',
      todo: 'Enable these items in the production, or run the install again.',
    });
    expect(disabled.edge).toBe('attention');
    expect(disabled.status).toEqual({ tone: 'positive', label: '4 of 4 pass' });
    // A failing core check keeps the plain count: the group is blocking already
    const both = groupReport({ ...RECORDED, production_class: false, missing_items: ['Gate'] }, false)
      .groups[0];
    expect(both.status).toEqual({ tone: 'blocking', label: '3 of 4 pass' });
  });

  it('counts a credential that no longer signs in against the group and marks its list blocking', () => {
    const { groups } = groupReport(
      { ...RECORDED, credentials_ok: false, credentials_state: 'stale', credentials: CREDENTIALS },
      false,
    );
    const credentials = groups.find((g) => g.def.id === 'credentials')!;
    expect(credentials.status).toEqual({ tone: 'blocking', label: '0 of 1 pass' });
    expect(credentials.edge).toBe('blocking');
    expect(credentials.rows.find((r) => r.key === 'credentials')!.info).toMatchObject({
      mark: 'x',
      tone: 'blocking',
    });
    expect(credentials.checks.map((c) => c.key)).toEqual(['credentials_ok']);
  });

  it("shows the running production when it is not Shutter's own", () => {
    const { groups } = groupReport({ ...RECORDED, production: 'Site.Production' }, false);
    const rows = groups[0].rows;
    expect(rows.find((r) => r.key === 'production')?.label).toBe('Production running now');
  });

  it("counts a group's core checks, then the pieces the recording lacked, then the rows to look at", () => {
    const { groups } = groupReport(RECORDED, true);
    const status = (id: string) => groups.find((g) => g.def.id === id)!.status;
    expect(status('production')).toEqual({ tone: 'positive', label: '4 of 4 pass' });
    expect(status('web-applications')).toEqual({ tone: 'positive', label: '3 of 3 pass' });
    expect(status('agents')).toEqual({ tone: 'neutral', label: '2 not on the recorded instance' });
    expect(status('cases')).toEqual({ tone: 'neutral', label: '1 not on the recorded instance' });
    expect(status('installation')).toBeNull();
    const live = groupReport({ ...RECORDED, production_class: false }, false).groups;
    expect(live[0].status).toEqual({ tone: 'blocking', label: '3 of 4 pass' });
    expect(live[0].edge).toBe('blocking');
    // A live installation with no purge task is a row to look at
    expect(live.find((g) => g.def.id === 'cases')!.status).toEqual({
      tone: 'attention',
      label: '1 to check',
    });
    // A site install has three checks in Production and two in Web applications
    const site = groupReport({ ...RECORDED, demo: false }, false).groups;
    expect(site[0].status?.label).toBe('3 of 3 pass');
    expect(site[1].status?.label).toBe('2 of 2 pass');
  });
});

describe('the row rule', () => {
  const info = (key: string, value: unknown, trial = false, report: Report = RECORDED) =>
    rowInfo(key, value, report, trial);

  it('marks a core check that passes as positive and one that fails as blocking, with what to do', () => {
    expect(info('production_class', true)).toMatchObject({ mark: 'check', tone: 'positive' });
    expect(info('production_class', false)).toMatchObject({
      mark: 'x',
      tone: 'blocking',
      todo: 'Compile the production class, then reload.',
    });
    expect(info('production_state', 'running')).toMatchObject({ mark: 'check' });
    expect(info('production_state', 'stopped')).toMatchObject({ mark: 'x', tone: 'blocking' });
  });

  it('marks another yes as a check and another no as neutral, with the chip only for the pieces the recording lacked', () => {
    expect(info('demo', true)).toMatchObject({ mark: 'check', tone: 'positive' });
    expect(info('records_namespace', false)).toEqual({ mark: 'dash', tone: 'neutral', missing: false });
    const hub = info('ai_hub_present', false, true);
    expect(hub).toMatchObject({ mark: 'dash', tone: 'neutral' });
    expect(hub.reason).toMatchObject({ chip: 'Not on the recorded instance', tone: 'neutral' });
    expect(hub.reason?.note).toBe(
      "This report is from the instance that served the cases, which had no AI Hub. The board's runs were recorded with the real agents on the AI Hub build and replay here.",
    );
    // Outside the trial the same No is a plain No
    expect(info('ai_hub_present', false, false)).toEqual({ mark: 'dash', tone: 'neutral', missing: false });
    // A check that is core on a demo installation is only a yes or a no on a site's
    const site = { ...RECORDED, demo: false };
    expect(info('ward_classes', false, false, site)).toEqual({
      mark: 'dash',
      tone: 'neutral',
      missing: false,
    });
  });

  it('treats a missing message purge task as attention live and as a recorded absence in the trial', () => {
    const live = info('purge_task', false, false);
    expect(live).toMatchObject({ mark: 'dash', tone: 'attention' });
    expect(live.reason).toMatchObject({ chip: 'No message purge task', tone: 'attention' });
    expect(info('purge_task', false, true).reason?.chip).toBe('Not on the recorded instance');
    expect(info('purge_task', true, false)).toMatchObject({ mark: 'check', tone: 'positive' });
  });

  it('reads the credential checks as records, with the fields the report left out empty', () => {
    expect(credentialChecks(CREDENTIALS)).toEqual(CREDENTIALS);
    expect(credentialChecks([{ name: 'DownstreamAPI', ok: 1 }])).toEqual([
      { namespace: '', name: 'DownstreamAPI', user: '', status: '', detail: '', ok: false },
    ]);
    expect(credentialChecks('not a list')).toEqual([]);
    expect(info('credentials', [])).toEqual({ mark: 'none', tone: null, missing: false });
  });

  it("reads a null for the provider's pieces as the reader's right or the edition, never as a gap", () => {
    // On the AI Hub edition the Doctor sends null to a reader without the wallet's or the Config Store's right
    const hub = { ...RECORDED, ai_hub_present: true };
    const wallet = info('wallet_secret', null, false, hub);
    expect(wallet).toMatchObject({ mark: 'dash', tone: 'neutral', missing: false });
    expect(wallet.reason).toMatchObject({ chip: 'Not visible to you', tone: 'neutral' });
    expect(wallet.reason?.note).toContain('Shutter_Secrets');
    expect(info('provider_config', null, false, hub).reason?.note).toContain('%Admin_ConfigStore');
    // In the replay edition there is no wallet and no Config Store, so the same null is the edition
    const core = { ...RECORDED, ai_hub_present: false };
    expect(info('wallet_secret', null, false, core).reason).toMatchObject({
      chip: 'Not in this edition',
      tone: 'neutral',
    });
    expect(info('provider_config', null, true, core).reason?.chip).toBe('Not in this edition');
    // A true or a false is what the instance holds, and a key the report never sent is still a gap
    expect(info('wallet_secret', true, false, hub)).toMatchObject({ mark: 'check', tone: 'positive' });
    expect(info('wallet_secret', false, false, hub)).toEqual({
      mark: 'dash',
      tone: 'neutral',
      missing: false,
    });
    expect(info('provider_config', undefined, false, hub)).toMatchObject({
      mark: 'dash',
      tone: 'attention',
      missing: true,
    });
  });

  it('says a value the report did not send is attention, and gives names, paths and numbers no mark', () => {
    expect(info('adt_in', null)).toMatchObject({ mark: 'dash', tone: 'attention', missing: true });
    expect(info('adt_in', '')).toMatchObject({ missing: true });
    expect(info('adt_in', '/usr/irissys/mgr/shutter/in/')).toMatchObject({ mark: 'none', tone: null });
    expect(info('cases', 53)).toMatchObject({ mark: 'none' });
    // The API mimic's switch is empty when it is off: a setting, not a gap
    expect(info('mock_config', '')).toMatchObject({ mark: 'none', missing: false });
    expect(info('portal_hardened_at', '')).toMatchObject({ mark: 'none', missing: false });
    expect(info('portal_hardening_errors', '')).toMatchObject({ mark: 'none', missing: false });
    expect(info('portal_hardening_errors', '%Admin_Secure is required')).toMatchObject({
      mark: 'dash',
      tone: 'attention',
      missing: false,
    });
  });

  it('reads an empty provider as not configured on the AI Hub edition and as the edition in the replay one', () => {
    const hub = { ...RECORDED, ai_hub_present: true };
    const unset = info('provider', '', false, hub);
    expect(unset).toMatchObject({ mark: 'dash', tone: 'neutral', missing: false });
    expect(unset.reason).toMatchObject({ chip: 'Not configured', tone: 'neutral' });
    expect(unset.reason?.note).toContain('ANTHROPIC_API_KEY');
    const core = { ...RECORDED, ai_hub_present: false };
    expect(info('provider', '', false, core)).toMatchObject({
      mark: 'dash',
      tone: 'neutral',
      missing: false,
    });
    expect(info('provider', '', true, core).reason?.chip).toBe('Not in this edition');
    // A name is the provider the install recorded; a key the report never sent is still a gap
    expect(info('provider', 'AI.LLM.Shutter', false, hub)).toMatchObject({ mark: 'none', tone: null });
    expect(info('provider', undefined, false, hub)).toMatchObject({ tone: 'attention', missing: true });
  });

  it('marks a credential check that threw as attention and fails its core check', () => {
    const thrown = {
      ...RECORDED,
      credentials_ok: true,
      credentials_state: 'error: <THROW> reading the credential cache',
      credentials_checked_at: '',
      credentials: [],
    };
    const state = info('credentials_state', thrown.credentials_state, false, thrown);
    expect(state).toMatchObject({ mark: 'dash', tone: 'attention', missing: false });
    expect(state.reason).toMatchObject({ chip: 'Check did not run', tone: 'attention' });
    expect(info('credentials_ok', true, false, thrown)).toMatchObject({ mark: 'x', tone: 'blocking' });
    expect(info('credentials_state', 'fresh', false, { ...thrown, credentials_state: 'fresh' })).toEqual({
      mark: 'none',
      tone: null,
      missing: false,
    });
    const group = groupReport(thrown, false).groups.find((g) => g.def.id === 'credentials')!;
    expect(group.status).toEqual({ tone: 'blocking', label: '0 of 1 pass' });
    expect(group.edge).toBe('blocking');
  });
});

describe('the kind rule', () => {
  /** A group's rows of one kind, by key. */
  const kinds = (report: Report, trial: boolean, id: string) => {
    const group = groupReport(report, trial).groups.find((g) => g.def.id === id)!;
    return {
      checks: group.rows.filter((r) => r.kind === 'check').map((r) => r.key),
      details: group.rows.filter((r) => r.kind === 'detail').map((r) => r.key),
    };
  };

  it('puts the checks first and the names, paths, numbers and facts in the details, group by group', () => {
    expect(kinds(RECORDED, true, 'production')).toEqual({
      checks: ['interoperability', 'production_class', 'production_state', 'ward_classes'],
      details: ['shutter_production', 'adt_in', 'mode'],
    });
    expect(kinds(RECORDED, true, 'web-applications')).toEqual({
      checks: ['api_webapp', 'ui_webapp', 'wards_webapp'],
      details: ['webapps_checked'],
    });
    // A yes or no that is not a core check is still a check; the default board is a detail of the library's
    expect(kinds(RECORDED, true, 'agents')).toEqual({
      checks: ['ai_hub_present', 'aihub_runner'],
      details: ['board_members', 'default_board', 'recordings'],
    });
    expect(kinds(RECORDED, true, 'cases')).toEqual({ checks: ['purge_task'], details: ['cases'] });
    // The demo installation is a fact about the installation, never a check: this group has only details
    expect(kinds(RECORDED, true, 'installation')).toEqual({
      checks: [],
      details: ['namespace', 'version', 'installed_at', 'demo', 'license'],
    });
  });

  it('keeps the group links true: a group counts its core checks, which are the first of its checks', () => {
    const { groups } = groupReport(RECORDED, true);
    for (const g of groups) {
      const checks = g.rows.filter((r) => r.kind === 'check').map((r) => r.key);
      expect(checks.slice(0, g.checks.length)).toEqual(g.checks.map((c) => c.key));
      for (const r of g.rows.filter((r) => r.kind === 'detail'))
        expect(g.checks.some((c) => c.key === r.key)).toBe(false);
    }
  });

  it('makes a row to fix or to look at a check wherever it sits, and a plain fact a detail', () => {
    const live = {
      ...RECORDED,
      adt_in: null,
      edition: 'aihub',
      missing_items: ['Scenario Player'],
      disabled_items: [],
      purge_task: false,
    };
    const production = kinds(live, false, 'production');
    // Not reported and an item missing from the production are checks; the edition and "None" are details
    expect(production.checks).toEqual([
      'interoperability',
      'production_class',
      'production_state',
      'ward_classes',
      'adt_in',
      'missing_items',
    ]);
    expect(production.details).toEqual(['shutter_production', 'mode', 'edition', 'disabled_items']);
    expect(kinds(live, false, 'cases').checks).toEqual(['purge_task']);
    expect(
      kinds({ ...live, edition: 'broken: aihub module without AI Hub' }, false, 'production').checks,
    ).toContain('edition');
    expect(kinds({ ...live, disabled_items: ['Case Releaser'] }, false, 'production').checks).toContain(
      'disabled_items',
    );
  });

  it('keeps the stored credentials tried a check whether they all sign in or not, with the state and time as details', () => {
    const report = {
      ...RECORDED,
      credentials_ok: true,
      credentials_state: 'fresh',
      credentials_checked_at: '2026-11-03T10:00:00Z',
      credentials: CREDENTIALS.filter((c) => c.ok),
    };
    expect(kinds(report, false, 'credentials')).toEqual({
      checks: ['credentials_ok', 'credentials'],
      details: ['credentials_state', 'credentials_checked_at'],
    });
    const stale = { ...report, credentials_ok: false, credentials_state: 'stale', credentials: CREDENTIALS };
    expect(kinds(stale, false, 'credentials').checks).toEqual(['credentials_ok', 'credentials']);
    // A check that threw puts its state among the checks, since it wants a look
    const thrown = {
      ...report,
      credentials_state: 'error: <THROW> reading the credential cache',
      credentials: [],
    };
    expect(kinds(thrown, false, 'credentials')).toEqual({
      checks: ['credentials_ok', 'credentials_state'],
      details: ['credentials_checked_at', 'credentials'],
    });
  });

  it("keeps the provider and its pieces checks while they carry a reason, and the downstream system's pieces facts off a demo", () => {
    const hub = {
      ...RECORDED,
      ai_hub_present: true,
      provider: '',
      wallet_secret: null,
      provider_config: null,
    };
    expect(kinds(hub, false, 'agents').checks).toEqual([
      'ai_hub_present',
      'aihub_runner',
      'provider',
      'wallet_secret',
      'provider_config',
    ]);
    // A named provider is a fact; its pieces as a yes or a no are still checks
    const named = { ...hub, provider: 'AI.LLM.Shutter', wallet_secret: true, provider_config: false };
    expect(kinds(named, false, 'agents')).toMatchObject({
      checks: ['ai_hub_present', 'aihub_runner', 'wallet_secret', 'provider_config'],
      details: ['board_members', 'default_board', 'recordings', 'provider'],
    });
    // On a site's installation the downstream system's classes and web application are facts about the demo
    const site = { ...RECORDED, demo: false, ward_classes: false };
    expect(kinds(site, false, 'production').details).toContain('ward_classes');
    expect(kinds(site, false, 'web-applications').details).toEqual(['wards_webapp', 'webapps_checked']);
    // Unless the report left one out, which wants a look wherever it sits
    expect(kinds(without(site, 'wards_webapp'), false, 'web-applications').details).toEqual([
      'webapps_checked',
    ]);
    expect(kinds({ ...site, wards_webapp: null }, false, 'web-applications').checks).toContain(
      'wards_webapp',
    );
  });
});

describe('the licence', () => {
  it('is one sentence built from the fields as the report names them, with no sum', () => {
    expect(licenceSentence(RECORDED.license)).toBe(
      'Concurrent User licence: 1 unit consumed, 7 available, up to 25 connections',
    );
    expect(licenceSentence({ license_type: 'Concurrent User', units_consumed: 3, max_connections: 1 })).toBe(
      'Concurrent User licence: 3 units consumed, up to 1 connection',
    );
  });

  it('leaves out a field the report did not send, and says when the licence could not be read', () => {
    expect(licenceSentence({ units_consumed: 1 })).toBe('Licence: 1 unit consumed');
    expect(licenceSentence({ error: 'No licence key' })).toBe('The licence could not be read.');
    expect(licenceSentence(null)).toBeNull();
    expect(licenceSentence('Concurrent User')).toBeNull();
  });
});

describe('the agents badge', () => {
  it('says the agents run on IRIS AI Hub when both pieces are there', () => {
    expect(agentsBadge({ ai_hub_present: true, aihub_runner: true }, false, null)).toEqual({
      kind: 'on-hub',
      tone: 'info',
      label: 'Agents run on IRIS AI Hub',
    });
  });

  it('says the board was recorded on IRIS AI Hub and replays here, with the build, in the trial and the demo build', () => {
    const b = agentsBadge({ ai_hub_present: false, aihub_runner: false }, true, RECORDED_ON);
    expect(b).toEqual({
      kind: 'recorded',
      tone: 'neutral',
      label: 'Board runs recorded on IRIS AI Hub (build 154); replayed here',
      hint: 'Recorded on irishealth-community:2026.3.0AI.154.0',
    });
    // One piece missing is enough
    expect(agentsBadge({ ai_hub_present: true, aihub_runner: false }, true, RECORDED_ON)?.kind).toBe(
      'recorded',
    );
    // An evaluation with no build leaves the build out
    expect(agentsBadge({ ai_hub_present: false }, true, null)?.label).toBe(
      'Board runs recorded on IRIS AI Hub; replayed here',
    );
  });

  it('says a live installation replays recordings and needs IRIS AI Hub to run them', () => {
    expect(agentsBadge({ ai_hub_present: false, aihub_runner: false }, false, RECORDED_ON)).toEqual({
      kind: 'replays',
      tone: 'info',
      label: 'Agents replay recordings; running them needs IRIS AI Hub',
    });
  });

  it('says nothing when the report does not say, and never says AI Hub is not needed', () => {
    expect(agentsBadge({}, true, RECORDED_ON)).toBeNull();
    expect(agentsBadge({ ai_hub_present: true }, false, null)).toBeNull();
    const all = [
      agentsBadge({ ai_hub_present: true, aihub_runner: true }, false, null),
      agentsBadge({ ai_hub_present: false, aihub_runner: false }, true, RECORDED_ON),
      agentsBadge({ ai_hub_present: false, aihub_runner: false }, false, RECORDED_ON),
    ];
    for (const b of all) expect(`${b?.label} ${b?.hint ?? ''}`).not.toMatch(/not needed|optional/i);
  });
});

describe('the provenance', () => {
  it('reads when the recording was read from the text, and writes times to the minute in UTC', () => {
    expect(recordedAt(RECORDED.recorded)).toBe('2026-10-20T17:55:04Z');
    expect(recordedAt('No time here')).toBeNull();
    expect(recordedAt(undefined)).toBeNull();
    expect(utcMinute('2026-10-20T17:55:04Z')).toBe('20 Oct 2026, 17:55 UTC');
  });

  it('splits the text into one fact per line: when it was read, what it holds, what was recorded later', () => {
    expect(provenanceFacts(RECORDED.recorded)).toEqual([
      "Recorded from Shutter's REST API at 20 Oct 2026, 17:55 UTC",
      '53 cases (14 by rules alone, 26 in site-policy mode, 13 by the board of specialists) and 2 incidents',
      "The board's 64 agent runs are replays of recorded runs",
      "S22's two cases, one per receiver, were recorded at 26 Oct 2026, 02:13 UTC in site-policy mode from a test instance with the patient records system.",
      'The demo serves these answers in the browser; nothing in it reaches an IRIS instance.',
    ]);
    expect(provenanceFacts(undefined)).toEqual([]);
    expect(provenanceFacts('  ')).toEqual([]);
  });
});

describe('the model budget', () => {
  const budget = { dailyUsd: 5, spentTodayUsd: 1.5, exhausted: false };
  it('says "today" on an installation and "since the demo last reset" on the public demo', () => {
    expect(budgetLine(budget, {})).toBe("$1.50 of today's $5.00 spent on live runs");
    expect(budgetLine(budget, { live: { enabled: true } })).toBe(
      '$1.50 of the $5.00 per reset spent on live runs since the demo last reset (every hour)',
    );
    expect(budgetLine(null, {})).toBeNull();
  });
});
