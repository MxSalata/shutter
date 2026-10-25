import { Accordion, Group, List, Stack, Table, Text } from '@mantine/core';
import { IconCircleCheck, IconCircleX } from '@tabler/icons-react';
import type { GateDecision, PlanView } from '@/api/types';
import { Digest } from '@/components/Digest';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { checkCounts, CHECK_STATES, checkState, gateOutcome } from '@/lib/status';
import { asArray, asObject } from '@/lib/json';
import { checksOf } from './derive';
import { humanize } from '@/lib/format';
import { KeyValueList } from '@/components/KeyValueList';
import { NotYet, Section } from './Section';

const STAGES: Record<string, string> = {
  proposal: 'At proposal, before the rehearsal',
  approval: 'At approval',
  dispatch: 'At dispatch, after the approval and a fresh read of the receiver',
};

function GateTable({ d }: { d: GateDecision }) {
  const checks = checksOf(d);
  return (
    <Stack gap={6}>
      <Group gap="sm" wrap="wrap">
        <Text size="xs" c="dimmed">
          {`${checkCounts(checks)}. Policy ${d.policyVersion}, checked`}
        </Text>
        <Timestamp iso={d.at} size="xs" c="dimmed" />
      </Group>
      <Table.ScrollContainer minWidth={560}>
        <Table verticalSpacing={4}>
          <Table.Thead>
            <Table.Tr>
              <Table.Th w={150}>Check</Table.Th>
              <Table.Th w={150}>Result</Table.Th>
              <Table.Th w={210}>Reason code</Table.Th>
              <Table.Th>Detail</Table.Th>
            </Table.Tr>
          </Table.Thead>
          <Table.Tbody>
            {checks.map((c) => {
              const r = CHECK_STATES[checkState(c)];
              return (
                <Table.Tr key={c.check}>
                  <Table.Td>
                    <Text size="sm">{humanize(c.check)}</Text>
                  </Table.Td>
                  <Table.Td>
                    <StatusBadge {...r} hint={undefined} size="sm" />
                  </Table.Td>
                  <Table.Td>
                    <Text size="xs" className="mono-wrap">
                      {c.reason_code}
                    </Text>
                  </Table.Td>
                  <Table.Td>
                    <Text size="sm">{c.detail}</Text>
                  </Table.Td>
                </Table.Tr>
              );
            })}
          </Table.Tbody>
        </Table>
      </Table.ScrollContainer>
    </Stack>
  );
}

