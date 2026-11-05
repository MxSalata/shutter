import { Anchor, Container, Stack, Tabs, Text, VisuallyHidden } from '@mantine/core';
import { IconFileSearch, IconHistory, IconListDetails, IconPlayerPlay } from '@tabler/icons-react';
import { useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useLocation, useParams, useSearchParams } from 'react-router';
import { isOpen, keys, useCase, useCaseEvents, useMe, useScenarios, useSiteProfile } from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { ApiSource } from '@/components/ApiSource';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { isApiError } from '@/lib/errors';
import { REPLAY_DONE, SHOW_APPROVAL } from '@/lib/events';
import { usePrefersReducedMotion, useStagedReveal } from '@/lib/motion';
import { caseOutcome } from '@/lib/status';
import { CaseHeader } from './case/CaseHeader';
import { Lifecycle, REPLAYED_STAGES, type StageKey } from './case/Lifecycle';
import { FailureMap } from './case/FailureMap';
import { failureMapOf } from './case/failureMap';
import { CaseActionButton } from './case/CaseActionButton';
import { caseActionOf } from './case/caseAction';
import { closeNeedsApprover } from '../site-profile/profile';
import { EvidencePanel } from './case/EvidencePanel';
import { revealSection } from './case/revealSection';
import { EscalationPanel } from './case/EscalationPanel';
import { AbandonPanel } from './case/AbandonPanel';
import { CaseTimeline } from './case/CaseTimeline';
import { CaseStory, type StoryStep } from './case/CaseStory';
import { BoardPanel } from './case/BoardPanel';
import { DecisionCard } from './case/DecisionCard';
import { PortalLinks } from './case/PortalLinks';
import { PrecedentsSection } from './case/Precedents';
import { CounterpartStrip, S8RulesNote } from './case/S8Compare';
import { SHOW_EVIDENCE } from './case/evidenceLinks';
import { rounds } from './case/derive';
import { nextAction, outcomeCaseOf, provenanceOf, recordedApprovalTime } from './case/outcome';
import { useCaseFacts } from './case/useCaseFacts';
import { AskButton, AskSurface } from './ask/AskSurface';
import { ConveneBoard } from './case/ConveneBoard';

/** The portal's base path (/csp/<namespace>/) for links to messages, read from the case's trace link. */
function portalBase(visualTrace: string | undefined): string {
  const m = visualTrace ? /^(.*\/)EnsPortal\./.exec(visualTrace) : null;
  return m ? m[1] : '/csp/shutter/';
}

/** The case page's tabs, kept in the route's search parameters (`?tab=evidence`) so a link opens the right one. */
const TABS = ['summary', 'evidence', 'audit'] as const;
type Tab = (typeof TABS)[number];

/** The story steps a link may open (`?open=decision`), as the guide does to show one. */
const STEPS: StoryStep[] = ['failed', 'evidence', 'proposed', 'decision', 'written', 'verified', 'compare'];

/**
 * Where each stage of the progress strip is told on the page, besides the Evidence tab and the board: the story step
 * it opens and the section it scrolls to, then the sections to try when that one is not there.
 */
const STAGE_PLACES: Record<Exclude<StageKey, 'evidence'>, [StoryStep, string, ...string[]]> = {
  investigation: ['proposed', 'board', 'plan'],
  gate: ['decision', 'gate'],
  rehearsal: ['written', 'rehearsal'],
  approval: ['decision', 'approval', 'gate'],
  dispatch: ['written', 'dispatch'],
  verification: ['verified', 'verification'],
};

/** What the trial says, once, when the replay after an approval has played. */
const REPLAYED = 'Approved in the trial. The recording shows it delivered and verified.';

/** The event the guide waits for once the trial has played out what came of a reader's approval (`@/lib/events`). */
export { REPLAY_DONE };

/**
 * A tab panel clears the header and the sticky tab bar when it is scrolled to, as `.case-tab-panel` makes the
 * sections and steps inside it do.
 */
const PANEL = {
  className: 'case-tab-panel',
  style: { scrollMarginTop: 'calc(var(--shutter-header-h) + 3.5rem)' },
};

