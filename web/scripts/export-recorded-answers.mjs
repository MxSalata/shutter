#!/usr/bin/env node
/**
 * Exports the demo's recorded answers to "Ask about this case": signs in to a running Shutter's REST API
 * (docs/CONTRACTS.md, sections 5 and 14), reads the questions that were asked for every turn of the scenarios' suggested
 * conversations (knowledge/questions/S*.json) in record mode, and writes them to src/mocks/recorded-questions.json,
 * which the in-browser mock serves in the demo build and the tests.
 *
 *   node scripts/export-recorded-answers.mjs [--url http://localhost:52773] [--user approver] [--out src/mocks/recorded-questions.json]
 *                                            [--fixtures src/mocks/fixtures.json] [--records ../fixtures/records]
 *                                            [--questions ../knowledge/questions]
 *
 * Run it from web/. The password comes from SHUTTER_PASSWORD (default: the demo installer's "shutter"). Only reads:
 * nothing is changed on the instance. Node 22 or later (fetch).
 *
 * What it does, per scenario that has suggested conversations AND a case in the demo's fixtures.json (a scenario with no
 * demo case is left out, with a note; record the case into fixtures.json with record-demo.mjs, then run this again):
 *   1. Lists the instance's cases for the scenario and their questions. For each receiver it takes the one case that
 *      has recorded answers for the most turns (the newest wins a tie), because a story's answers belong to one run.
 *      Of that case's questions it keeps, for each conversation and turn, the newest answered one whose mode is
 *      "record" (free questions, replays and failed attempts are ignored).
 *   2. Finds the demo case it stands for: the one in fixtures.json with the same scenario, receiver and mode (the
 *      lowest id if several). The instance's case ids, encounter ids, patient ids and source message ids are then
 *      rewritten to that demo case's own wherever the texts name them, so the panel never shows an id that does not
 *      match the case on screen. An id of those kinds that belongs to neither case stops the export.
 *   3. Reads each question (GET /cases/{id}/questions/{qid}) for the members' answers and what the core resolved, the
 *      case's What-if card (GET /cases/{id}/whatif; its profile version becomes the demo's site profile version), and
 *      the time each answer was recorded: recordedAt in the repository's fixtures/records/question-*.json, found by the
 *      question's recordKey.
 *   4. Replaces any em or en dash in the texts with "; " (or "-" between digits), as the repository's text check wants.
 *
 * Output: { recordedFrom, exportedAt, scenarios: { S8: { "Downstream Out": { caseId, whatif, questions: { "c1.3": {
 * question, tier, answer, memberAnswers, resolved, model, recordedAt } } } } } }. The key of "questions" is
 * "conversation.turn"; "answer" is the stored answer object (Answer for the Explain tier, BoardAnswer for the board).
 */
import { readFileSync, readdirSync, writeFileSync } from 'node:fs';
import { join } from 'node:path';

const args = Object.fromEntries(
  process.argv
    .slice(2)
    .reduce(
      (pairs, arg, i, all) => (arg.startsWith('--') ? [...pairs, [arg.slice(2), all[i + 1]]] : pairs),
      [],
    ),
);
const base = `${(args.url ?? 'http://localhost:52773').replace(/\/$/, '')}/api/shutter`;
const user = args.user ?? 'approver';
const password = process.env.SHUTTER_PASSWORD ?? 'shutter';
const out = args.out ?? 'src/mocks/recorded-questions.json';
const fixturesPath = args.fixtures ?? 'src/mocks/fixtures.json';
const recordsDir = args.records ?? '../fixtures/records';
const questionsDir = args.questions ?? '../knowledge/questions';

let cookie = '';

async function call(method, path, body) {
  // In English: Node's fetch asks for any language, and IRIS then words its own texts in the first it has, Arabic
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
  return { status: response.status, data: text ? JSON.parse(text) : null };
}

async function read(path) {
  const { status, data } = await call('GET', path);
  if (status !== 200) throw new Error(`GET ${path}: HTTP ${status} ${JSON.stringify(data)}`);
  return data;
}

const fixtures = JSON.parse(readFileSync(fixturesPath, 'utf8'));
const demoCases = Object.values(fixtures.cases)
  .map((c) => c.summary)
  .sort((a, b) => a.caseId.localeCompare(b.caseId));
const demoProfileVersion = fixtures.siteProfile.version;

/** The time each recording was made, by the record's key (question-*.json in fixtures/records). */
const recordedAtByKey = new Map();
for (const name of readdirSync(recordsDir).filter((n) => /^question-.*\.json$/.test(n))) {
  const record = JSON.parse(readFileSync(join(recordsDir, name), 'utf8'));
  recordedAtByKey.set(record.key, record.recordedAt);
}

const suggestedFiles = readdirSync(questionsDir)
  .filter((n) => /^S.*\.json$/.test(n))
  .map((n) => JSON.parse(readFileSync(join(questionsDir, n), 'utf8')));

const signIn = await call('POST', '/session', { username: user, password });
if (signIn.status !== 200) throw new Error(`Sign-in as ${user} failed: HTTP ${signIn.status}`);

/** The board's members in the order the board's cards show them; the instance lists them as they finished. */
const MEMBERS = ['conformance', 'encounter', 'impact'];
const ID_KINDS = [/\bC-\d{6}\b/g, /\bENC-\d+\b/g, /\bMRN\d+\b/g];

/** A text with the instance's ids swapped for the demo case's and any em or en dash removed. */
function tidy(text, ids) {
  return text
    .replace(/\b(?:C-\d{6}|ENC-\d+|MRN\d+|MSG\d+)\b/g, (id) => ids.get(id) ?? id)
    .replace(/(\d)\s*[\u2013\u2014]\s*(\d)/g, '$1-$2')
    .replace(/\s*[\u2013\u2014]\s*/g, '; ');
}

