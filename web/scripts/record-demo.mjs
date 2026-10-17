#!/usr/bin/env node
/**
 * Records the demo's data from a running Shutter: signs in to the REST API (docs/CONTRACTS.md, section 5), reads
 * every read route for the scenarios, every case, the library, the settings, the costs and the health report, and
 * writes them to src/mocks/fixtures.json, which the in-browser mock serves in the demo build and the tests.
 *
 *   node scripts/record-demo.mjs [--url http://localhost:52773] [--user operator] [--out src/mocks/fixtures.json]
 *                                [--cases C-000002,C-000008,...]
 *
 * --cases keeps only the cases named (one per scenario and mode reads better than every rehearsal of the same run),
 * and the costs are then those of the kept cases' runs.
 * The password comes from SHUTTER_PASSWORD (default: the demo installer's "shutter"). Only reads: nothing is
 * changed on the instance. Node 22 or later (fetch).
 */
import { writeFileSync } from 'node:fs';

const args = Object.fromEntries(
  process.argv
    .slice(2)
    .reduce(
      (pairs, arg, i, all) => (arg.startsWith('--') ? [...pairs, [arg.slice(2), all[i + 1]]] : pairs),
      [],
    ),
);
const base = `${(args.url ?? 'http://localhost:52773').replace(/\/$/, '')}/api/shutter`;
const user = args.user ?? 'operator';
const password = process.env.SHUTTER_PASSWORD ?? 'shutter';
const out = args.out ?? 'src/mocks/fixtures.json';
const only = args.cases ? new Set(args.cases.split(',').map((c) => c.trim())) : null;

let cookie = '';

