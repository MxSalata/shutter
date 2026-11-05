import { readFileSync, readdirSync, statSync } from 'node:fs';
import { join } from 'node:path';
import { describe, expect, it } from 'vitest';
import type { Can } from '@/api/types';
import {
  CHAPTERS,
  enabled,
  modesSay,
  pathOf,
  RANKED_REVIEW_RECORDED,
  SCOPES,
  stepAt,
  stepForRole,
  tourMinutes,
} from './registry';

/** Every source file of the app, read once: the guide's targets must be attributes the screens really carry. */
function sources(dir: string): string {
  return readdirSync(dir)
    .map((name) => join(dir, name))
    .map((path) =>
      statSync(path).isDirectory()
        ? sources(path)
        : /\.tsx?$/.test(path) && !/\.test\.tsx?$/.test(path) && !path.includes('features/guide')
          ? readFileSync(path, 'utf8')
          : '',
    )
    .join('\n');
}
const SOURCE = sources(join(__dirname, '..', '..'));

/** The case story's steps, as CaseStory's StoryStep type lists them. */
const STORY_STEPS = ['failed', 'evidence', 'proposed', 'decision', 'written', 'verified', 'compare'];

const STEPS = CHAPTERS.flatMap((c) => c.steps.map((s) => ({ c, s, path: pathOf(c, s) })));
const words = (s: string) => s.split(/\s+/).filter(Boolean).length;

