import { Anchor, Container, Stack, Tabs } from '@mantine/core';
import { IconFileSearch, IconHistory, IconListDetails } from '@tabler/icons-react';
import { useQueryClient } from '@tanstack/react-query';
import { useCallback, useEffect, useRef, useState } from 'react';
import { Link, useParams, useSearchParams } from 'react-router';
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
import { DecisionCard } from './case/DecisionCard';
import { PortalLinks } from './case/PortalLinks';
import { SHOW_EVIDENCE } from './case/evidenceLinks';
import { provenanceOf } from './case/outcome';
import { useCaseFacts } from './case/useCaseFacts';

/** The portal's base path (/csp/<namespace>/) for links to messages, read from the case's trace link. */
function portalBase(visualTrace: string | undefined): string {
  const m = visualTrace ? /^(.*\/)EnsPortal\./.exec(visualTrace) : null;
  return m ? m[1] : '/csp/shutter/';
}

/** The case page's tabs, kept in the route's search parameters (`?tab=evidence`) so a link opens the right one. */
const TABS = ['summary', 'evidence', 'audit'] as const;
type Tab = (typeof TABS)[number];

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
          if (!next || next === 'summary') params.delete('tab');
          else params.set('tab', next);
          return params;
        },
        { replace: true },
      ),
    [setSearch],
  );
  const compare = search.get('show') === 'compare';
  // The story steps start closed, except where the reader is sent: the approval of a case waiting for one, and the
  // S8 comparison when the demo's guide links to it. After that they stay as the reader leaves them.
  const [steps, setSteps] = useState<string[]>(() => [
    ...(c.state === 'awaiting_approval' ? ['decision'] : []),
    ...(compare && c.scenario === 'S8' ? ['compare'] : []),
  ]);
  const openStep = (step: StoryStep, target: string) => {
    setSteps((s) => (s.includes(step) ? s : [...s, step]));
    setTab('summary');
    window.setTimeout(() => document.getElementById(target)?.scrollIntoView?.({ block: 'start' }), 250);
  };
  // A finding's "Cites" badge: the Evidence tab, opened on the cited kind
  const [focus, setFocus] = useState<{ kind: string; at: number }>();
  useEffect(() => {
    const show = (e: Event) => {
      setTab('evidence');
      setFocus({ kind: (e as CustomEvent<string>).detail, at: Date.now() });
    };
    window.addEventListener(SHOW_EVIDENCE, show);
    return () => window.removeEventListener(SHOW_EVIDENCE, show);
  }, [setTab]);

  const stopped = ['blocked', 'escalated', 'failed'].includes(c.state);
  const base = portalBase(c.links?.visualTrace);
  return (
    <>
      <CaseHeader c={c} provenance={provenanceOf(c.mode, facts.runs)} />
      <Lifecycle c={c} events={events.data ?? []} />
      <Stack gap="md">
        <DecisionCard facts={facts} onReview={() => openStep('decision', 'approval')} />
        <AbandonPanel c={c} events={events.data} />
        {/* A stopped case's hand-off to the team is its next action; once closed by hand, it is history */}
        {stopped ? <EscalationPanel c={c} /> : null}
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
            />
          </Tabs.Panel>
          <Tabs.Panel value="evidence" pt="md">
            <EvidencePanel caseId={c.caseId} open={open} focus={focus} />
          </Tabs.Panel>
          <Tabs.Panel value="audit" pt="md">
            <Stack gap="md">
              <CaseTimeline events={events.data ?? []} />
              {!stopped ? <EscalationPanel c={c} /> : null}
              <PortalLinks c={c} runs={facts.runs} portalBase={base} />
            </Stack>
          </Tabs.Panel>
        </Tabs>
      </Stack>
    </>
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