export function PlanPanel({ view, loading }: { view: PlanView | null | undefined; loading: boolean }) {
  const p = view?.plan;
  const body = asObject(p?.plan) ?? {};
  const action = asObject(body.action) ?? {};
  const preconditions = asArray<string>(p?.preconditions ?? body.preconditions);
  const disagreements = asArray(p?.disagreements ?? body.disagreements);
  const write = !!p?.operationKey && ['resend'].includes(p.disposition);
  return (
    <Section
      id="plan"
      title="The plan"
      note="One plan, bound by its digest: what the gate checks, and what a release names."
      aside={p ? <DispositionBadge disposition={p.disposition} /> : null}
    >
      {!p ? (
        <NotYet>{loading ? 'Loading…' : 'No plan yet: the investigation is still running.'}</NotYet>
      ) : null}
      {p ? (
        <Stack gap="sm">
          <Text size="sm" fw={500}>
            {p.summary}
          </Text>
          <KeyValueList
            rows={[
              [
                'Exact action',
                write
                  ? `${humanize(p.actionType || String(action.type ?? 'resend'))} the case's operation`
                  : 'Nothing is written to the downstream system',
              ],
              [
                'Conditional on receiver version',
                write ? String(p.expectedVersion ?? action.expected_version ?? '') : '',
              ],
              [
                'Operation key',
                write ? <Digest key="k" value={p.operationKey} label="operation key" length={80} /> : '',
              ],
              [
                'Payload digest',
                p.payloadDigest ? <Digest key="pd" value={p.payloadDigest} label="payload digest" /> : '',
              ],
              ['Plan digest', <Digest key="d" value={p.digest} label="plan digest" />],
              [
                'Catalogue entry',
                p.catalogueEntry
                  ? `${p.catalogueEntry}, ${p.outcome === 'preferred' || !p.outcome ? 'the preferred outcome' : humanize(p.outcome).toLowerCase()}${p.why ? `: ${p.why}` : ''}`
                  : '',
              ],
              [
                'Plan version',
                `v${p.version}, by ${
                  p.createdBy?.startsWith('run:')
                    ? 'the coordinator'
                    : p.createdBy === 'rules'
                      ? 'the rules'
                      : p.createdBy?.startsWith('policy:')
                        ? `the site's policy for ${p.createdBy.slice('policy:'.length)}`
                        : p.createdBy
                }`,
              ],
            ]}
          />
          {preconditions.length ? (
            <Stack gap={2}>
              <Text size="xs" fw={600} c="dimmed">
                Preconditions the plan states
              </Text>
              <List size="sm" spacing={2}>
                {preconditions.map((x, i) => (
                  <List.Item key={i}>{x}</List.Item>
                ))}
              </List>
            </Stack>
          ) : null}
          <Text size="xs" c="dimmed">
            {disagreements.length
              ? `${disagreements.length} disagreement(s) kept in the plan.`
              : 'No disagreements were recorded.'}
          </Text>
        </Stack>
      ) : null}
    </Section>
  );
}

/**
 * The gate's decisions on the plan, the latest open. The gate checks the plan mechanically against the evidence, before
 * the rehearsal and again before dispatch.
 */
export function GatePanel({ view, loading }: { view: PlanView | null | undefined; loading: boolean }) {
  const decisions = view?.gateDecisions ?? [];
  return (
    <Section
      id="gate"
      title="The gate"
      note="Mechanical checks of the plan against the evidence, before the rehearsal and again before dispatch. An unknown blocks a write as surely as a failed check; the agents can explain the gate's result but cannot override it."
    >
      {decisions.length ? (
        <Accordion
          variant="separated"
          multiple
          defaultValue={[String(decisions.length - 1)]}
          chevronPosition="left"
        >
          {decisions.map((d, i) => (
            <Accordion.Item key={`${d.stage}-${i}`} value={String(i)}>
              <Accordion.Control>
                <Group gap="sm" wrap="wrap">
                  <Text size="sm" fw={600}>
                    {STAGES[d.stage] ?? humanize(d.stage)}
                  </Text>
                  <StatusBadge {...gateOutcome(d.outcome, checksOf(d))} />
                </Group>
              </Accordion.Control>
              <Accordion.Panel>
                <GateTable d={d} />
              </Accordion.Panel>
            </Accordion.Item>
          ))}
        </Accordion>
      ) : (
        <NotYet>
          {loading
            ? 'Loading…'
            : view?.plan
              ? 'The gate has not checked this plan yet.'
              : 'No plan for the gate yet.'}
        </NotYet>
      )}
    </Section>
  );
}

/** The downstream system's dry run of the exact action, read from the rehearsal's own response (CONTRACTS 1.4, WIC-2.5). */
export function RehearsalPanel({ view, write }: { view: PlanView | null | undefined; write: boolean }) {
  const r = view?.rehearsal;
  const response = asObject(r?.response) ?? {};
  const before = asObject(response.encounter_before);
  const after = asObject(response.encounter_after);
  const describe = (e: Record<string, unknown> | undefined) =>
    e
      ? `${humanize(String(e.state ?? ''))}${e.ward ? ` in ${String(e.ward)}` : ''}, version ${String(e.version ?? '')}`
      : 'not known to the downstream system';
  return (
    <Section
      id="rehearsal"
      title="Rehearsal"
      note="A dry run of the exact action on the downstream system itself, inside a transaction it rolls back. It shows the action would validate and apply against the state it read; it reserves nothing. The dispatch is a separate conditional write, checked again first."
      aside={
        r ? (
          <StatusBadge
            tone={r.wouldApply ? 'positive' : 'blocking'}
            label={r.wouldApply ? 'Would apply' : `Would not apply${r.reason ? `: ${r.reason}` : ''}`}
            hint="The dry run checks the action against the receiver; it was rolled back"
            icon={r.wouldApply ? IconCircleCheck : IconCircleX}
          />
        ) : null
      }
    >
      {!r ? (
        <NotYet>{write ? 'Not rehearsed yet.' : 'Nothing to rehearse: the plan writes nothing.'}</NotYet>
      ) : null}
      {r ? (
        <KeyValueList
          rows={[
            [
              'Checked against',
              before !== undefined || 'encounter_before' in response ? describe(before) : '',
            ],
            ['Would leave', after ? describe(after) : ''],
            ['Epoch', response.epoch !== undefined ? String(response.epoch) : ''],
            ['The downstream system answered', `HTTP ${r.httpStatus}${r.reason ? `, ${r.reason}` : ''}`],
            ['Rolled back', 'Yes: nothing was committed and no receipt was stored'],
            ['When', <Timestamp key="t" iso={r.at} />],
          ]}
        />
      ) : null}
    </Section>
  );
}