describe('the guide registry', () => {
  it('has unique chapter ids and step ids within each chapter', () => {
    const ids = CHAPTERS.map((c) => c.id);
    expect(new Set(ids).size).toBe(ids.length);
    for (const c of CHAPTERS) expect(new Set(c.steps.map((s) => s.id)).size).toBe(c.steps.length);
  });

  it('makes the quick tour the 9 steps from a case to the proof, and the engineers tour 6', () => {
    expect(SCOPES.quick).toEqual([
      'scenarios/start',
      's2/receipt',
      's2/decision',
      's2/verified',
      's8/receipt',
      's8/compare',
      's8/ask',
      's20/receipt',
      'evaluation/headline',
    ]);
    expect(SCOPES.engineer).toEqual([
      's2/receipt-json',
      's2/gate',
      's8/evidence-cited',
      's8/compare',
      's8/trace',
      'evaluation/rules-differs',
    ]);
  });

  it("gives every screen every enabled step that is not the engineers' alone, one to four a chapter", () => {
    expect(RANKED_REVIEW_RECORDED).toBe(true);
    expect(SCOPES.all).toHaveLength(32);
    expect(SCOPES.all).toContain('review/agent');
    expect(SCOPES.all).toEqual(
      STEPS.filter(({ c, s }) => enabled(c, s) && !(s.scopes.length === 1 && s.scopes[0] === 'engineer')).map(
        (x) => x.path,
      ),
    );
    for (const c of CHAPTERS) {
      const n = SCOPES.all.filter((p) => p.startsWith(`${c.id}/`)).length;
      expect(n, c.id).toBeGreaterThan(0);
      expect(n, c.id).toBeLessThanOrEqual(4);
    }
  });

  it('points every step at a target a screen carries, by attribute, and every try-it at a control that has it', () => {
    // A story step's section carries data-tour={`case-${value}`}: only the story's own steps may lean on that form
    const story = SOURCE.includes('data-tour={`case-${value}`}');
    for (const { s, path } of STEPS) {
      const named =
        SOURCE.includes(`data-tour="${s.target}"`) ||
        SOURCE.includes(`tour="${s.target}"`) ||
        (story && s.target.startsWith('case-') && STORY_STEPS.includes(s.target.slice(5)));
      expect(named, `${path}: ${s.target}`).toBe(true);
      for (const a of [s.tryIt, s.chip].filter((x) => !!x)) {
        const marked =
          SOURCE.includes(`data-tour-action="${a.action}"`) ||
          SOURCE.includes(`tourAction="${a.action}"`) ||
          SOURCE.includes(`tourAction: '${a.action}'`) ||
          (a.action.startsWith('run-') && SOURCE.includes('data-tour-action={`run-${s.id}`}'));
        expect(marked, `${path}: ${a.action}`).toBe(true);
      }
    }
    // The finish card points at S20's Run button
    expect(SOURCE.includes('data-tour-action={`run-${s.id}`}')).toBe(true);
  });

  it('opens a story step or a tab only on a case', () => {
    for (const { s, path } of STEPS) if (s.open || s.tab) expect('scenario' in s.place, path).toBe(true);
  });

  it('keeps to its word budgets: title 6, say 25, detail 40, a try-it or chip 8', () => {
    for (const { s, path } of STEPS) {
      expect(words(s.title), `${path} title`).toBeLessThanOrEqual(6);
      expect(words(s.say), `${path} say`).toBeLessThanOrEqual(25);
      if (s.detail) expect(words(s.detail), `${path} detail`).toBeLessThanOrEqual(40);
      for (const a of [s.tryIt, s.chip].filter((x) => !!x))
        expect(words(a.text), `${path} ${a.action}`).toBeLessThanOrEqual(8);
    }
  });

  it('keeps the words a role reads instead to the same budgets', () => {
    for (const { s, path } of STEPS)
      for (const v of [s.lookOnly, s.noApprove, ...Object.values(s.whenCase ?? {})].filter((x) => !!x)) {
        expect(words(v.say), `${path} say`).toBeLessThanOrEqual(25);
        if (v.title) expect(words(v.title), `${path} title`).toBeLessThanOrEqual(6);
        if (v.detail) expect(words(v.detail), `${path} detail`).toBeLessThanOrEqual(40);
      }
  });

  it("tells each role only what it can do on the tour's S2 and Scenarios steps", () => {
    const can = (over: Partial<Can>): Can => ({
      operate: true,
      approve: true,
      configure: true,
      scenarios: true,
      liveAgents: false,
      ...over,
    });
    const operator = can({ approve: false, configure: false });
    const demo = can({ configure: false, scenarios: false });
    const decision = stepAt('s2/decision')!.step;
    expect(stepForRole(decision, can({})).tryIt?.action).toBe('approve-plan');
    expect(stepForRole(decision, demo).tryIt?.action).toBe('approve-plan');
    expect(stepForRole(decision, operator).tryIt).toBeUndefined();
    expect(stepForRole(decision, operator).title).toBe('An approver decides here');
    const verified = stepAt('s2/verified')!.step;
    expect(stepForRole(verified, can({})).say).toMatch(/That is verified: it landed/);
    expect(stepForRole(verified, operator).say).toMatch(/^Not approved, so nothing is written yet/);
    // Over the case as it stands: the tour never says a write landed that a person rejected or has not yet released
    expect(stepForRole(verified, can({}), 'resolved').say).toMatch(/That is verified: it landed/);
    expect(stepForRole(verified, can({}), 'awaiting_approval').say).toMatch(/^Not approved/);
    expect(stepForRole(verified, can({}), 'blocked').title).toBe('Rejected, so nothing written');
    expect(stepForRole(verified, can({}), 'blocked').say).not.toMatch(/verified|landed/);
    expect(stepForRole(decision, can({}), 'awaiting_approval').tryIt?.action).toBe('approve-plan');
    expect(stepForRole(decision, can({}), 'blocked').tryIt).toBeUndefined();
    expect(stepForRole(decision, can({}), 'blocked').title).toBe('The plan was rejected here');
    expect(stepForRole(stepAt('scenarios/start')!.step, can({})).say).toMatch(/Start with these three/);
    expect(stepForRole(stepAt('scenarios/start')!.step, demo).say).toMatch(/follows S2, S8 and S20/);
    expect(stepForRole(stepAt('scenarios/mode')!.step, demo).say).not.toMatch(/Choose/);
  });

  it('names the modes the page offers, with no single investigator on the trial', () => {
    expect(modesSay(false)).toMatch(/Board, Site policy, Single investigator or Rules only\./);
    expect(modesSay(true)).toMatch(
      /Board, Site policy, Single investigator \(not recorded\) or Rules only\./,
    );
    for (const trial of [false, true]) {
      expect(modesSay(trial)).toMatch(/^Choose/);
      // Who can't run one has nothing to choose for a run
      expect(modesSay(trial, false)).not.toMatch(/Choose/);
      for (const canRun of [false, true]) expect(words(modesSay(trial, canRun))).toBeLessThanOrEqual(25);
    }
  });

  it("says what a reason code is on the engineers' gate step, and that an unknown blocks", () => {
    const { step } = stepAt('s2/gate')!;
    expect(step.say).toMatch(/a reason code, a fixed name such as APPROVAL_RECEIVER_CHANGED/);
    expect(step.detail).toMatch(/An unknown answer blocks a write as surely as a failed one\.$/);
  });

  it('names the Workflow task on the approval step', () => {
    expect(stepAt('s2/decision')!.step.detail).toMatch(
      /The same approval is an EnsLib\.Workflow task in IRIS's Workflow inbox, for the role Shutter Approvers\.$/,
    );
  });

  it('names the two depths of Ask on the quick tour as the panel does, each in its own quotes', () => {
    const say = stepAt('s8/ask')!.step.say;
    expect(say).toMatch(/"Explain" is one agent, quick; "Ask the board" puts it to all four\.$/);
    expect(say).not.toMatch(/Explain answers/);
  });

  it('keeps the wording rules: no dashes, no exclamations, and never a person approving every write', () => {
    for (const { c, s } of STEPS) {
      const text = `${c.title} ${s.title} ${s.say} ${s.detail ?? ''} ${s.tryIt?.text ?? ''} ${s.chip?.text ?? ''}`;
      expect(text).not.toMatch(/[\u2013\u2014!]/);
      expect(text).not.toMatch(/a person (approves|releases) (every|each|all)/i);
      expect(text).not.toMatch(/\b(simply|just|easy|try anything|every action works)\b/i);
    }
    // Where a step speaks of releasing fixes in general, it names both a person and the written policy
    const general = STEPS.filter(({ s }) => /every (write|fix)/i.test(s.say));
    expect(general.length).toBeGreaterThan(0);
    for (const { s } of general) expect(s.say).toMatch(/a person, or the site's written policy/);
  });

  it('explains a word on the quick tour before it uses it', () => {
    const terms = ['gate', 'receiver', 'write', 'release', 'pass', 'production'];
    const known = new Set<string>();
    for (const path of SCOPES.quick) {
      const { step } = stepAt(path)!;
      for (const t of step.introduces ?? []) known.add(t);
      for (const t of terms.filter((x) => !known.has(x)))
        expect(`${step.title} ${step.say}`, `${path} uses "${t}" first`).not.toMatch(
          new RegExp(`\\b${t}\\b`, 'i'),
        );
    }
  });

  it('says how long each route takes from its own words, about 4 minutes for the quick tour', () => {
    expect(tourMinutes('quick')).toBe(4);
    expect(tourMinutes('engineer')).toBeGreaterThanOrEqual(2);
    expect(tourMinutes('all')).toBeGreaterThan(tourMinutes('quick'));
  });

  it('says what the pages say: a held case needs a person, and how many reviews are kept', () => {
    expect(stepAt('cases/closed')!.step.say).toMatch(/Escalated and blocked cases still wait for a person/);
    expect(stepAt('reviews/past')!.step.say).toMatch(/^The last 50 reviews of each production are kept/);
  });

  it('reads the proof and the costs from the evaluation, never typed', () => {
    expect(stepAt('evaluation/headline')!.step.say).toBe(
      "The board matched all 24 recorded failures. Played through on 11: board 11, Rules only 4. Of Rules only's 7 misses, the gate stopped 6.",
    );
    expect(stepAt('settings/costs')!.step.say).toMatch(/cost \$0\.34 to \$0\.50\.$/);
  });
});
