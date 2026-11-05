import {
  Anchor,
  Button,
  Card,
  Group,
  Paper,
  SimpleGrid,
  Stack,
  Table,
  Text,
  VisuallyHidden,
} from '@mantine/core';
import { IconAlertTriangle, IconArrowsLeftRight, IconEqual } from '@tabler/icons-react';
import { useEffect, useRef } from 'react';
import { Link } from 'react-router';
import { scenariosHidden } from '@/api/can';
import {
  useAttempts,
  useCan,
  useCase,
  useCases,
  useClosure,
  usePlan,
  useScenarios,
  useSnapshot,
} from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { ExpectedMark } from '@/components/ExpectedMark';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { PortalLink } from '@/components/PortalLink';
import { StackTable } from '@/components/StackTable';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { trialHref } from '@/env/mode';
import { humanize } from '@/lib/format';
import { TRIAL_BOARD_CASE } from '@/lib/hospital';
import { playedFor } from '@/lib/proof';
import { caseOutcome, expectationOf, writes, type ExpectedScenario } from '@/lib/status';
import { traceScreenshot } from '@/lib/screenshots';
import { TONE_COLOURS, toneText, type Tone } from '@/lib/tone';
import type { CaseDetail } from '@/api/types';
import { compareSide, evidenceRows, playedMark, s8Pair, type CompareSide, type EvidenceRow } from './compare';
import { NotYet, Section } from './Section';

/** One case of the pair, read the way its own page reads it. */
function useSide(caseId: string): { side?: CompareSide; detail?: CaseDetail; error: unknown } {
  const c = useCase(caseId);
  const plan = usePlan(caseId, false);
  const attempts = useAttempts(caseId, false);
  const closure = useClosure(caseId, true);
  const snapshot = useSnapshot(caseId, false);
  const error = c.error ?? plan.error ?? attempts.error ?? snapshot.error;
  if (!c.data || plan.isPending || attempts.isPending || snapshot.isPending) return { error };
  return {
    side: compareSide({
      c: c.data,
      plan: plan.data,
      attempts: attempts.data,
      closure: closure.data,
      snapshot: snapshot.data,
    }),
    detail: c.data,
    error,
  };
}

/** Which side of the pair did what the scenario asks: the edge of its card, so the two can be told apart at a glance. */
const EDGES: Record<string, Tone> = { 'as-expected': 'positive', differs: 'blocking' };

function SideCard({
  side,
  title,
  current,
  scenario,
}: {
  side: CompareSide;
  title: string;
  current: boolean;
  scenario?: ExpectedScenario | null;
}) {
  const verdict = caseOutcome(side.outcome, scenario);
  const wrong = verdict.key === 'not-as-expected';
  const edge = EDGES[expectationOf(side.outcome, scenario).kind];
  const VerdictIcon = verdict.icon;
  const written = writes(side.writes);
  return (
    <Card
      padding="sm"
      withBorder
      data-testid={`compare-${side.mode}`}
      style={edge ? { borderTop: `4px solid var(--mantine-color-${TONE_COLOURS[edge]}-filled)` } : undefined}
    >
      <Stack gap={6}>
        <Group gap="xs" wrap="wrap">
          <Text size="sm" fw={600}>
            {title}
          </Text>
          {current ? (
            <Text size="sm" c="dimmed">
              {`(${side.caseId}, this case)`}
            </Text>
          ) : (
            <Anchor component={Link} to={`/cases/${encodeURIComponent(side.caseId)}`} size="sm">
              {side.caseId}
            </Anchor>
          )}
        </Group>
        {/* How it ended for the patient comes first: the versions and receipts below only prove it */}
        {side.patient ? (
          <Group gap={8} wrap="nowrap" align="flex-start">
            {VerdictIcon ? (
              <VerdictIcon
                size={20}
                aria-hidden
                style={{ color: toneText(edge ?? verdict.tone), flex: 'none', marginTop: 2 }}
              />
            ) : null}
            <Text
              fw={700}
              lh={1.35}
              data-testid="compare-patient"
              style={{ color: toneText(edge ?? verdict.tone) }}
            >
              {side.patient}
            </Text>
          </Group>
        ) : null}
        <Group gap={6}>
          <OutcomeBadge c={side.outcome} scenario={scenario} />
          {/* The outcome already says Not as expected; an escalated case's proposal to escalate would only repeat it */}
          {wrong ? null : <ExpectedMark c={side.outcome} scenario={scenario} />}
          {side.state === 'escalated' && side.disposition === 'escalate' ? null : (
            <DispositionBadge disposition={side.disposition} />
          )}
          <StatusBadge {...written} tone={wrong && side.writes ? 'blocking' : written.tone} />
        </Group>
        <Text size="sm" fw={500}>
          {side.result}
        </Text>
        {side.verification ? (
          <Text size="sm" c="dimmed">
            {side.verification}
          </Text>
        ) : null}
        {/* Green words under a wrong write are the point of S8, so they are explained where they are read */}
        {wrong && side.outcome.verification === 'verified' ? (
          <Text size="sm">Every check passed: verified means the write landed, not that it was right.</Text>
        ) : null}
        {side.dissent ? (
          <Text size="sm" c="dimmed">
            {`Dissent kept in the plan, and overruled: ${side.dissent}`}
          </Text>
        ) : null}
      </Stack>
    </Card>
  );
}