function CaseBody({ c }: { c: CaseDetail }) {
  const [search, setSearch] = useSearchParams();
  const me = useMe().data;
  const open = isOpen(c.state);
  const events = useCaseEvents(c.caseId, open);
  const facts = useCaseFacts(c, open);
  const client = useQueryClient();
  // The case's scenario, for its expectation: rules alone's S8 write is "Not as expected", however verified
  const scenario = useScenarios().data?.scenarios.find((s) => s.id === c.scenario);
  const outcomeCase = outcomeCaseOf(facts);
  const verdict = caseOutcome(outcomeCase, scenario);
  // The parts poll only while the case is open: when it closes, fetch them once more so the last events show.
  const wasOpen = useRef(open);
  useEffect(() => {
    if (wasOpen.current && !open) void client.invalidateQueries({ queryKey: keys.case(c.caseId) });
    wasOpen.current = open;
  }, [open, c.caseId, client]);

  // The trial plays out what came of an approval, once: when a case this page saw waiting for approval resolves
  // (the reader's Approve plan, or the guide's approve-for-you), its last three stages fill in one at a time, then the
  // band turns to the outcome. Live pages never replay: they show the real states as the case polls them.
  const [seen, setSeen] = useState(c.state);
  const [replay, setReplay] = useState(false);
  if (seen !== c.state) {
    setSeen(c.state);
    if (TRIAL && seen === 'awaiting_approval' && c.state === 'resolved') setReplay(true);
  }
  // It starts once the recorded outcome is read (the attempts come after the case), or after two seconds regardless
  const [waited, setWaited] = useState(false);
  useEffect(() => {
    if (!replay) return;
    const t = window.setTimeout(() => setWaited(true), 2000);
    return () => window.clearTimeout(t);
  }, [replay]);
  const ready = replay && c.state === 'resolved' && (verdict.key !== 'resolved' || waited);
  const [announced, setAnnounced] = useState('');
  const onReplayed = useCallback(() => {
    setAnnounced(REPLAYED);
    window.dispatchEvent(new CustomEvent(REPLAY_DONE, { detail: c.caseId }));
  }, [c.caseId]);
  const staged = useStagedReveal(REPLAYED_STAGES, { start: ready, onDone: onReplayed });
  const reduced = usePrefersReducedMotion();
  // The lifecycle and the band are both in view while it plays
  useEffect(() => {
    if (ready)
      document
        .getElementById('case-lifecycle')
        ?.scrollIntoView?.({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
  }, [ready, reduced]);
  const played = replay && staged.done;
  // Until it has played, the band still reads as the case did when it waited
  const shown =
    replay && !played ? caseOutcome({ state: 'awaiting_approval', disposition: c.disposition }) : verdict;
  const approvedAt = recordedApprovalTime(events.data);

  const asked = search.get('tab') as Tab | null;
  const tab: Tab = asked && TABS.includes(asked) ? asked : 'summary';
  const setTab = useCallback(
    (next: string | null) =>
      setSearch(
        (prev) => {
          const params = new URLSearchParams(prev);
          // The story step a link opened has been shown: a later tab change must not open it again
          params.delete('open');
          if (!next || next === 'summary') params.delete('tab');
          else params.set('tab', next);
          return params;
        },
        { replace: true },
      ),
    [setSearch],
  );
  const compare = search.get('show') === 'compare';
  // Ask about this case, kept in the address (`?ask=1`) so a link opens it; closing it returns focus to its button
  const asking = search.get('ask') === '1';
  const askButton = useRef<HTMLButtonElement>(null);
  const setAsking = useCallback(
    (on: boolean) =>
      setSearch(
        (prev) => {
          const params = new URLSearchParams(prev);
          if (on) params.set('ask', '1');
          else params.delete('ask');
          return params;
        },
        { replace: true },
      ),
    [setSearch],
  );
  const closeAsk = useCallback(() => {
    setAsking(false);
    window.setTimeout(() => askButton.current?.focus(), 0);
  }, [setAsking]);
  // The story steps start closed, except where the reader is sent: the approval of a case waiting for one, and the
  // S8 comparison when the demo's guide links to it. After that they stay as the reader leaves them.
  const [steps, setSteps] = useState<string[]>(() => [
    ...(c.state === 'awaiting_approval' ? ['decision'] : []),
    ...(compare && c.scenario === 'S8' ? ['compare'] : []),
  ]);
  // A link that names a story step opens it, on every navigation to the link (the location's key), even on this
  // page; a tab change drops the parameter, so a step the reader closed stays closed
  const asks = search.get('open') as StoryStep | null;
  const { key: visit } = useLocation();
  const [visited, setVisited] = useState<string>();
  if (asks && STEPS.includes(asks) && visited !== visit) {
    setVisited(visit);
    if (!steps.includes(asks)) setSteps([...steps, asks]);
  }
  // "See them" under the approval: the Audit trail, its precedents' list open and its heading focused
  const [precedentsOpen, setPrecedentsOpen] = useState(false);
  const seePrecedents = () => {
    const from = document.activeElement;
    setPrecedentsOpen(true);
    setTab('audit');
    // Unless the reader has already moved on, as a quick hand does to a Retire button
    revealSection(
      ['precedents'],
      () => document.activeElement === from || document.activeElement === document.body,
    );
  };
  // Scrolls the first of these sections that is on the page under the tab bar and moves focus to its heading
  // Focus goes with the scroll, so a keyboard or screen reader user lands on the section, not back at the button
  const reveal = (...targets: string[]) => revealSection(targets);
  const openStep = (step: StoryStep, target: string, ...fallbacks: string[]) => {
    setSteps((s) => (s.includes(step) ? s : [...s, step]));
    setTab('summary');
    reveal(target, ...fallbacks);
  };
  // A reached stage of the progress strip: the Evidence tab, the board above the story, or the story step that tells it
  const showStage = (stage: StageKey) => {
    if (stage === 'evidence') {
      setTab('evidence');
      reveal('evidence');
    } else if (stage === 'investigation' && boardOnTop) {
      setTab('summary');
      reveal('board');
    } else {
      const [step, ...targets] = STAGE_PLACES[stage];
      openStep(step, ...(targets as [string, ...string[]]));
    }
  };
  // A finding's citation chip: the Evidence tab, opened on the cited section
  const [focus, setFocus] = useState<{ kind: string; at: number }>();
  const clearFocus = useCallback(() => setFocus(undefined), []);
  useEffect(() => {
    const show = (e: Event) => {
      setTab('evidence');
      setFocus({ kind: (e as CustomEvent<string>).detail, at: Date.now() });
    };
    window.addEventListener(SHOW_EVIDENCE, show);
    return () => window.removeEventListener(SHOW_EVIDENCE, show);
  }, [setTab]);
  // The abandon dialog's "reject the plan instead": the case read again (its approval task is open, so it waits for a
  // person now), then the decision step with the Approval section in view
  useEffect(() => {
    const show = () => {
      void client.invalidateQueries({ queryKey: keys.case(c.caseId) });
      openStep('decision', 'approval');
    };
    window.addEventListener(SHOW_APPROVAL, show);
    return () => window.removeEventListener(SHOW_APPROVAL, show);
  });

  // A board case shows its board first on the Summary tab: the specialists, their proposals and any dissent are the
  // point of it. So does a site policy case the policy left to the board, once its runs show the board sat. A withheld
  // merge or cancel convenes no board, and the other modes keep their investigation in step 3.
  const boardOnTop =
    c.failureKind !== 'withheld' &&
    (c.mode === 'board' || (c.mode === 'policy' && !!facts.runs?.some((r) => r.role === 'coordinator')));
  // Until a policy case's runs are read, where its board goes is not known: the rest of the page waits for them, so
  // the board does not push the steps down, nor step 3 change, once they arrive
  const placing = c.mode === 'policy' && c.failureKind !== 'withheld' && !facts.runsSettled;
  const stopped = ['blocked', 'escalated', 'failed'].includes(c.state);
  const base = portalBase(c.links?.visualTrace);
  // Where it failed, as the band says it: during the trial's replay, the outcome as it was until the replay has played
  const map = failureMapOf(c, facts.snapshot, shown, {
    delivered: shown.key === 'delivered',
    code: stopped ? (facts.blocked?.code ?? '') : '',
  });
  // What the case needs from this reader, for the button at the top and its copy in the tab bar
  const site = useSiteProfile();
  const action = caseActionOf(facts, {
    me,
    trial: TRIAL,
    closeNeedsApprover: site.isError ? false : site.data ? closeNeedsApprover(site.data.profile) : undefined,
  });
  return (
    <AskSurface caseId={c.caseId} open={asking} onClose={closeAsk}>
      <CaseHeader
        c={c}
        provenance={provenanceOf(c.mode, facts.runs)}
        outcome={outcomeCase}
        scenario={scenario}
        portalBase={base}
        snapshot={facts.snapshot}
        actions={
          <>
            <ConveneBoard c={c} />
            <CaseActionButton action={action} />
            <AskButton
              ref={askButton}
              open={asking}
              onToggle={() => (asking ? closeAsk() : setAsking(true))}
            />
          </>
        }
      />
      <FailureMap map={map} />
      <Lifecycle
        c={c}
        events={events.data ?? []}
        verified={facts.receipt.verificationState === 'verified'}
        reveal={replay ? staged.stepProps : undefined}
        onStage={showStage}
        investigation={boardOnTop ? 'the board' : undefined}
      />
      <S8RulesNote c={c} />
      <CounterpartStrip c={c} onCompare={() => openStep('compare', 's8-compare')} />
      {/* Said once the replay has played: the approval the receipt shows is the recording's, and yours is noted */}
      {played ? (
        <Text
          size="sm"
          mb="sm"
          data-testid="replay-note"
          style={{ display: 'flex', gap: 6, alignItems: 'baseline' }}
        >
          <IconPlayerPlay size={14} aria-hidden style={{ flex: 'none', alignSelf: 'center' }} />
          <span>
            {`Replayed from the recording${approvedAt ? `: approved ${approvedAt}` : ''}. Your approval is noted at the end of the audit trail.`}
          </span>
        </Text>
      ) : null}
      {/* A live region, not a status role: the page has no status region once its data is in */}
      <VisuallyHidden aria-live="polite" aria-atomic="true" data-testid="replay-announcement">
        {announced}
      </VisuallyHidden>
      <DecisionCard
        facts={facts}
        round={rounds(events.data ?? [])}
        onReview={() => openStep('decision', 'approval')}
        outcome={shown}
        fading={played}
        onSeePrecedents={seePrecedents}
      />
      {placing ? <PageSkeleton label="Loading the investigation…" /> : null}
      {placing ? null : (
        <Tabs value={tab} onChange={setTab} keepMounted={false}>
          {/* The tabs stay under the header while the page scrolls, so Evidence is a click away from anywhere, and the
              case's action with them, compact */}
          <div className="sticky-tabs case-tab-bar">
            <Tabs.List aria-label="The case in detail">
              <Tabs.Tab value="summary" leftSection={<IconListDetails size={16} aria-hidden />}>
                Summary
              </Tabs.Tab>
              <Tabs.Tab value="evidence" leftSection={<IconFileSearch size={16} aria-hidden />}>
                Evidence
              </Tabs.Tab>
              <Tabs.Tab value="audit" leftSection={<IconHistory size={16} aria-hidden />}>
                Audit trail
              </Tabs.Tab>
            </Tabs.List>
            <CaseActionButton action={action} compact />
          </div>
          <Tabs.Panel value="summary" pt="md" {...PANEL}>
            <Stack gap="md">
              {boardOnTop ? (
                <BoardPanel
                  caseId={c.caseId}
                  open={open}
                  mode={c.mode}
                  portalBase={base}
                  receiver={c.receiver}
                />
              ) : null}
              {/* A stopped case's hand-off to the team, with the action it serves, after the board; the main button
                  only when escalating is the action */}
              {stopped ? <EscalationPanel c={c} primary={nextAction(facts).escalate} /> : null}
              <AbandonPanel c={c} events={events.data} />
              <CaseStory
                c={c}
                me={me}
                facts={facts}
                open={open}
                opened={steps}
                onChange={setSteps}
                onShowEvidence={() => setTab('evidence')}
                portalBase={base}
                compareFocus={compare}
                boardOnTop={boardOnTop}
              />
            </Stack>
          </Tabs.Panel>
          <Tabs.Panel value="evidence" pt="md" data-tour="case-evidence-tab" {...PANEL}>
            <EvidencePanel
              caseId={c.caseId}
              receiver={c.receiver}
              open={open}
              focus={focus}
              onFocused={clearFocus}
            />
          </Tabs.Panel>
          <Tabs.Panel value="audit" pt="md" {...PANEL}>
            <Stack gap="md">
              <CaseTimeline events={events.data ?? []} />
              {/* What approvers decided before on these conditions here; "What needs you now" names them first when
                  the case waits for an approval */}
              <PrecedentsSection
                caseId={c.caseId}
                snapshot={facts.snapshot}
                define={c.state !== 'awaiting_approval'}
                open={precedentsOpen}
              />
              {/* A stopped case's hand-off is part of its next action; once closed by hand, it is history here */}
              {!stopped ? <EscalationPanel c={c} /> : null}
              <PortalLinks c={c} runs={facts.runs} portalBase={base} />
            </Stack>
          </Tabs.Panel>
        </Tabs>
      )}
      {/* The case as the API sends it, for the engineer: open in Technical */}
      <Stack mt="lg">
        <ApiSource endpoint={`GET /api/shutter/cases/${c.caseId}`} data={c} />
      </Stack>
    </AskSurface>
  );
}

export default function CasePage() {
  const { caseId = '' } = useParams();
  const c = useCase(caseId);

  if (c.isPending) return <PageSkeleton label={`Loading case ${caseId}…`} />;
  if (c.isError)
    return (
      <Container size="sm" py="xl">
        <ErrorAlert
          error={c.error}
          title={
            isApiError(c.error) && c.error.isNotFound
              ? `There is no case ${caseId}`
              : `Case ${caseId} could not be read`
          }
          onRetry={isApiError(c.error) && c.error.isNotFound ? undefined : () => void c.refetch()}
        />
        <Anchor component={Link} to="/cases" size="sm" mt="sm" display="block">
          All cases
        </Anchor>
      </Container>
    );
  // A new case id starts the page afresh: its own tab, steps and evidence request
  return <CaseBody key={caseId} c={c.data} />;
}
