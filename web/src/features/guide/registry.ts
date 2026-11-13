import { scenariosHidden } from '@/api/can';
import type { Can, CaseState, Mode } from '@/api/types';
import { TRIAL } from '@/env/mode';
import type { StoryStep } from '@/features/cases/case/CaseStory';
import { PROOF } from '@/lib/proof';

/**
 * The guide's chapters and steps, for the three routes it offers in the trial: the quick tour (9 steps, from a case to
 * the proof), every screen, and the integration engineers' tour (6 steps, Technical on). A step names the page it
 * shows (a fixed page, or a case, incident or review found when the step opens), the `data-tour` target on that page
 * (its card is placed just before it), the case story step or tab to open first, and its words: a title of at most 6
 * words, `say` of at most 25 and an expert `detail` of at most 40. A step may invite an action (`tryIt`, the control's
 * `data-tour-action`) and offer one quiet detour (`chip`). Targets are attributes the screens carry, never positions.
 */
export type GuideScope = 'quick' | 'all' | 'engineer';

export type GuidePlace =
  /** A page of the app, with its own query if it needs one (`/evaluation?show=rules-differs`). */
  | { page: string }
  /** The newest case of the scenario, in the mode when one is given (in board mode if there is one, otherwise). */
  | { scenario: string; mode?: Mode }
  /** The newest incident. */
  | { incident: 'newest' }
  /** The newest finished production review. */
  | { review: 'newest' };

/** An action a step invites: the control's `data-tour-action`, and the chip's words (at most 8). */
export interface GuideAction {
  action: string;
  text: string;
}

/** The case page's tabs a step may open (`?tab=` in the case's address). */
export type CaseTab = 'evidence' | 'audit';

export interface GuideStep {
  id: string;
  title: string;
  say: string;
  /** For the expert, in the step's own Technical detail (kind data). */
  detail?: string;
  place: GuidePlace;
  /** The `data-tour` attribute of the section the step shows. */
  target: string;
  /** Where the card sits instead while the step invites a press: just above that control, when the section is long. */
  nearTry?: string;
  /** On a case page: the story step to open before the section is shown. */
  open?: StoryStep;
  /** On a case page: the tab to open. */
  tab?: CaseTab;
  tryIt?: GuideAction;
  chip?: GuideAction;
  /** The routes the step belongs to. */
  scopes: GuideScope[];
  /** The words this step explains first (the first-use rule of the quick tour). */
  introduces?: string[];
  /** The words instead, for a role that may not run scenarios (the public demo's). */
  lookOnly?: RoleWords;
  /** The words instead, for a role that may not approve (a site's operator): the step's try-it goes with them. */
  noApprove?: RoleWords;
  /** The words instead, while the step's case stands in one of these states: what the step says happened did not. */
  whenCase?: Partial<Record<CaseState, RoleWords>>;
}

/** What a role that can't do what a step assumes reads instead, within the same word budgets. */
export type RoleWords = Pick<GuideStep, 'say'> & Partial<Pick<GuideStep, 'title' | 'detail'>>;

/**
 * The step as this role reads it, over the case as it stands: nothing tells someone to do what their role can't, or that
 * it happened when it did not.
 */
export function stepForRole(step: GuideStep, can: Can, caseState?: CaseState): GuideStep {
  const asItStands = caseState && step.whenCase?.[caseState];
  if (asItStands) return { ...step, ...asItStands, tryIt: undefined };
  if (!can.approve && step.noApprove) {
    return { ...step, ...step.noApprove, tryIt: undefined };
  }
  return scenariosHidden(can) && step.lookOnly ? { ...step, ...step.lookOnly } : step;
}

/** S2's verified step while its plan still waits, whoever reads it: a chapter or Resume can land there before any decision. */
const NOT_YET_APPROVED =
  "Not approved, so nothing is written yet. Once an approver releases it, Shutter reads the bed system's own history to check the transfer landed.";

export type ChapterGroup = 'Operate' | 'Results' | 'Configure';

export interface GuideChapter {
  id: string;
  /** In sentence case, with no scenario code: "A transfer recovered". */
  title: string;
  /** The scenario's code, named after the words on every route but the quick tour's. */
  code?: string;
  /** The navigation's group the chapter's page sits in, for the chapter picker. */
  group: ChapterGroup;
  steps: GuideStep[];
}