/** The evidence fact by fact; on a phone each fact is a block, its two readings under their run's name. */
function EvidenceTable({
  rows,
  rulesId,
  boardId,
}: {
  rows: EvidenceRow[];
  rulesId: string;
  boardId: string;
}) {
  const rulesHead = `Rules only (${rulesId})`;
  const boardHead = `The board (${boardId})`;
  return (
    <Table.ScrollContainer minWidth={560} className="stack-scroll">
      <StackTable verticalSpacing={4} fz="sm" className="stack-table">
        <StackTable.Thead>
          <StackTable.Tr>
            <StackTable.Th w="22%">Evidence</StackTable.Th>
            <StackTable.Th>{rulesHead}</StackTable.Th>
            <StackTable.Th>{boardHead}</StackTable.Th>
            <StackTable.Th w={56}>Same</StackTable.Th>
          </StackTable.Tr>
        </StackTable.Thead>
        <StackTable.Tbody>
          {rows.map((r) => (
            <StackTable.Tr key={r.label}>
              <StackTable.Td>
                <Text size="sm" c="dimmed" fw={500}>
                  {r.label}
                </Text>
              </StackTable.Td>
              <StackTable.Td data-label={rulesHead}>
                <span className="mono-wrap">{r.rules}</span>
              </StackTable.Td>
              <StackTable.Td data-label={boardHead}>
                <span className="mono-wrap">{r.board}</span>
              </StackTable.Td>
              <StackTable.Td data-label="Same">
                {r.same ? (
                  <>
                    <IconEqual size={16} color="var(--shutter-muted)" aria-hidden />
                    <VisuallyHidden>the same</VisuallyHidden>
                  </>
                ) : (
                  <Text size="xs" c="dimmed">
                    differs
                  </Text>
                )}
              </StackTable.Td>
            </StackTable.Tr>
          ))}
        </StackTable.Tbody>
      </StackTable>
    </Table.ScrollContainer>
  );
}

