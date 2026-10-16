#!/usr/bin/env node
/**
 * Records the demo's data from a running Interlock: signs in to the REST API (docs/CONTRACTS.md, section 5), reads
 * every read route for the scenarios, every case, the library, the settings, the costs and the health report, and
 * writes them to src/mocks/fixtures.json, which the in-browser mock serves in the demo build and the tests.
 *
 *   node scripts/record-demo.mjs [--url http://localhost:52773] [--user operator] [--out src/mocks/fixtures.json]
 *
 * The password comes from INTERLOCK_PASSWORD (default: the demo installer's "interlock"). Only reads: nothing is
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
const base = `${(args.url ?? 'http://localhost:52773').replace(/\/$/, '')}/api/interlock`;
const user = args.user ?? 'operator';
const password = process.env.INTERLOCK_PASSWORD ?? 'interlock';
const out = args.out ?? 'src/mocks/fixtures.json';

let cookie = '';

async function call(method, path, body) {
  const headers = { Accept: 'application/json' };
  if (cookie) headers.Cookie = cookie;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  if (method !== 'GET') headers['X-Requested-With'] = 'Interlock';
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
for (const summary of list.items) {
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
const fixtures = {
  source: `Recorded from Interlock's REST API at ${recordedAt}: ${list.items.length} cases played in replay on a development instance. The demo serves these answers in the browser; nothing in it reaches an IRIS instance.`,
  recordedAt,
  scenarios: (Array.isArray(scenarios) ? scenarios : scenarios.scenarios).map((s) => ({
    ...s,
    steps: s.steps.map(({ path: _path, ...step }) => step),
  })),
  cases,
  library: await read('/library'),
  settings: await read('/settings'),
  costs: await read('/costs'),
  health: await read('/health'),
};
await call('DELETE', '/session');
writeFileSync(out, `${JSON.stringify(fixtures, null, 1)}\n`);
console.log(`wrote ${out}: ${list.items.length} cases, ${fixtures.scenarios.length} scenarios`);