/**
 * Whether the demo's recording holds a production review the agent ranked (DESIGN.md decision 6): it does since the
 * re-recording on the AI Hub instance, whose newest review of each production is ranked. Without one, the step about
 * the agent's ranking is left out of every route.
 */
export const RANKED_REVIEW_RECORDED = true;

const Q: GuideScope[] = ['quick', 'all'];
const A: GuideScope[] = ['all'];
const E: GuideScope[] = ['engineer'];

/** Step 9's sentence, from the evaluation's own figures (lib/proof.ts), never typed. */
function proofSay(): string {
  const b = PROOF.board;
  const p = PROOF.played;
  if (!b || !p)
    return "These figures come from runs recorded with the real agents. Each compares the board's choice with the expected action.";
  const matched = b.matched === b.scored ? `all ${b.scored}` : `${b.matched} of ${b.scored}`;
  const m = PROOF.rulesMisses;
  const stopped = m?.total ? ` Of Rules only's ${m.total} misses, the gate stopped ${m.stopped.length}.` : '';
  return `The board matched ${matched} recorded failures. Played through on ${p.of}: board ${p.board}, Rules only ${p.rules}.${stopped}`;
}

/** "From 100 runs recorded with the real agents on IRIS AI Hub, 25 Oct to 1 Nov 2026." and what a match means. */
function proofDetail(): string {
  const day = (iso: string | null) =>
    iso
      ? new Date(iso).toLocaleDateString('en-GB', { day: 'numeric', month: 'short', timeZone: 'UTC' })
      : null;
  const year = PROOF.recordedTo ? new Date(PROOF.recordedTo).getUTCFullYear() : null;
  const from = day(PROOF.recordedFrom);
  const to = day(PROOF.recordedTo);
  const when = from && to && year ? `, ${from} to ${to} ${year}` : '';
  const runs = PROOF.runs ?? 'the';
  return `From ${runs} runs recorded with the real agents on IRIS AI Hub${when}. A match is agreement with each scenario's expected outcome, not general reliability.`;
}

/** "A board pass with real agents cost $0.34 to $0.50.", or nothing when the evaluation does not say. */
function costSay(): string {
  const c = PROOF.costPerPass;
  const range = c ? ` A board pass with real agents cost $${c.min.toFixed(2)} to $${c.max.toFixed(2)}.` : '';
  return `Costs come from list prices and the tokens used: estimates, not invoices.${range}`;
}

/**
 * The mode step's words, naming the four modes the page shows; the trial has no recording of the single investigator
 * (ScenariosPage). `canRun`: a role that can't run a scenario picks a mode only to read the list in it.
 */
export function modesSay(trial: boolean, canRun = true): string {
  const single = trial ? 'Single investigator (not recorded)' : 'Single investigator';
  if (!canRun)
    return `Four modes propose fixes: Board, Site policy, ${single} or Rules only (no agents). Pick one to read the list.`;
  return `Choose who proposes fixes: Board, Site policy, ${single} or Rules only. Every fix needs a person, or the site's written policy.`;
}

/** What this role can do in the trial, in words: the welcome promises nothing the role's controls grey out. */
export function welcomeActions(can: Can): string {
  const verbs = [
    can.approve && 'approve',
    can.scenarios && 'run',
    can.configure && 'save',
    'escalate',
  ].filter((v): v is string => !!v);
  const said = verbs.length > 1 ? `${verbs.slice(0, -1).join(', ')} or ${verbs.at(-1)}` : verbs[0];
  return said.charAt(0).toUpperCase() + said.slice(1);
}

