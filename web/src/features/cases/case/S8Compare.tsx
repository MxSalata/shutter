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
import { IconArrowsLeftRight, IconEqual } from '@tabler/icons-react';
import { useEffect, useRef } from 'react';
import { Link } from 'react-router';
import { useAttempts, useCase, useCases, useClosure, usePlan, useScenarios, useSnapshot } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { OutcomeBadge } from '@/components/OutcomeBadge';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { humanize } from '@/lib/format';
import { playedFor } from '@/lib/proof';
import { writes } from '@/lib/status';
import { traceScreenshot } from '@/lib/screenshots';
import type { CaseDetail } from '@/api/types';
import { compareSide, evidenceRows, playedMark, s8Pair, type CompareSide } from './compare';
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

function SideCard({ side, title, current }: { side: CompareSide; title: string; current: boolean }) {
  return (
    <Card padding="sm" withBorder>
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
        <Group gap={6}>
          <StateBadge state={side.state} />
          <DispositionBadge disposition={side.disposition} />
          <StatusBadge {...writes(side.writes)} />
        </Group>
        <Text size="sm" fw={500}>
          {side.result}
        </Text>
        {side.verification ? (
          <Text size="sm" c="dimmed">
            {side.verification}
          </Text>
        ) : null}
        {side.dissent ? (
          <Text size="sm" c="dimmed">
            {`Dissent kept in the plan: ${side.dissent}`}
          </Text>
        ) : null}
      </Stack>
    </Card>
  );
}

function Pair({ rulesId, boardId, caseId }: { rulesId: string; boardId: string; caseId: string }) {
  const rules = useSide(rulesId);
  const board = useSide(boardId);
  const error = rules.error ?? board.error;
  if (error) return <ErrorAlert error={error} title="The two S8 cases could not be read" />;
  if (!rules.side || !board.side) return <NotYet>Reading the two cases…</NotYet>;
  const rows = evidenceRows(rules.side.evidence, board.side.evidence);
  const trace = board.detail?.links?.visualTrace;
  return (
    <Stack gap="sm">
      <SimpleGrid cols={{ base: 1, md: 2 }} spacing="sm">
        <SideCard side={rules.side} title="Rules alone" current={rulesId === caseId} />
        <SideCard side={board.side} title="The board" current={boardId === caseId} />
      </SimpleGrid>
      {rows.length ? (
        <Table.ScrollContainer minWidth={560}>
          <Table verticalSpacing={4} fz="sm">
            <Table.Thead>
              <Table.Tr>
                <Table.Th>Evidence</Table.Th>
                <Table.Th>{`Rules alone (${rulesId})`}</Table.Th>
                <Table.Th>{`The board (${boardId})`}</Table.Th>
                <Table.Th>Same</Table.Th>
              </Table.Tr>
            </Table.Thead>
            <Table.Tbody>
              {rows.map((r) => (
                <Table.Tr key={r.label}>
                  <Table.Th scope="row" fw="normal">
                    <Text size="sm" c="dimmed">
                      {r.label}
                    </Text>
                  </Table.Th>
                  <Table.Td className="mono-wrap">{r.rules}</Table.Td>
                  <Table.Td className="mono-wrap">{r.board}</Table.Td>
                  <Table.Td>
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
                  </Table.Td>
                </Table.Tr>
              ))}
            </Table.Tbody>
          </Table>
        </Table.ScrollContainer>
      ) : null}
      <Text size="xs" c="dimmed">
        The digests differ because each case's evidence was collected on its own run of the scenario, at its
        own time: the receiver's epoch, the times the operations applied and the message ids are that run's.
        The facts a decision rests on read the same.
      </Text>
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

/**
 * S8 played by rules alone and by the board, side by side: what each did at the receiver, and the evidence both read.
 * On an S8 case's page; `?show=compare` (the demo's Start here) scrolls to it.
 */
export function S8Compare({ caseId, focus }: { caseId: string; focus: boolean }) {
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
        title="S8 side by side: rules alone and the board"
        note="The same failure played twice. Two systems moved the patient in the same minute; rules alone pass every check and resend, the board sees that the evidence can't decide which movement is current."
      >
        {cases.isError ? <ErrorAlert error={cases.error} title="The S8 cases could not be listed" /> : null}
        {ready && missing.length ? (
          <NotYet>{`S8 has not been played in ${missing.map((m) => humanize(m).toLowerCase()).join(' or ')} mode here yet.`}</NotYet>
        ) : null}
        {rules && board ? <Pair rulesId={rules.caseId} boardId={board.caseId} caseId={caseId} /> : null}
      </Section>
    </div>
  );
}

/**
 * A compact strip near the top of an S8 case played by rules alone or by the board: the same failure's other run,
 * linked, with its outcome against S8's expectation (rules alone's write reads "Not as expected"), how the evaluation
 * scored each mode's play of S8 ("Board: as expected", "Rules alone: differs, wrote WARD-B"), and a button to the side
 * by side. Shown only when both runs exist.
 */
export function CounterpartStrip({ c, onCompare }: { c: CaseDetail; onCompare: () => void }) {
  const mine = c.scenario === 'S8' && (c.mode === 'rules' || c.mode === 'board');
  const cases = useCases({ scenario: 'S8', limit: 50 }, mine);
  const scenario = useScenarios().data?.scenarios.find((s) => s.id === 'S8');
  const { rules, board } = s8Pair(cases.data?.items ?? []);
  if (!mine || !rules || !board) return null;
  const other = c.mode === 'board' ? rules : board;
  if (other.caseId === c.caseId) return null;
  const thisRun = c.mode === 'board' ? "the board's run" : 'the run by rules alone';
  const otherRun = c.mode === 'board' ? 'Rules alone' : 'The board';
  const played = playedFor('S8');
  const marks = [playedMark('board', played?.board), playedMark('rules', played?.rules, rules.ward)].filter(
    (m) => m !== null,
  );
  return (
    <Paper withBorder p="xs" mb="md" component="section" aria-label="Same failure, two runs">
      <Stack gap={6}>
        <Group gap="sm" wrap="wrap" justify="space-between">
          <Group gap={6} wrap="wrap">
            <Text size="sm" fw={600}>
              Same failure, two runs:
            </Text>
            <Text size="sm">{`this is ${thisRun}. ${otherRun} played it as`}</Text>
            <Anchor component={Link} to={`/cases/${encodeURIComponent(other.caseId)}`} size="sm" fw={600}>
              {other.caseId}
            </Anchor>
            <OutcomeBadge c={other} scenario={scenario} />
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