function Pair({ rulesId, boardId, caseId }: { rulesId: string; boardId: string; caseId: string }) {
  const rules = useSide(rulesId);
  const board = useSide(boardId);
  const scenarios = useScenarios();
  const scenario = scenarios.data?.scenarios.find((s) => s.id === 'S8');
  const error = rules.error ?? board.error;
  if (error) return <ErrorAlert error={error} title="The two S8 cases could not be read" />;
  // Until the scenario is read, a wrong write would show as delivered and verified
  if (!rules.side || !board.side || scenarios.isPending) return <NotYet>Reading the two cases…</NotYet>;
  const rows = evidenceRows(rules.side.evidence, board.side.evidence);
  const same = rows.filter((r) => r.same);
  const apart = rows.filter((r) => !r.same);
  const trace = board.detail?.links?.visualTrace;
  return (
    <Stack gap="sm">
      <SimpleGrid cols={{ base: 1, md: 2 }} spacing="sm">
        <SideCard side={rules.side} title="Rules only" current={rulesId === caseId} scenario={scenario} />
        <SideCard side={board.side} title="The board" current={boardId === caseId} scenario={scenario} />
      </SimpleGrid>
      {same.length ? (
        <Stack gap={4}>
          <Text size="sm" fw={600}>
            Both runs read the same evidence
          </Text>
          <EvidenceTable rows={same} rulesId={rulesId} boardId={boardId} />
        </Stack>
      ) : null}
      {/* Only a time and two digests differ, each run's own: they say nothing about the decision, so they stay a click away */}
      {apart.length ? (
        <TechDetail label="Times and digests, which differ on each run" kind="data">
          <Stack gap="xs">
            <EvidenceTable rows={apart} rulesId={rulesId} boardId={boardId} />
            <Text size="xs" c="dimmed">
              The digests differ because each case's evidence was collected on its own run of the scenario, at
              its own time: the receiver's epoch, the times the operations applied and the message ids are
              that run's. The facts a decision rests on read the same.
            </Text>
          </Stack>
        </TechDetail>
      ) : null}
      {trace ? (
        <Group gap={6}>
          <Text size="sm" c="dimmed">
            The board's run in the Management Portal:
          </Text>
          <PortalLink
            href={trace}
            what={`the Visual Trace of session ${board.detail?.ensSessionId ?? ''}`}
            screenshot={traceScreenshot({ scenario: 'S8', mode: 'board' })}
          >
            Visual Trace
          </PortalLink>
        </Group>
      ) : null}
    </Stack>
  );
}

/** The recorded pair in the trial, for a site that doesn't play Rules only: opened on the board's case, side by side. */
const TRIAL_COMPARE = trialHref(`#/cases/${TRIAL_BOARD_CASE}?show=compare`);

/**
 * S8 played by rules alone and by the board, side by side: what each did at the receiver, and the evidence both read.
 * On an S8 case's page; `?show=compare` (the demo's path through the recorded cases) scrolls to it.
 */
export function S8Compare({ caseId, focus }: { caseId: string; focus: boolean }) {
  const hidden = scenariosHidden(useCan());
  const cases = useCases({ scenario: 'S8', limit: 50 });
  const { rules, board } = s8Pair(cases.data?.items ?? []);
  const ref = useRef<HTMLDivElement>(null);
  const ready = cases.isSuccess;
  useEffect(() => {
    if (focus && ready) ref.current?.scrollIntoView?.({ block: 'start' });
  }, [focus, ready]);
  const missing = [!rules ? 'Rules only' : '', !board ? 'board' : ''].filter(Boolean);
  return (
    <div ref={ref}>
      <Section
        id="s8-compare"
        title="S8 side by side: Rules only and the board"
        note="The same failure played twice. Two systems moved the patient in the same minute: Rules only writes over the bed manager's ward with every check passed; the board sees the evidence can't decide which movement is current."
      >
        {cases.isError ? <ErrorAlert error={cases.error} title="The S8 cases could not be listed" /> : null}
        {/* The online demo's visitor can't run a scenario, so "not played yet" would promise what never comes */}
        {ready && missing.length && hidden ? (
          <NotYet>
            {"Rules only isn't played on this demo. "}
            <Anchor href={TRIAL_COMPARE} size="sm">
              See the two side by side in the trial
            </Anchor>
          </NotYet>
        ) : null}
        {ready && missing.length && !hidden ? (
          <NotYet>{`S8 has not been played in ${missing.map((m) => humanize(m).toLowerCase()).join(' or ')} mode here yet.`}</NotYet>
        ) : null}
        {rules && board ? <Pair rulesId={rules.caseId} boardId={board.caseId} caseId={caseId} /> : null}
      </Section>
    </div>
  );
}

/**
 * What went wrong on the run by Rules only, said on the case itself: its verification is green and it asks for nothing,
 * so without this a reader of S8 sees a success. Shown only for a run that wrote (a resolved resend), with or without the
 * other run to compare it with. The wards are S8's own: its feed moves the patient to WARD-B and its bed manager to WARD-C.
 */