export const CHAPTERS: GuideChapter[] = [
  {
    id: 'scenarios',
    title: 'Scenarios',
    group: 'Operate',
    steps: [
      {
        id: 'start',
        title: 'Three stories to start with',
        say: 'Each scenario replays a known message failure. Start with these three: a transfer recovered, one that had already arrived, and a fix held back.',
        lookOnly: {
          say: "Each scenario replays a known failure. The cards show three of the online hospital's stories; this tour then follows S2, S8 and S20.",
        },
        place: { page: '/scenarios' },
        target: 'scenarios',
        scopes: Q,
      },
      {
        id: 'mode',
        title: 'Who makes the plan',
        say: modesSay(TRIAL),
        lookOnly: { say: modesSay(TRIAL, false) },
        detail:
          "In every mode, every fix passes the safety checks, then a person, or the site's written policy, releases it. Rules only is the baseline.",
        place: { page: '/scenarios' },
        target: 'scenarios-mode',
        scopes: A,
      },
      {
        id: 'expected',
        title: 'What should happen, and what did',
        say: 'A scenario is a known failure we replay; a case is one run. Latest case shows how it ended, in colour and words. Open one.',
        detail:
          'Each row says how its scenario should end. Latest case is the case it opened and how that really ended. Open one to see why.',
        place: { page: '/scenarios' },
        target: 'scenarios-list',
        scopes: A,
      },
    ],
  },
  {
    id: 'cases',
    title: 'Cases',
    group: 'Operate',
    steps: [
      {
        id: 'list',
        title: 'Every failure becomes a case',
        say: 'Colour shows where each case stands: green delivered or nothing to send, yellow needs a person, red refused or failed. The tiles filter the list.',
        place: { page: '/cases' },
        target: 'cases-list',
        scopes: A,
      },
      {
        id: 'closed',
        title: 'Closed does not mean sent',
        say: 'A closed case may have sent nothing: nothing was needed, or a person handled it. Escalated and blocked cases still wait for a person.',
        place: { page: '/cases' },
        target: 'cases-list',
        scopes: A,
      },
    ],
  },
  {
    id: 's2',
    title: 'A transfer recovered',
    code: 'S2',
    group: 'Operate',
    steps: [
      {
        id: 'receipt',
        title: 'The outcome at a glance',
        say: 'The bed system was down, so this transfer never arrived. The board of agents proposes sending it again, only if nothing has changed since.',
        detail:
          'The receiver holds the encounter at its earlier ward and version 1, with no receipt for the operation. The plan resends it unchanged, conditional on that version.',
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-outcome',
        scopes: Q,
      },
      {
        id: 'receipt-json',
        title: 'The decision receipt, as JSON',
        say: "The receipt binds the plan digest, the gate's policy version, the approval and each write's expected version. Copy it as JSON.",
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-receipt',
        tryIt: { action: 'copy-receipt', text: 'Try it: Copy receipt as JSON' },
        scopes: E,
      },
      {
        id: 'evidence',
        title: 'What the evidence says',
        say: 'The bed system still holds the patient in the old ward, with no record of the transfer. Three specialist agents read this evidence in parallel.',
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-evidence',
        open: 'evidence',
        scopes: A,
      },
      {
        id: 'decision',
        title: 'Your turn: approve the fix',
        say: 'The safety checks (the gate) passed, and a test run on the bed system worked. Now the fix waits for you.',
        detail:
          "The rehearsal applied the exact write and rolled it back. An approver releases it; on other cases, the site's written policy may. The same approval is an EnsLib.Workflow task in IRIS's Workflow inbox, for the role Shutter Approvers.",
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-decision',
        nearTry: 'case-approve',
        open: 'decision',
        tryIt: { action: 'approve-plan', text: 'Try it: press Approve the resend' },
        noApprove: {
          title: 'An approver decides here',
          say: "The safety checks (the gate) passed and a test run worked. Your role can't approve, so the fix waits for an approver.",
        },
        whenCase: {
          blocked: {
            title: 'The plan was rejected here',
            say: 'The safety checks (the gate) passed and a test run worked, but the plan was rejected, so the fix was never sent.',
          },
          resolved: {
            title: 'The fix was approved here',
            say: 'The safety checks (the gate) passed and a test run worked. An approver released the fix, so it no longer waits.',
          },
        },
        scopes: Q,
        introduces: ['gate'],
      },
      {
        id: 'gate',
        title: 'Plain question, then reason code',
        say: 'Each gate row asks a plain question and shows a reason code, a fixed name such as APPROVAL_RECEIVER_CHANGED that logs and tests refer to.',
        detail:
          'The gate is a list of mechanical checks. An unknown answer blocks a write as surely as a failed one.',
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-decision',
        open: 'decision',
        scopes: E,
      },
      {
        id: 'verified',
        title: 'Checked at the bed system',
        say: "Shutter reads the bed system's own history and finds the transfer to WARD-B there. That is verified: it landed.",
        noApprove: {
          title: 'What would be checked',
          say: NOT_YET_APPROVED,
        },
        whenCase: {
          awaiting_approval: { title: 'What would be checked', say: NOT_YET_APPROVED },
          blocked: {
            title: 'Rejected, so nothing written',
            say: 'The plan was rejected, so nothing was written. The bed system still holds the patient in the old ward.',
          },
        },
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-verified',
        open: 'verified',
        scopes: Q,
      },
    ],
  },
  {
    id: 's8',
    title: 'A fix held back',
    code: 'S8',
    group: 'Operate',
    steps: [
      {
        id: 'receipt',
        title: 'Escalated, nothing sent',
        say: 'Two systems moved one patient at exactly the same recorded time. Nobody can tell which move is current, so the board asks a person.',
        detail:
          "PAS and BEDMGR sent the same encounter's transfer at the same event time, 08:20:00Z. The coordinator cites catalogue entry E7 and records no write.",
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-outcome',
        chip: { action: 'open-trace', text: 'See it in IRIS: the message trace' },
        scopes: Q,
      },
      {
        id: 'dissent',
        title: 'A disagreement, kept',
        say: 'One specialist agent wanted to send the transfer again. The coordinator chose to ask a person, and kept that dissent on record beside the plan.',
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-board',
        scopes: A,
      },
      {
        id: 'evidence-cited',
        title: 'What each agent cited',
        say: "The two transfers carry the same event time. Each Evidence section names the agents and the plan that cited it. Summary's board cards show recordings.",
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-evidence-tab',
        tab: 'evidence',
        scopes: E,
      },
      {
        id: 'compare',
        title: 'Rules only got it wrong',
        say: "With no agents, Rules only sent the transfer again and overwrote the bed manager's ward. Every safety check passed. Compare the two side by side.",
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-compare',
        open: 'compare',
        scopes: ['quick', 'all', 'engineer'],
      },
      {
        id: 'ask',
        title: 'Ask about this case',
        say: 'Pick a suggested question: the trial has its recorded answer. "Explain" is one agent, quick; "Ask the board" puts it to all four.',
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-ask',
        tryIt: { action: 'ask-open', text: 'Try it: open Ask, pick a question' },
        scopes: Q,
      },
      {
        id: 'trace',
        title: 'The message trace in IRIS',
        say: "Every case links to IRIS's own Visual Trace of the session that carried it. In the trial, it opens the recorded screenshot.",
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-iris',
        tryIt: { action: 'open-trace', text: 'Try it: open the message trace' },
        scopes: E,
      },
    ],
  },
  {
    id: 's8-rules',
    title: 'Rules only on the same failure',
    code: 'S8',
    group: 'Operate',
    steps: [
      {
        id: 'written',
        title: 'The fix Rules only sent',
        say: "With no agents, the rules sent the transfer again unchanged. Here is the update and the bed system's answer.",
        place: { scenario: 'S8', mode: 'rules' },
        target: 'case-written',
        open: 'written',
        scopes: A,
      },
      {
        id: 'verified',
        title: 'Verified, and still wrong',
        say: 'The bed system confirms the patient is in WARD-B. Verified means it landed, not that it was right. The board weighed that.',
        place: { scenario: 'S8', mode: 'rules' },
        target: 'case-verified',
        open: 'verified',
        scopes: A,
      },
    ],
  },
  {
    id: 's20',
    title: 'The gate stopping a fix',
    code: 'S20',
    group: 'Operate',
    steps: [
      {
        id: 'receipt',
        title: 'Blocked, nothing sent',
        say: 'A nurse moved the patient by hand while the fix waited for approval. The record changed, so the gate blocked the old plan.',
        detail:
          "The approval was bound to the receiver's version; the nurse's move changed it, the dispatch gate voided the approval, and the replanned resend was superseded and blocked.",
        place: { scenario: 'S20', mode: 'rules' },
        target: 'case-outcome',
        scopes: Q,
      },
      {
        id: 'decision',
        title: 'An approval covers one plan',
        say: 'The earlier approval stays as history, tied to the plan it released. A changed record needs a new decision.',
        place: { scenario: 'S20', mode: 'rules' },
        target: 'case-decision',
        open: 'decision',
        scopes: A,
      },
    ],
  },
  {
    id: 'incidents',
    title: 'Incidents',
    group: 'Operate',
    steps: [
      {
        id: 'list',
        title: 'Many failures, one incident',
        say: 'When many messages to one system fail within minutes, Shutter groups them into one incident, with a chain per patient encounter.',
        place: { page: '/incidents' },
        target: 'incidents-list',
        scopes: A,
      },
    ],
  },
  {
    id: 'incident',
    title: 'An incident',
    group: 'Operate',
    steps: [
      {
        id: 'chains',
        title: 'One chain per encounter',
        say: 'Each chain is sent one message at a time, in event order. If anything changes, the chain stops and comes back to a person.',
        place: { incident: 'newest' },
        target: 'incident-chains',
        scopes: A,
      },
    ],
  },
  {
    id: 'reviews',
    title: 'Production review',
    group: 'Operate',
    steps: [
      {
        id: 'start',
        title: 'A review reads, it repairs nothing',
        say: "A production review checks a production's settings and recent errors, and changes nothing. In the trial, you can start one.",
        place: { page: '/reviews' },
        target: 'reviews-start',
        tryIt: { action: 'start-review', text: 'Try it: start a review' },
        scopes: A,
      },
      {
        id: 'past',
        title: 'Past reviews',
        say: 'The last 50 reviews of each production are kept. Open one to read what it found and why it matters.',
        place: { page: '/reviews' },
        target: 'reviews-past',
        scopes: A,
      },
    ],
  },
  {
    id: 'review',
    title: 'A review',
    group: 'Operate',
    steps: [
      {
        id: 'findings',
        title: 'The findings',
        say: 'Each finding says what was found, why it matters and what to change in the Management Portal. Severity is how bad it is.',
        place: { review: 'newest' },
        target: 'review-findings',
        scopes: A,
      },
      {
        id: 'agent',
        title: "The agent's ranking",
        say: 'An agent ranks the findings and explains each against the cases. It never changes a severity or approves a change.',
        place: { review: 'newest' },
        target: 'review-agent',
        scopes: A,
      },
    ],
  },
  {
    id: 'evaluation',
    title: 'Evaluation',
    group: 'Results',
    steps: [
      {
        id: 'headline',
        title: 'The proof, from recorded runs',
        say: proofSay(),
        detail: proofDetail(),
        place: { page: '/evaluation' },
        target: 'evaluation-headline',
        scopes: Q,
      },
      {
        id: 'limits',
        title: 'What is not measured yet',
        say: "The limits sit beside the results. Matching these scenarios is narrower than general reliability, and a confidence is the agent's own report.",
        place: { page: '/evaluation' },
        target: 'evaluation-limits',
        scopes: A,
      },
      {
        id: 'rules-differs',
        title: 'Where Rules only went wrong',
        say: 'The per-scenario table, filtered to where Rules only did not end as expected. Six were stopped by the gate; one, S8, wrote.',
        place: { page: '/evaluation?show=rules-differs' },
        target: 'evaluation-table',
        scopes: E,
      },
    ],
  },
  {
    id: 'health',
    title: 'Health',
    group: 'Results',
    steps: [
      {
        id: 'report',
        title: 'Is the installation ready?',
        say: "The installation checks itself: its message engine, web pages and agents. In the trial you see the recorded instance's report.",
        place: { page: '/health' },
        target: 'health',
        scopes: A,
      },
    ],
  },
  {
    id: 'site-profile',
    title: 'Site profile',
    group: 'Configure',
    steps: [
      {
        id: 'categories',
        title: 'Two kinds of receiving system',
        say: 'A bed manager needs only where the patient is now. A patient record needs the full history. Shutter treats their failures differently.',
        place: { page: '/site-profile' },
        target: 'site-receivers-cards',
        scopes: A,
      },
      {
        id: 'summary',
        title: 'Who releases each fix',
        say: "For each tier, this map shows who releases a fix: the site's written policy or a person, always after the gate.",
        place: { page: '/site-profile' },
        target: 'site-summary',
        scopes: A,
      },
      {
        id: 'approvals',
        title: 'The answers behind it',
        say: "Who approves, who gets escalations, and who may close a case by hand. In the trial, a save changes only this browser's copy.",
        place: { page: '/site-profile' },
        target: 'site-approvals',
        scopes: A,
      },
    ],
  },
  {
    id: 'library',
    title: 'Agent library',
    group: 'Configure',
    steps: [
      {
        id: 'agents',
        title: 'Who sits on the board',
        say: 'Three specialist agents each read the evidence from one angle. A coordinator agent turns their findings into one plan. Each card says what it asks.',
        place: { page: '/library' },
        target: 'library',
        scopes: A,
      },
    ],
  },
  {
    id: 'settings',
    title: 'Settings and costs',
    group: 'Configure',
    steps: [
      {
        id: 'agents',
        title: 'How the agents answer',
        say: 'Each agent can run with a real model, record that run, or replay a recording. Here every answer is a replay, so it costs nothing.',
        place: { page: '/settings' },
        target: 'settings-agents',
        scopes: A,
      },
      {
        id: 'costs',
        title: 'What it cost',
        say: costSay(),
        place: { page: '/settings' },
        target: 'settings-costs',
        scopes: A,
      },
    ],
  },
];

