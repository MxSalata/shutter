/**
 * The written guide to each page, for the Ask Shutter panel: what the page is, what to try next (each a link into the
 * app), and the few questions the panel suggests for it. The guide stands in for a live answer where none can be given
 * (no model key, a role without the live agents' resource) and under every live answer as "About this page". Each
 * sentence says what the page shows and where its parts are; none states a figure, since the figures are the page's own.
 * The trial's mock answers exactly these questions (mocks/pageQuestions.ts).
 */

export interface GuideLink {
  label: string;
  to: string;
}

export interface PageGuide {
  /** The page's name as the panel says it. */
  title: string;
  /** What the page is, in one or two plain sentences. */
  what: string;
  /** What to try next from here. */
  next: GuideLink[];
  /** The questions the panel suggests for this page. */
  questions: string[];
}

export const GUIDES: Record<string, PageGuide> = {
  home: {
    title: 'Home',
    what: 'The front page: one sentence on what Shutter does, and a card for each section with what a visit there is for.',
    next: [
      { label: 'Try a scenario first', to: '/scenarios' },
      { label: 'Open the cases', to: '/cases' },
    ],
    questions: ['Where should I start?', 'What does each section do?'],
  },
  scenarios: {
    title: 'Scenarios',
    what: 'Known failures replayed: each row is one failure, with what Shutter did about it and who decided. Playing one runs the whole recovery on the demo hospital.',
    next: [
      { label: 'Follow the path from Try first', to: '/scenarios' },
      { label: 'See the cases they made', to: '/cases' },
      { label: 'How the board scored on them', to: '/evaluation' },
    ],
    questions: ['What is a scenario?', 'Which scenario should I play first?', 'What do the outcomes mean?'],
  },
  cases: {
    title: 'Cases',
    what: 'Every failed delivery, newest first: what happened, who decided and what was written. The tiles at the top count the cases that need a person, and pressing one filters the list to them.',
    next: [
      { label: 'Open a case and read its story', to: '/cases' },
      { label: 'Incidents: many failures handled together', to: '/incidents' },
    ],
    questions: ['Which cases need me?', 'What does each outcome colour mean?', 'What is a case?'],
  },
  incidents: {
    title: 'Incidents',
    what: 'Many failures to one receiver within a few minutes, handled together: each incident groups its cases into chains, one per patient visit, released in event order under one approval.',
    next: [
      { label: 'Open an incident to see its chains', to: '/incidents' },
      { label: 'Back to the single cases', to: '/cases' },
    ],
    questions: ['What is an incident?', 'What is a chain?'],
  },
  incident: {
    title: 'An incident',
    what: "One incident's story: its chains, the approval that released them, and a timeline of what happened when. A chain is one patient visit's failed messages, sent in event order.",
    next: [
      { label: 'All incidents', to: '/incidents' },
      { label: 'The cases this incident holds', to: '/cases' },
    ],
    questions: ['What is a chain?', 'Who released this incident?'],
  },
  reviews: {
    title: 'Production review',
    what: "A read-only check of a production's settings and recent errors: an agent reads the production, ranks what it found by severity, and an approver may annotate a finding as intended or an accepted risk. Nothing here changes the production.",
    next: [
      { label: 'Open a review to read its findings', to: '/reviews' },
      { label: 'How the installation stands', to: '/health' },
    ],
    questions: ['What does a review check?', 'What do the severities mean?'],
  },
  review: {
    title: 'A production review',
    what: "One review's findings, ranked by severity, each with the setting or the error signature it rests on and how many cases it touched. An approver's annotation marks a finding intended, an accepted risk or a false positive.",
    next: [
      { label: 'All reviews', to: '/reviews' },
      { label: 'The site profile the findings refer to', to: '/site-profile' },
    ],
    questions: ['What do the severities mean?', 'What does an annotation do?'],
  },
  'site-profile': {
    title: 'Site profile',
    what: "The site's own answers: each receiver, what kind of record it keeps and how sensitive it is, and who releases a write at each tier, the site's written policy or a person. A suggested change from a case opens here as a draft for an approver to save. Beside a receiver's kind and tier, and beside enabling recovery, \"Ask Shutter about this\" explains that answer.",
    next: [
      { label: 'Read the receivers and the policy', to: '/site-profile' },
      { label: 'The agents the board is made of', to: '/library' },
    ],
    questions: ['Who releases a write?', 'What is a receiver category?', 'What is a tier?'],
  },
  library: {
    title: 'Agent library',
    what: 'The board: three specialist agents and a coordinator agent, what each one asks of the evidence and what it knows. An approver may switch a specialist off the board.',
    next: [
      { label: 'See the board at work on a case', to: '/cases' },
      { label: 'How the board scored', to: '/evaluation' },
    ],
    questions: ['What does each agent do?', 'What is the coordinator for?'],
  },
  settings: {
    title: 'Settings and costs',
    what: "How the agents answer (with a model on the live system, or replaying recordings), the prices used to cost each run, what was spent and the day's budget for runs with a model.",
    next: [
      { label: 'The installation report', to: '/health' },
      { label: 'The agents themselves', to: '/library' },
    ],
    questions: ['What does the mode mean?', 'What is the budget?', 'Where do the costs come from?'],
  },
  evaluation: {
    title: 'Evaluation',
    what: 'How the board decides, measured on recorded runs: for each scenario, what was expected and what the board, the single investigator and rules alone proposed, with the agreement among the specialists.',
    next: [
      { label: 'Play a scenario yourself', to: '/scenarios' },
      { label: 'Read a case the evaluation names', to: '/cases' },
    ],
    questions: ['What is being compared?', 'What does "as expected" mean?'],
  },
  health: {
    title: 'Health',
    what: 'The installation checks itself: its message engine, web pages, agents and licence, in groups, each check with its result and what it means.',
    next: [
      { label: 'Settings and costs', to: '/settings' },
      { label: 'Try a scenario', to: '/scenarios' },
    ],
    questions: ['Is the installation healthy?', 'What does a failed check mean?'],
  },
};

/** The guide for a page, or a plain one for a page the map does not name. */
export function guideFor(page: string): PageGuide {
  return (
    GUIDES[page] ?? {
      title: 'This page',
      what: 'A page of Shutter. The sections in the navigation each have a guide of their own.',
      next: [{ label: 'Home', to: '/home' }],
      questions: ['What can I do here?'],
    }
  );
}