export function S8RulesNote({ c }: { c: CaseDetail }) {
  if (c.scenario !== 'S8' || c.mode !== 'rules' || c.state !== 'resolved' || c.disposition !== 'resend')
    return null;
  return (
    <Paper withBorder p="xs" mb="xs" data-testid="s8-rules-note">
      <Group gap="xs" wrap="nowrap" align="flex-start">
        <IconAlertTriangle size={18} aria-hidden style={{ flexShrink: 0 }} />
        <Text size="sm" fw={600}>
          Wrote WARD-B over the bed manager's WARD-C. Every check passed; only the board caught it.
        </Text>
      </Group>
    </Paper>
  );
}

/**
 * A compact strip near the top of an S8 case played by rules alone or by the board: the same failure's other run,
 * linked, with its outcome against S8's expectation (rules alone's write reads "Not as expected"), how the evaluation
 * scored each mode's play of S8 ("Board: as expected", "Rules alone: differs, wrote WARD-B"), and a button to the side
 * by side. A board run that sent nothing also says what that kept from happening, since its own page shows only a
 * case waiting for a person; that holds with no other run to link, as on the online demo. The wards are S8's own.
 */
export function CounterpartStrip({
  c,
  writesSent,
  onCompare,
}: {
  c: CaseDetail;
  /** The writes this case sent, from its attempts. */
  writesSent: number;
  onCompare: () => void;
}) {
  const mine = c.scenario === 'S8' && (c.mode === 'rules' || c.mode === 'board');
  const hidden = scenariosHidden(useCan());
  const cases = useCases({ scenario: 'S8', limit: 50 }, mine);
  const scenario = useScenarios().data?.scenarios.find((s) => s.id === 'S8');
  const { rules, board } = s8Pair(cases.data?.items ?? []);
  if (!mine) return null;
  const stakes =
    c.mode === 'board' && c.state === 'escalated' && writesSent === 0
      ? "A resend here writes WARD-B over the bed manager's WARD-C with every check passed. The board sent nothing."
      : '';
  const other = rules && board ? (c.mode === 'board' ? rules : board) : undefined;
  const counterpart = other && other.caseId !== c.caseId ? other : undefined;
  if (!counterpart && !stakes) return null;
  const otherRun = c.mode === 'board' ? 'Rules only' : 'The board';
  const played = playedFor('S8');
  const marks = counterpart
    ? [playedMark('board', played?.board), playedMark('rules', played?.rules, rules?.ward)].filter(
        (m) => m !== null,
      )
    : [];
  return (
    <Paper
      withBorder
      p="xs"
      mb="md"
      component="section"
      aria-label={counterpart ? 'Same failure, two runs' : 'What a resend would do'}
    >
      <Stack gap={6}>
        {counterpart ? (
          <Group gap="sm" wrap="wrap" justify="space-between">
            <Group gap={6} wrap="wrap">
              <Text size="sm" fw={600}>
                Same failure, two runs:
              </Text>
              <Text size="sm">{`${otherRun} played it as`}</Text>
              <Anchor
                component={Link}
                to={`/cases/${encodeURIComponent(counterpart.caseId)}`}
                size="sm"
                fw={600}
              >
                {counterpart.caseId}
              </Anchor>
              <OutcomeBadge c={counterpart} scenario={scenario} />
            </Group>
            <Button
              size="xs"
              variant="default"
              leftSection={<IconArrowsLeftRight size={14} aria-hidden />}
              onClick={onCompare}
            >
              Compare the two runs
            </Button>
          </Group>
        ) : null}
        {stakes ? (
          <Text size="sm" fw={600} data-testid="s8-stakes">
            {stakes}
          </Text>
        ) : null}
        {!counterpart && hidden ? (
          <Anchor href={TRIAL_COMPARE} size="sm">
            See the two side by side in the trial
          </Anchor>
        ) : null}
        {/* The evaluation's marks for S8 in each mode, from its recorded passes */}
        {marks.length ? (
          <Group gap={6} wrap="wrap" data-testid="played-marks">
            <Text size="xs" c="dimmed">
              In the evaluation:
            </Text>
            {marks.map((m) => (
              <StatusBadge key={m.label} tone={m.tone} label={m.label} variant="outline" />
            ))}
          </Group>
        ) : null}
      </Stack>
    </Paper>
  );
}