/** Whether a step is in the routes at all: the agent's ranking only once the recording holds one. */
export const enabled = (chapter: GuideChapter, step: GuideStep) =>
  RANKED_REVIEW_RECORDED || !(chapter.id === 'review' && step.id === 'agent');

/** A step's path, as the routes and the stored progress name it: `s2/decision`. */
export const pathOf = (chapter: GuideChapter, step: GuideStep) => `${chapter.id}/${step.id}`;

/** Each route's steps, in order: the chapters' order, each chapter's steps that belong to the route. */
const route = (scope: GuideScope) =>
  CHAPTERS.flatMap((c) =>
    c.steps.filter((s) => enabled(c, s) && s.scopes.includes(scope)).map((s) => pathOf(c, s)),
  );
export const SCOPES: Record<GuideScope, string[]> = {
  quick: route('quick'),
  all: route('all'),
  engineer: route('engineer'),
};

export const SCOPE_LABELS: Record<GuideScope, string> = {
  quick: 'Quick tour',
  all: 'Every screen',
  engineer: 'For integration engineers',
};

/** The overline's name for a route. */
export const SCOPE_OVERLINE: Record<GuideScope, string> = {
  quick: 'Trial tour',
  all: 'Every screen',
  engineer: "Engineers' tour",
};

/** The finish card's one sentence on what the route showed: each route its own, since their steps differ. */
export const SCOPE_FINISH: Record<GuideScope, string> = {
  quick:
    "You saw a transfer delivered and verified, a resend that would have overwritten the bed manager's ward held back for a person, and the gate stopping one.",
  all: "You saw a transfer delivered and verified, a resend that would have overwritten the bed manager's ward held back for a person, the gate stopping one, and every screen on the way.",
  engineer:
    "You saw the decision receipt as JSON, the gate's reason codes, what each agent cited, S8 beside its Rules only run, the message trace in IRIS, and where Rules only went wrong.",
};

export function chapterById(id: string | null | undefined): GuideChapter | undefined {
  return CHAPTERS.find((c) => c.id === id);
}

/** The chapter and step a path names. */
export function stepAt(
  path: string | null | undefined,
): { chapter: GuideChapter; step: GuideStep } | undefined {
  if (!path) return undefined;
  const [c, s] = path.split('/');
  const chapter = chapterById(c);
  const step = chapter?.steps.find((x) => x.id === s);
  return chapter && step ? { chapter, step } : undefined;
}

const words = (s: string) => s.split(/\s+/).filter(Boolean).length;

/**
 * A route's length in minutes, as the welcome says it: the words of its steps' titles and `say` read at 200 words a
 * minute, plus 10 s a step and 20 s a step that invites an action, rounded up to a whole minute. One timed walk of
 * each route confirms it; if it does not, these constants change, never a typed figure.
 */
export function tourMinutes(scope: GuideScope): number {
  const seconds = SCOPES[scope].reduce((sum, path) => {
    const s = stepAt(path)!.step;
    return sum + ((words(s.title) + words(s.say)) / 200) * 60 + 10 + (s.tryIt ? 20 : 0);
  }, 0);
  return Math.max(1, Math.ceil(seconds / 60));
}
