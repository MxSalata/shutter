#!/usr/bin/env node
/**
 * Records the demo's data from a running Shutter: signs in to the REST API (docs/CONTRACTS.md, section 5), reads
 * every read route for the scenarios, every case, every incident, every production review, the library, the settings, the
 * costs and the health report, and writes them to src/mocks/fixtures.json, which the in-browser mock serves in the demo build and the tests.
 * The precedents (CONTRACTS 6.4) are kept once each, from every kept case's GET /cases/{id}/precedents, as one list
 * newest first: the mock answers a case's route from it as the store stood when the case's evidence was collected.
 *
 *   node scripts/record-demo.mjs [--url http://localhost:52773] [--user operator] [--out src/mocks/fixtures.json]
 *                                [--cases C-000002,C-000008,...] [--incidents I-000001,...] [--reviews PR-000001,...]
 *                                [--ids ids.json] [--allow-unmapped]
 *
 * --cases keeps only the cases named (one per scenario and mode reads better than every rehearsal of the same run),
 * and the costs are then those of the kept cases' runs. --incidents keeps only the incidents named; the cases a kept
 * incident holds are kept with it, so its chains link to them. --reviews keeps only the production reviews named, and
 * their agent runs are then the costs' byReview.
 * --ids names a JSON file that maps the instance's case, incident and review ids to the demo's ({"C-000155":
 * "C-000002", "I-000009": "I-000001", "PR-000018": "PR-000001", ...}), so a re-recording keeps the ids the tests and the
 * guide name. --cases, --incidents and --reviews still name the instance's ids. The map is applied to every id
 * written, wherever it stands: keys, fields, lists and texts (events, plans, approvals, headlines, chains, links,
 * costs). A replayed agent run keeps the ids of the case it was recorded on (its tool calls' arguments, its answer, the
 * plan the coordinator's answer wrote): where the instance's case of such an id tells the same story as the kept case
 * (the same operation key and receiver), it is rewritten in that case's runs and plan to the case's own id, and the
 * recording's incident to the case's own incident, as export-recorded-answers.mjs does for the recorded answers. Two
 * lists are trimmed first: a review's latest cases (its case aggregates, overall and per finding) keep only the cases
 * the map names, their counts staying the instance's, and with --cases the scenarios carry no latestCase, which the
 * mock works out from the kept cases. Any other id of those kinds that the map does not name stops the export, since
 * it would point at a case the demo does not have, or at a different one; --allow-unmapped lists them and writes the
 * file anyway.
 * The password comes from SHUTTER_PASSWORD (default: the demo installer's "shutter"). Only reads: nothing is
 * changed on the instance. Node 22 or later (fetch).
 */
import { readFileSync, writeFileSync } from 'node:fs';

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
const onlyIncidents = args.incidents ? new Set(args.incidents.split(',').map((i) => i.trim())) : null;
const onlyReviews = args.reviews ? new Set(args.reviews.split(',').map((r) => r.trim())) : null;
const idMap = args.ids ? JSON.parse(readFileSync(args.ids, 'utf8')) : null;
// A boolean flag takes no value: the reduce above pairs it with the next argument, so it is looked for on its own
const allowUnmapped = process.argv.includes('--allow-unmapped');

let cookie = '';

