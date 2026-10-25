import type { Mode } from '@/api/types';
import type { StoryStep } from '@/features/cases/case/CaseStory';

/**
 * The guide's chapters and steps. A step names the page it shows (a fixed page, or a case, incident or review found
 * through the API when the step opens), the `data-tour` target on that page, the case story step to open first, and
 * its text. Targets are attributes the screens carry, never positions in the page.
 */
export type GuideScope = 'quick' | 'all';

export type GuidePlace =
  /** A page of the app. */
  | { page: string }
  /** The newest case of the scenario, in the mode when one is given (in board mode if there is one, otherwise). */
  | { scenario: string; mode?: Mode }
  /** The newest incident. */
  | { incident: 'newest' }
  /** The newest finished production review. */
  | { review: 'newest' };

export interface GuideStep {
  id: string;
  title: string;
  text: string;
  place: GuidePlace;
  /** The `data-tour` attribute of the section the step shows. */
  target: string;
  /** On a case page: the story step to open before the section is shown. */
  open?: StoryStep;
}

export interface GuideChapter {
  id: string;
  title: string;
  steps: GuideStep[];
}

/** The wording every step about approvals keeps: the gate first, then a person or the written policy. */
const RELEASE = "every write passes the gate, then a person, or the site's written policy, releases it";

