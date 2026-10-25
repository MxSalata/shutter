import { Anchor, Badge, Card, Group, SimpleGrid, Stack, Table, Text, VisuallyHidden } from '@mantine/core';
import { IconCheck } from '@tabler/icons-react';
import { useEffect, useRef } from 'react';
import { Link } from 'react-router';
import { useAttempts, useCase, useCases, useClosure, usePlan, useSnapshot } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PortalLink } from '@/components/PortalLink';
import { DispositionBadge, StateBadge } from '@/components/StateBadge';
import { humanize } from '@/lib/format';
import { traceScreenshot } from '@/lib/screenshots';
import type { CaseDetail } from '@/api/types';
import { compareSide, evidenceRows, s8Pair, type CompareSide } from './compare';
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
          <Badge
            color={side.writes ? 'red' : 'teal'}
            variant="light"
            style={{ textTransform: 'none' }}
          >{`${side.writes} write${side.writes === 1 ? '' : 's'}`}</Badge>
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
                        <IconCheck size={16} color="var(--mantine-color-teal-6)" aria-hidden />
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