async function call(method, path, body) {
  // In English: Node's fetch asks for any language, and IRIS then words its own error texts (a health probe's) in the
  // first it has, Arabic
  const headers = { Accept: 'application/json', 'Accept-Language': 'en' };
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
// The incidents first: with --cases, the cases a kept incident holds are kept too. An instance without the routes
// answers 404, and the demo then has no incidents.
const incidents = {};
const incidentList = await read('/incidents?limit=500');
for (const summary of incidentList?.items ?? []) {
  if (onlyIncidents && !onlyIncidents.has(summary.incidentId)) continue;
  const id = encodeURIComponent(summary.incidentId);
  const detail = await read(`/incidents/${id}`);
  incidents[summary.incidentId] = { summary, detail, events: await read(`/incidents/${id}/events`) };
  for (const chain of detail?.chains ?? []) for (const item of chain.items ?? []) only?.add(item.caseId);
}
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
// Every precedent the kept cases' conditions match, once each, newest first. An instance before v1.35 answers 404.
const precedentRows = new Map();
for (const summary of kept)
  for (const p of (await read(`/cases/${encodeURIComponent(summary.caseId)}/precedents`))?.precedents ?? [])
    precedentRows.set(String(p.id), p);
const precedents = [...precedentRows.values()].sort(
  (a, b) => b.createdAt.localeCompare(a.createdAt) || Number(b.id) - Number(a.id),
);
// The production reviews (CONTRACTS 13): the targets, the list and each review as GET answers it. An instance without
// the routes answers 404, and the demo then has no reviews.
const reviewTargets = await read('/production-reviews/targets');
const reviewList = await read('/production-reviews?limit=500');
const keptReviews = (reviewList?.items ?? []).filter((r) => !onlyReviews || onlyReviews.has(r.reviewId));
const reviews = {};
for (const item of keptReviews)
  reviews[item.reviewId] = await read(`/production-reviews/${encodeURIComponent(item.reviewId)}`);

const recordedAt = new Date().toISOString().replace(/\.\d+Z$/, 'Z');

// What the kept cases are, said from their own runs: live (or recorded live) agent runs, or replays.
const runs = kept.flatMap((c) => cases[c.caseId].runs ?? []);
const liveRuns = runs.filter((r) => r.mode === 'live' || r.mode === 'record');
const models = [...new Set(liveRuns.map((r) => r.model))].join(', ');
const MODE_WORDS = {
  board: 'by the board of specialists',
  single: 'by one agent',
  rules: 'by rules alone',
  policy: 'in site-policy mode',
};
const modeCounts = kept.reduce((m, c) => ({ ...m, [c.mode]: (m[c.mode] ?? 0) + 1 }), {});
const byMode = Object.entries(modeCounts)
  .map(([mode, n]) => `${n} ${MODE_WORDS[mode] ?? mode}`)
  .join(', ');
const incidentCount = Object.keys(incidents).length;
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
  // The reviews whose agent answered (any mode), newest first, as the route lists them apart from the board's runs
  const byReview = Object.values(reviews)
    .filter((r) => r?.agent?.mode)
    .sort((a, b) => b.startedAt.localeCompare(a.startedAt))
    .map((r) => ({
      reviewId: r.reviewId,
      production: r.production,
      model: r.agent.model ?? '',
      mode: r.agent.mode,
      costUsd: r.agent.mode === 'replay' ? 0 : (r.agent.costUsd ?? 0),
      startedAt: r.startedAt,
    }));
  totals.spentUsd += byReview.reduce((sum, r) => sum + r.costUsd, 0);
  const sorted = (rows, key) => rows.sort((a, b) => key(a).localeCompare(key(b)));
  return {
    totals: { ...totals, spentUsd: usd(totals.spentUsd), reviewRuns: byReview.length },
    byModel: sorted([...byModel.values()], (m) => `${m.model}|${m.mode}`).map((m) => ({
      ...m,
      costUsd: usd(m.costUsd),
    })),
    byDay: sorted([...byDay.values()], (d) => d.day).map((d) => ({ ...d, costUsd: usd(d.costUsd) })),
    byCase: sorted(byCase, (c) => c.caseId).reverse(),
    byReview,
  };
}

const health = await read('/health');
// Where it was recorded, and what the agent did with the reviews, in the source's words
const onHub = health?.ai_hub_present === true ? ' on an instance with IRIS AI Hub' : '';
const ranked = Object.values(reviews).filter((r) => r?.agent?.state === 'ok');
const rankedWords = ranked.length
  ? `, ${ranked.length} ranked by the agent${ranked.every((r) => r.agent.mode === 'replay') ? ' in replays of recorded runs' : ''}`
  : '';
const reviewWords = keptReviews.length
  ? `; ${keptReviews.length} production review${keptReviews.length === 1 ? '' : 's'}${rankedWords}`
  : '';

const fixtures = {
  source: `Recorded from Shutter's REST API${onHub} at ${recordedAt}: ${kept.length} cases (${byMode})${incidentCount ? ` and ${incidentCount} incident${incidentCount === 1 ? '' : 's'}` : ''}; ${agents}${reviewWords}. The demo serves these answers in the browser; nothing in it reaches an IRIS instance.`,
  recordedAt,
  // With --cases a scenario's latest case may be one the demo does not keep: the mock works it out from the kept cases
  scenarios: (Array.isArray(scenarios) ? scenarios : scenarios.scenarios).map(({ latestCase, ...s }) => ({
    ...s,
    ...(only ? {} : { latestCase }),
    steps: s.steps.map(({ path: _path, ...step }) => step),
  })),
  cases,
  incidents,
  library: await read('/library'),
  settings: await read('/settings'),
  costs: only || onlyReviews ? costsOfKept() : await read('/costs'),
  health,
  siteProfile: await read('/site-profile'),
  siteProfileHistory: await read('/site-profile/history'),
  productionReviews: { targets: reviewTargets?.items ?? [], list: keptReviews, reviews },
  precedents,
};
await call('DELETE', '/session');

