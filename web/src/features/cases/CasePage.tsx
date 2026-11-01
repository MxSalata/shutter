import { Anchor, Container, Stack, Tabs } from '@mantine/core';
import { IconFileSearch, IconHistory, IconListDetails } from '@tabler/icons-react';
import { useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useLocation, useParams, useSearchParams } from 'react-router';
import { isOpen, keys, useCase, useCaseEvents, useMe } from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { isApiError } from '@/lib/errors';
import { CaseHeader } from './case/CaseHeader';
import { Lifecycle } from './case/Lifecycle';
import { EvidencePanel } from './case/EvidencePanel';
import { EscalationPanel } from './case/EscalationPanel';
import { AbandonPanel } from './case/AbandonPanel';
import { CaseTimeline } from './case/CaseTimeline';
import { CaseStory, type StoryStep } from './case/CaseStory';
import { BoardPanel } from './case/BoardPanel';
import { DecisionCard } from './case/DecisionCard';
import { PortalLinks } from './case/PortalLinks';
import { CounterpartStrip } from './case/S8Compare';
import { SHOW_EVIDENCE } from './case/evidenceLinks';
import { rounds } from './case/derive';
import { nextAction, provenanceOf } from './case/outcome';
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

function CaseBody({ c }: { c: CaseDetail }) {
  const [search, setSearch] = useSearchParams();
  const me = useMe().data;
  const open = isOpen(c.state);
  const events = useCaseEvents(c.caseId, open);
  const facts = useCaseFacts(c, open);
  const client = useQueryClient();
  // The parts poll only while the case is open: when it closes, fetch them once more so the last events show.
  const wasOpen = useRef(open);
  useEffect(() => {
    if (wasOpen.current && !open) void client.invalidateQueries({ queryKey: keys.case(c.caseId) });
    wasOpen.current = open;
  }, [open, c.caseId, client]);

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
  const openStep = (step: StoryStep, target: string) => {
    setSteps((s) => (s.includes(step) ? s : [...s, step]));
    setTab('summary');
    window.setTimeout(() => {
      document.getElementById(target)?.scrollIntoView?.({ block: 'start' });
      // Focus follows the scroll, so a keyboard or screen reader user lands on the section, not back at the button
      document.getElementById(`${target}-title`)?.focus({ preventScroll: true });
    }, 250);
  };
  // A finding's "Cites" badge: the Evidence tab, opened on the cited kind
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

  // A board case shows its board under the outcome: the specialists, their proposals and any dissent are the point
  // of it. So does a site policy case the policy left to the board, once its runs show the board sat. A withheld
  // merge or cancel convenes no board, and the other modes keep their investigation in step 3.
  const boardOnTop =
    c.failureKind !== 'withheld' &&
    (c.mode === 'board' || (c.mode === 'policy' && !!facts.runs?.some((r) => r.role === 'coordinator')));
  // Until a policy case's runs are read, where its board goes is not known: the rest of the page waits for them, so
  // the board does not push the steps down, nor step 3 change, once they arrive
  const placing = c.mode === 'policy' && c.failureKind !== 'withheld' && !facts.runsSettled;
  const stopped = ['blocked', 'escalated', 'failed'].includes(c.state);
  const base = portalBase(c.links?.visualTrace);
  return (
    <AskSurface caseId={c.caseId} open={asking} onClose={closeAsk}>
      <CaseHeader
        c={c}
        provenance={provenanceOf(c.mode, facts.runs)}
        actions={
          <>
            <ConveneBoard c={c} />
            <AskButton
              ref={askButton}
              open={asking}
              onToggle={() => (asking ? closeAsk() : setAsking(true))}
            />
          </>
        }
      />
      <Lifecycle c={c} events={events.data ?? []} />
      <CounterpartStrip c={c} onCompare={() => openStep('compare', 's8-compare')} />
      <Stack gap="md">
        <DecisionCard
          facts={facts}
          round={rounds(events.data ?? [])}
          onReview={() => openStep('decision', 'approval')}
        />
        {placing ? <PageSkeleton label="Loading the investigation…" /> : null}
        {boardOnTop ? <BoardPanel caseId={c.caseId} open={open} mode={c.mode} portalBase={base} /> : null}
        {/* A stopped case's hand-off to the team, with the action it serves, after the board so the board stays
            under the receipt; the main button only when escalating is the action */}
        {stopped && !placing ? <EscalationPanel c={c} primary={nextAction(facts).escalate} /> : null}
        {placing ? null : <AbandonPanel c={c} events={events.data} />}
        {placing ? null : (
          <Tabs value={tab} onChange={setTab} keepMounted={false}>
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
            <Tabs.Panel value="summary" pt="md">
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
            </Tabs.Panel>
            <Tabs.Panel value="evidence" pt="md">
              <EvidencePanel
                caseId={c.caseId}
                receiver={c.receiver}
                open={open}
                focus={focus}
                onFocused={clearFocus}
              />
            </Tabs.Panel>
            <Tabs.Panel value="audit" pt="md">
              <Stack gap="md">
                <CaseTimeline events={events.data ?? []} />
                {/* A stopped case's hand-off is part of its next action; once closed by hand, it is history here */}
                {!stopped ? <EscalationPanel c={c} /> : null}
                <PortalLinks c={c} runs={facts.runs} portalBase={base} />
              </Stack>
            </Tabs.Panel>
          </Tabs>
        )}
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
