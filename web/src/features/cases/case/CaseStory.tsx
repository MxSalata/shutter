import { Accordion, Button, Group, Stack, Text } from '@mantine/core';
import { IconListSearch } from '@tabler/icons-react';
import type { ReactNode } from 'react';
import type { CaseDetail, Me } from '@/api/types';
import { KeyValueList } from '@/components/KeyValueList';
import { keyLabel } from '@/lib/format';
import { ApprovalPanel } from './ApprovalPanel';
import { BoardPanel } from './BoardPanel';
import { ClosureRecord } from './Closure';
import { describeItem, KIND_LABELS } from './derive';
import { DispatchPanel, VerificationPanel } from './DispatchPanel';
import { FailurePanel } from './FailurePanel';
import {
  decisionSummary,
  evidenceSummary,
  failedSummary,
  proposedSummary,
  verifiedSummary,
  writtenSummary,
  type CaseFacts,
} from './outcome';
import { GatePanel, PlanPanel, RehearsalPanel } from './PlanPanel';
import { S8Compare } from './S8Compare';
import { NestedSections } from './Section';

/** The summary's steps in story order, and the S8 comparison after them. */
export type StoryStep = 'failed' | 'evidence' | 'proposed' | 'decision' | 'written' | 'verified' | 'compare';

/** The observations the evidence step lists before the whole snapshot: what the receiver holds and has committed. */
const KEY_KINDS = ['ward_state', 'receipt', 'later_event'];

function Step({
  value,
  n,
  title,
  summary,
  children,
}: {
  value: StoryStep;
  n?: number;
  title: string;
  summary: string;
  children: ReactNode;
}) {
  return (
    <Accordion.Item value={value} id={`story-${value}`} data-tour={`case-${value}`}>
      <Accordion.Control>
        <Text span display="block" fw={600}>
          {n ? `${n}. ${title}` : title}
        </Text>
        <Text span display="block" size="sm" c="dimmed" maw="75ch" mt={2}>
          {summary}
        </Text>
      </Accordion.Control>
      <Accordion.Panel>
        <NestedSections>
          <Stack gap="xl">{children}</Stack>
        </NestedSections>
      </Accordion.Panel>
    </Accordion.Item>
  );
}

/**
 * The Summary tab: the case's story in six steps, each with a one-line summary put together from the case's facts
 * and its details on demand: what failed, what the evidence says, what was proposed, the gate and the decision, what
 * was written and what was verified. On an S8 case, the comparison of rules alone with the board follows.
 */
export function CaseStory({
  c,
  me,
  facts,
  open,
  opened,
  onChange,
  onShowEvidence,
  portalBase,
  compareFocus,
}: {
  c: CaseDetail;
  me: Me | null | undefined;
  facts: CaseFacts;
  open: boolean;
  opened: string[];
  onChange: (steps: string[]) => void;
  /** Switches to the Evidence tab. */
  onShowEvidence: () => void;
  portalBase: string;
  compareFocus: boolean;
}) {
  const plan = facts.plan;
  const write = plan?.plan?.disposition === 'resend';
  const planRead = {
    view: plan,
    loading: plan === undefined && !facts.planError,
    error: facts.planError,
    onRetry: facts.retryPlan,
  };
  const execution = {
    caseId: c.caseId,
    open,
    write,
    planned: !!plan?.plan,
    byHand: c.disposition === 'handled_by_hand',
    state: c.state,
  };
  const key = (facts.snapshot?.items ?? []).filter((x) => KEY_KINDS.includes(x.kind));
  return (
    <Accordion
      variant="separated"
      multiple
      order={2}
      chevronPosition="left"
      value={opened}
      onChange={onChange}
    >
      <Step value="failed" n={1} title="What failed" summary={failedSummary(c)}>
        <FailurePanel c={c} />
      </Step>
      <Step value="evidence" n={2} title="What the evidence says" summary={evidenceSummary(facts.snapshot)}>
        <Stack gap="sm">
          {key.length ? (
            <KeyValueList rows={key.map((x) => [KIND_LABELS[x.kind] ?? keyLabel(x.kind), describeItem(x)])} />
          ) : null}
          <Text size="sm" c="dimmed">
            Every observation, its source, time and digest, and the encounter's timeline are on the Evidence
            tab.
          </Text>
          <Group>
            <Button
              size="xs"
              variant="light"
              leftSection={<IconListSearch size={14} />}
              onClick={onShowEvidence}
            >
              Open the evidence
            </Button>
          </Group>
        </Stack>
      </Step>
      <Step value="proposed" n={3} title="What was proposed" summary={proposedSummary(facts)}>
        <BoardPanel
          caseId={c.caseId}
          open={open}
          mode={c.mode}
          withheld={c.failureKind === 'withheld'}
          portalBase={portalBase}
        />
        <PlanPanel {...planRead} />
      </Step>
      <Step value="decision" n={4} title="Gate and decision" summary={decisionSummary(facts)}>
        <GatePanel {...planRead} />
        {me ? <ApprovalPanel c={c} me={me} view={plan} approvals={facts.approvals} /> : null}
      </Step>
      <Step value="written" n={5} title="What was written" summary={writtenSummary(facts)}>
        <RehearsalPanel view={plan} write={write} />
        <DispatchPanel {...execution} />
      </Step>
      <Step value="verified" n={6} title="What was verified" summary={verifiedSummary(facts)}>
        <VerificationPanel {...execution} />
        <ClosureRecord c={c} />
      </Step>
      {c.scenario === 'S8' ? (
        <Step
          value="compare"
          title="Why the board matters"
          summary="The same failure played by rules alone and by the board: what each did at the receiver, and the evidence both read."
        >
          <S8Compare caseId={c.caseId} focus={compareFocus} />
        </Step>
      ) : null}
    </Accordion>
  );
}