export const CHAPTERS: GuideChapter[] = [
  {
    id: 'scenarios',
    title: 'Scenarios',
    steps: [
      {
        id: 'start',
        title: 'Start with S2, then S8',
        text: 'Each scenario plays a real failure into the production. S2 shows a failed transfer recovered; S8 shows why a write may be withheld. Running a scenario sends test messages and changes the demonstration environment, so it is always your own action: the guide never runs one.',
        place: { page: '/scenarios' },
        target: 'scenarios',
      },
      {
        id: 'mode',
        title: 'Who makes the proposal',
        text: `The investigation mode chooses who proposes the plan: the board of specialists, the site's policy, or rules alone. The mode changes only the proposal: in every mode, ${RELEASE}.`,
        place: { page: '/scenarios' },
        target: 'scenarios-mode',
      },
      {
        id: 'expected',
        title: 'Expected outcome and latest case',
        text: 'Each card says what the scenario should end in; Latest case shows what actually happened. Open a case from there to read its evidence and its receipt.',
        place: { page: '/scenarios' },
        target: 'scenarios-list',
      },
    ],
  },
  {
    id: 'cases',
    title: 'Cases',
    steps: [
      {
        id: 'list',
        title: 'Every failed delivery opens a case',
        text: 'The state says where a case stands; the disposition says how it was handled. Filter by state or scenario, for example to find the cases waiting for an approval.',
        place: { page: '/cases' },
        target: 'cases-list',
      },
      {
        id: 'closed',
        title: 'Closed is not the same as written',
        text: 'A case can end escalated, blocked or handled by a team, with nothing written by Shutter. The case page says which, and what was verified.',
        place: { page: '/cases' },
        target: 'cases-list',
      },
    ],
  },
  {
    id: 's2',
    title: 'S2: a transfer recovered',
    steps: [
      {
        id: 'receipt',
        title: 'The outcome and its receipt',
        text: 'A transfer was refused while the receiver was down, and it is still current. The top of the case is its receipt: what was proposed, what the gate said, who or what released the write, what was written and what was verified.',
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-outcome',
      },
      {
        id: 'evidence',
        title: 'What the evidence says',
        text: "The evidence shows the transfer never committed: the receiver still holds the encounter in its earlier ward. The board proposes an unchanged resend, conditional on the receiver's version, so it cannot overwrite a newer change.",
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-evidence',
        open: 'evidence',
      },
      {
        id: 'decision',
        title: 'The gate, the dry run and the release',
        text: "The gate checks the plan and a dry run at the receiver rolls back. Then the write waits to be released; on this case, a person releases it with Approve. Approving is always your own action, never the guide's.",
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-decision',
        open: 'decision',
      },
      {
        id: 'verified',
        title: 'Verified at the receiver',
        text: "Once the write is made, Shutter reads the receiver's own history: the transfer to WARD-B, at the next version. Verification confirms what the receiver holds; it does not decide which source should have been believed.",
        place: { scenario: 'S2', mode: 'board' },
        target: 'case-verified',
        open: 'verified',
      },
    ],
  },
  {
    id: 's8',
    title: 'S8: a write withheld',
    steps: [
      {
        id: 'receipt',
        title: 'Escalated, nothing written',
        text: 'The PAS and the bed manager moved the same patient in the same minute. The evidence cannot tell which movement is current, so the coordinator escalates to a person, citing catalogue entry E7, and the receipt records no write.',
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-outcome',
      },
      {
        id: 'dissent',
        title: 'The dissent the coordinator kept',
        text: "Conformance proposed a resend: the message itself is valid. The coordinator kept that dissent in the plan, open here, while choosing escalation. A specialist's confidence is its own report; the gate does not use it.",
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-board',
        open: 'proposed',
      },
      {
        id: 'compare',
        title: 'Rules alone and the board, side by side',
        text: "Rules alone resent the transfer and wrote WARD-B over the bed manager's WARD-C, with every mechanical check passed. Side by side, the two cases show that passing the checks is not the same as choosing the right action.",
        place: { scenario: 'S8', mode: 'board' },
        target: 'case-compare',
        open: 'compare',
      },
    ],
  },
  {
    id: 's8-rules',
    title: 'S8 in Rules only mode',
    steps: [
      {
        id: 'written',
        title: 'The write rules alone made',
        text: "With no agents, the rules resent the transfer unchanged. The write is recorded here with its attempt and the receiver's answer.",
        place: { scenario: 'S8', mode: 'rules' },
        target: 'case-written',
        open: 'written',
      },
      {
        id: 'verified',
        title: 'Verified, and still the wrong ward',
        text: 'Verification confirms the effect at the receiver: the patient is in WARD-B. It does not say which source system should have been believed; that is what the board weighed.',
        place: { scenario: 'S8', mode: 'rules' },
        target: 'case-verified',
        open: 'verified',
      },
    ],
  },
  {
    id: 's20',
    title: 'S20: an approval no longer valid',
    steps: [
      {
        id: 'receipt',
        title: 'Blocked, nothing written',
        text: 'A nurse moved the patient by hand while the plan waited for its approval. The receiver changed, so the earlier approval no longer holds, and the gate blocks the plan: a later event made the movement obsolete.',
        place: { scenario: 'S20' },
        target: 'case-outcome',
      },
      {
        id: 'decision',
        title: 'An approval releases one exact plan',
        text: 'The gate and decision step shows the earlier approval as history, tied to the plan it released, and the checks that block the current plan. A changed receiver needs a new decision.',
        place: { scenario: 'S20' },
        target: 'case-decision',
        open: 'decision',
      },
    ],
  },
  {
    id: 'incidents',
    title: 'Incidents',
    steps: [
      {
        id: 'list',
        title: 'Many failures to one receiver',
        text: 'An incident groups the failures to one receiver within a few minutes. It counts cases and encounter chains apart: one chain per encounter, its operations in event order.',
        place: { page: '/incidents' },
        target: 'incidents-list',
      },
    ],
  },
  {
    id: 'incident',
    title: 'An incident',
    steps: [
      {
        id: 'chains',
        title: 'A chain per encounter',
        text: `Each chain is released one operation at a time, at the version the one before verified, and a changed condition stops it. The site's written policy may release a chain, or it waits for a person; either way, ${RELEASE}.`,
        place: { incident: 'newest' },
        target: 'incident-chains',
      },
    ],
  },
  {
    id: 'reviews',
    title: 'Production review',
    steps: [
      {
        id: 'start',
        title: 'A review reads, it repairs nothing',
        text: "A production review reads a production's settings and recent errors. Starting one is your own action: you choose the production and the window.",
        place: { page: '/reviews' },
        target: 'reviews-start',
      },
      {
        id: 'past',
        title: 'Past reviews',
        text: 'Every review is kept. Open one to read its findings and the explanation of each.',
        place: { page: '/reviews' },
        target: 'reviews-past',
      },
    ],
  },
  {
    id: 'review',
    title: 'A review',
    steps: [
      {
        id: 'findings',
        title: 'The findings',
        text: 'Each finding keeps what was observed with the evidence it rests on. Severity is how bad the hazard is; confidence, kept apart, is how the finding was read.',
        place: { review: 'newest' },
        target: 'review-findings',
      },
      {
        id: 'agent',
        title: "The agent's ranking",
        text: 'The ranking suggests what to look at first. It approves no change and does not settle a root cause by itself.',
        place: { review: 'newest' },
        target: 'review-agent',
      },
    ],
  },
  {
    id: 'evaluation',
    title: 'Evaluation',
    steps: [
      {
        id: 'headline',
        title: 'Recorded live runs',
        text: "These figures come from the recorded live runs, not from measurements made on this installation. They compare the board's disposition with each scenario's expected outcome.",
        place: { page: '/evaluation' },
        target: 'evaluation-headline',
      },
      {
        id: 'limits',
        title: 'The limits beside the results',
        text: "What is not yet measured is listed next to the results. Agreeing with the demonstration's expected outcomes is narrower than general reliability, and a member's confidence is its own report, not a calibrated score and not an input to the gate.",
        place: { page: '/evaluation' },
        target: 'evaluation-limits',
      },
    ],
  },
  {
    id: 'library',
    title: 'Agent library',
    steps: [
      {
        id: 'agents',
        title: 'The agents a board is made from',
        text: 'Three specialists review the evidence, each from one perspective; the coordinator turns their findings into one plan. Enabled and on the default board are separate settings, and changing them is a configuration action outside the guide.',
        place: { page: '/library' },
        target: 'library',
      },
    ],
  },
  {
    id: 'site-profile',
    title: 'Site profile',
    steps: [
      {
        id: 'summary',
        title: 'Who releases each write',
        text: `For each receiver tier: ${RELEASE}. The summary says plainly where the written policy releases a write without a person.`,
        place: { page: '/site-profile' },
        target: 'site-summary',
      },
      {
        id: 'approvals',
        title: 'The answers behind it',
        text: 'Who approves, who an escalation goes to and who may close a case by hand. Saving a change is your own action, after you review it against the saved version.',
        place: { page: '/site-profile' },
        target: 'site-approvals',
      },
    ],
  },
  {
    id: 'settings',
    title: 'Settings and costs',
    steps: [
      {
        id: 'agents',
        title: 'Live, recorded or replayed',
        text: 'Each agent item runs live, records a live run, or replays a recording. A replay answers with recorded reasoning while the scenario itself still plays for real, so a replay does not make the application read only.',
        place: { page: '/settings' },
        target: 'settings-agents',
      },
      {
        id: 'costs',
        title: 'What it cost',
        text: 'Costs are computed from the stored list prices and the tokens used: estimates, not invoices. A replayed run costs nothing.',
        place: { page: '/settings' },
        target: 'settings-costs',
      },
    ],
  },
  {
    id: 'health',
    title: 'Health',
    steps: [
      {
        id: 'report',
        title: 'Readiness for the mode you use',
        text: "The installation's own readiness report. A missing live model is expected while the agents replay recordings, and blocking for live operation. The report as the API sends it stays available below.",
        place: { page: '/health' },
        target: 'health',
      },
    ],
  },
];

/** The chapters of each scope, in order. */
export const SCOPES: Record<GuideScope, string[]> = {
  quick: ['scenarios', 's2', 's8', 's20', 'evaluation'],
  all: CHAPTERS.map((c) => c.id),
};

export const SCOPE_LABELS: Record<GuideScope, string> = {
  quick: 'Quick demonstration',
  all: 'All sections',
};

export function chapterById(id: string | null | undefined): GuideChapter | undefined {
  return CHAPTERS.find((c) => c.id === id);
}