/** A case, incident or review id as the API writes it, as a whole word. */
const ID = /\b(?:C|I|PR)-\d{6}\b/g;

/**
 * The ids of the cases and incidents the kept cases' replayed runs were recorded on, rewritten in those runs and the
 * case's plan to the case's own (and its incident's), once the instance confirms the recorded case is the same story.
 * Returns what it rewrote, for the console.
 */
async function ownRecordings(data) {
  const rewritten = [];
  const stories = new Map();
  const storyOf = async (id) => {
    if (!stories.has(id)) stories.set(id, await read(`/cases/${encodeURIComponent(id)}`));
    return stories.get(id);
  };
  for (const [caseId, c] of Object.entries(data.cases)) {
    if (!c.runs?.length) continue;
    // The runs, and the plan the coordinator's recorded answer wrote
    const text = JSON.stringify([c.runs, c.plan]);
    const own = c.summary;
    const incident = own.incidentId || c.detail?.incidentId;
    const swap = {};
    for (const id of new Set(text.match(ID) ?? [])) {
      if (id === caseId || id in idMap) continue;
      if (id.startsWith('C-')) {
        const other = await storyOf(id);
        if (other && other.operationKey === own.operationKey && other.receiver === own.receiver)
          swap[id] = caseId;
      } else if (id.startsWith('I-') && incident) {
        const other = await read(`/incidents/${encodeURIComponent(id)}`);
        if (other && other.receiver === own.receiver) swap[id] = incident;
      }
    }
    if (!Object.keys(swap).length) continue;
    [c.runs, c.plan] = JSON.parse(text.replace(ID, (id) => swap[id] ?? id));
    rewritten.push(`${caseId}: ${Object.keys(swap).join(', ')}`);
  }
  return rewritten;
}

/**
 * The fixtures with the instance's ids rewritten to the demo's by --ids, everywhere they stand, the reviews' lists of
 * latest cases trimmed to the cases the map names first. The costs' byCase is sorted again on the demo's ids, newest
 * first, as the route sorts it.
 */
function mapped(data) {
  const known = (id) => id in idMap;
  const trim = (aggregate) => {
    if (Array.isArray(aggregate?.latest)) aggregate.latest = aggregate.latest.filter(known);
  };
  for (const review of Object.values(data.productionReviews?.reviews ?? {})) {
    for (const aggregate of Object.values(review?.caseAggregates ?? {})) trim(aggregate);
    for (const finding of review?.findings ?? []) trim(finding.cases);
  }
  const text = JSON.stringify(data);
  const unmapped = [...new Set(text.match(ID) ?? [])].filter((id) => !(id in idMap)).sort();
  if (unmapped.length) {
    const what = `${unmapped.length} id(s) the map does not name: ${unmapped.join(', ')}`;
    if (!allowUnmapped) throw new Error(`${what}. Add them to ${args.ids}, or pass --allow-unmapped.`);
    console.warn(`left as they are: ${what}`);
  }
  const result = JSON.parse(text.replace(ID, (id) => idMap[id] ?? id));
  result.costs?.byCase?.sort((a, b) => b.caseId.localeCompare(a.caseId));
  return result;
}

if (idMap) {
  await call('POST', '/session', { username: user, password });
  const rewritten = await ownRecordings(fixtures);
  await call('DELETE', '/session');
  if (rewritten.length)
    console.log(`the recordings' own ids, rewritten to the case's: ${rewritten.join('; ')}`);
}
writeFileSync(out, `${JSON.stringify(idMap ? mapped(fixtures) : fixtures, null, 1)}\n`);
console.log(
  `wrote ${out}: ${kept.length} cases, ${incidentCount} incidents, ${keptReviews.length} reviews, ${fixtures.scenarios.length} scenarios`,
);