/** The same value with every string tidied. */
function walk(value, ids) {
  if (typeof value === 'string') return tidy(value, ids);
  if (Array.isArray(value)) return value.map((v) => walk(v, ids));
  if (value && typeof value === 'object')
    return Object.fromEntries(Object.entries(value).map(([k, v]) => [k, walk(v, ids)]));
  return value;
}

/** Every id of the three kinds that a value names, so the export can stop on one that is neither case's. */
function idsIn(value) {
  const text = JSON.stringify(value);
  return new Set(ID_KINDS.flatMap((re) => text.match(re) ?? []));
}

const scenarios = {};
const left = [];
for (const file of suggestedFiles) {
  const scenario = file.scenario;
  const demoOfScenario = demoCases.filter((c) => c.scenario === scenario);
  if (!demoOfScenario.length) {
    left.push(`${scenario}: no case in ${fixturesPath}`);
    continue;
  }
  const list = await read(`/cases?scenario=${encodeURIComponent(scenario)}&limit=100`);
  // Every case's recorded answers, then the one case per receiver with the most turns answered
  const candidates = [];
  for (const summary of list.items) {
    const { items } = await read(`/cases/${encodeURIComponent(summary.caseId)}/questions`);
    const newest = new Map();
    for (const q of items) {
      if (q.state !== 'answered' || q.mode !== 'record' || q.source !== 'suggested') continue;
      const key = `${q.conversation}.${q.turn}`;
      const had = newest.get(key);
      if (!had || (q.answeredAt ?? '') >= (had.answeredAt ?? '')) newest.set(key, q);
    }
    if (newest.size) {
      const latest = [...newest.values()]
        .map((q) => q.answeredAt ?? '')
        .sort()
        .at(-1);
      candidates.push({ summary, newest, latest });
    }
  }
  const receivers = [...new Set(candidates.map((c) => c.summary.receiver))];
  if (!receivers.length) left.push(`${scenario}: no recorded answers on the instance`);
  for (const receiver of receivers) {
    const best = candidates
      .filter((c) => c.summary.receiver === receiver)
      .sort((a, b) => b.newest.size - a.newest.size || b.latest.localeCompare(a.latest))[0];
    const { summary } = best;
    const demo = demoOfScenario.find((c) => c.receiver === receiver && c.mode === summary.mode);
    if (!demo) {
      left.push(`${scenario}, ${receiver}: no ${summary.mode}-mode case in ${fixturesPath}`);
      continue;
    }
    // The instance case's identifiers become the demo case's
    const detail = await read(`/cases/${encodeURIComponent(summary.caseId)}`);
    const ids = new Map();
    for (const key of ['caseId', 'encounterId', 'patientId', 'sourceMessageId'])
      if (detail[key] && demo[key]) ids.set(detail[key], demo[key]);

    const whatif = await read(`/cases/${encodeURIComponent(summary.caseId)}/whatif`);
    const questions = {};
    for (const [key, q] of [...best.newest].sort(([a], [b]) => a.localeCompare(b, 'en', { numeric: true }))) {
      const stored = await read(
        `/cases/${encodeURIComponent(summary.caseId)}/questions/${encodeURIComponent(q.questionId)}`,
      );
      const recordedAt = recordedAtByKey.get(stored.recordKey);
      if (!recordedAt)
        throw new Error(`No record in ${recordsDir} for ${stored.recordKey} (${q.questionId})`);
      questions[key] = walk(
        {
          question: stored.question,
          tier: stored.tier,
          answer: stored.answer,
          memberAnswers: [...stored.memberAnswers].sort(
            (a, b) => MEMBERS.indexOf(a.member) - MEMBERS.indexOf(b.member),
          ),
          resolved: stored.resolved,
          model: stored.model,
          recordedAt,
        },
        ids,
      );
    }
    const card = walk({ ...whatif, case_id: demo.caseId, profile_version: demoProfileVersion }, ids);

    // Nothing may name an encounter, patient or case that is not the demo case's
    const own = new Set([demo.caseId, demo.encounterId, demo.patientId]);
    const strangers = [...idsIn({ card, questions })].filter((id) => !own.has(id));
    if (strangers.length)
      throw new Error(
        `${scenario}, ${receiver}: the answers name ${strangers.join(', ')}, which are not ${demo.caseId}'s`,
      );
    (scenarios[scenario] ??= {})[receiver] = { caseId: demo.caseId, whatif: card, questions };
    console.log(
      `${scenario}, ${receiver}: ${summary.caseId} (${summary.mode}) -> ${demo.caseId}, ${Object.keys(questions).length} turns`,
    );
  }
}
for (const note of left) console.log(`left out: ${note}`);

const models = [
  ...new Set(
    Object.values(scenarios).flatMap((byReceiver) =>
      Object.values(byReceiver).flatMap((s) => Object.values(s.questions).map((q) => q.model)),
    ),
  ),
];
const exportedAt = new Date().toISOString().replace(/\.\d+Z$/, 'Z');
writeFileSync(
  out,
  `${JSON.stringify(
    {
      recordedFrom: `The suggested questions' answers recorded live with ${models.join(', ')} on a running Shutter, exported with scripts/export-recorded-answers.mjs. Each answer's recordedAt is the time its recording was made.`,
      exportedAt,
      scenarios,
    },
    null,
    2,
  )}\n`,
);
console.log(`wrote ${out}`);