async function call(method, path, body) {
  const headers = { Accept: 'application/json' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (method !== 'GET') headers['X-Requested-With'] = 'Shutter';
  const response = await fetch(base + path, {
    method,
    headers,
    body: body === undefined ? undefined : JSON.stringify(body),
  });
  const setCookie = response.headers.getSetCookie?.() ?? [];
  if (setCookie.length) cookie = setCookie.map((c) => c.split(';')[0]).join('; ');
  const text = await response.text();
  const data = text ? JSON.parse(text) : null;
  return { status: response.status, data };
}

/** A read that may answer 404 (no plan yet, not closed, not blocked): null then. */
async function read(path) {
  const { status, data } = await call('GET', path);
  if (status === 404) return null;
  if (status !== 200) throw new Error(`GET ${path}: HTTP ${status} ${JSON.stringify(data)}`);
  return data;
}

const signIn = await call('POST', '/session', { username: user, password });
if (signIn.status !== 200) throw new Error(`Sign-in as ${user} failed: HTTP ${signIn.status}`);

const scenarios = await read('/scenarios');
const list = await read('/cases?limit=500');
const cases = {};
const kept = list.items.filter((c) => !only || only.has(c.caseId));
for (const summary of kept) {
  const id = encodeURIComponent(summary.caseId);
  const closed = ['resolved', 'blocked', 'escalated', 'failed'].includes(summary.state);
  cases[summary.caseId] = {
    summary,
    detail: await read(`/cases/${id}`),
    events: await read(`/cases/${id}/events`),
    snapshot: await read(`/cases/${id}/snapshot`),
    runs: await read(`/cases/${id}/runs`),
    plan: await read(`/cases/${id}/plan`),
    approvals: await read(`/cases/${id}/approvals`),
    attempts: await read(`/cases/${id}/attempts`),
    closure: closed ? await read(`/cases/${id}/closure`) : null,
    blockedReason: ['blocked', 'escalated'].includes(summary.state)
      ? await read(`/cases/${id}/blocked-reason`)
      : null,
  };
}
const recordedAt = new Date().toISOString().replace(/\.\d+Z$/, 'Z');

// What the kept cases are, said from their own runs: live (or recorded live) agent runs, or replays.
const runs = kept.flatMap((c) => cases[c.caseId].runs ?? []);
const liveRuns = runs.filter((r) => r.mode === 'live' || r.mode === 'record');
const models = [...new Set(liveRuns.map((r) => r.model))].join(', ');
const byBoard = kept.filter((c) => c.mode !== 'rules').length;
const agents =
  runs.length === 0
    ? 'no agent runs'
    : liveRuns.length === runs.length
      ? `the board's ${runs.length} agent runs are live runs with ${models}`
      : liveRuns.length === 0
        ? `the board's ${runs.length} agent runs are replays of recorded runs`
        : `${liveRuns.length} of the board's ${runs.length} agent runs are live runs with ${models}, the rest replays`;

/**
 * The costs route covers the whole instance; with --cases, the same shape from the kept cases' runs alone. As in the
 * route, a replay reuses a recording's tokens and spends nothing, and has rows of its own.
 */
function costsOfKept() {
  const usd = (n) => Math.round(n * 1e6) / 1e6;
  const byModel = new Map();
  const byDay = new Map();
  const byCase = [];
  const totals = { spentUsd: 0, liveRuns: 0, replayedRuns: 0 };
  for (const summary of kept) {
    const caseRuns = cases[summary.caseId].runs ?? [];
    if (!caseRuns.length) continue;
    let caseCost = 0;
    let caseReplays = 0;
    for (const r of caseRuns) {
      const replay = r.mode === 'replay';
      const cost = replay ? 0 : (r.costUsd ?? 0);
      const key = `${r.model}|${r.mode}`;
      const m = byModel.get(key) ?? {
        model: r.model,
        mode: r.mode,
        runs: 0,
        promptTokens: 0,
        completionTokens: 0,
        cacheReadTokens: 0,
        costUsd: 0,
      };
      m.runs += 1;
      m.promptTokens += r.promptTokens ?? 0;
      m.completionTokens += r.completionTokens ?? 0;
      m.cacheReadTokens += r.cacheReadTokens ?? 0;
      m.costUsd += cost;
      byModel.set(key, m);
      const day = (r.startedAt ?? '').slice(0, 10);
      const d = byDay.get(day) ?? { day, runs: 0, replayedRuns: 0, costUsd: 0 };
      d.runs += 1;
      d.replayedRuns += replay ? 1 : 0;
      d.costUsd += cost;
      byDay.set(day, d);
      caseCost += cost;
      caseReplays += replay ? 1 : 0;
      totals.spentUsd += cost;
      totals[replay ? 'replayedRuns' : 'liveRuns'] += 1;
    }
    byCase.push({
      caseId: summary.caseId,
      runs: caseRuns.length,
      replayedRuns: caseReplays,
      costUsd: usd(caseCost),
    });
  }
  const sorted = (rows, key) => rows.sort((a, b) => key(a).localeCompare(key(b)));
  return {
    totals: { ...totals, spentUsd: usd(totals.spentUsd) },
    byModel: sorted([...byModel.values()], (m) => `${m.model}|${m.mode}`).map((m) => ({
      ...m,
      costUsd: usd(m.costUsd),
    })),
    byDay: sorted([...byDay.values()], (d) => d.day).map((d) => ({ ...d, costUsd: usd(d.costUsd) })),
    byCase: sorted(byCase, (c) => c.caseId).reverse(),
  };
}

const fixtures = {
  source: `Recorded from Shutter's REST API at ${recordedAt}: ${kept.length} cases, ${byBoard} by the board of specialists and ${kept.length - byBoard} by rules alone; ${agents}. The demo serves these answers in the browser; nothing in it reaches an IRIS instance.`,
  recordedAt,
  scenarios: (Array.isArray(scenarios) ? scenarios : scenarios.scenarios).map((s) => ({
    ...s,
    steps: s.steps.map(({ path: _path, ...step }) => step),
  })),
  cases,
  library: await read('/library'),
  settings: await read('/settings'),
  costs: only ? costsOfKept() : await read('/costs'),
  health: await read('/health'),
};
await call('DELETE', '/session');
writeFileSync(out, `${JSON.stringify(fixtures, null, 1)}\n`);
console.log(`wrote ${out}: ${kept.length} cases, ${fixtures.scenarios.length} scenarios`);
