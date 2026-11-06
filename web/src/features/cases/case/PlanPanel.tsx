import { Accordion, Group, List, Stack, Table, Text } from '@mantine/core';
import { IconCircleCheck, IconCircleX } from '@tabler/icons-react';
import type { GateDecision, PlanView } from '@/api/types';
import { Digest } from '@/components/Digest';
import { ErrorAlert } from '@/components/ErrorAlert';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { checkCounts, CHECK_STATES, checkState, gateOutcome } from '@/lib/status';
import { asArray, asObject } from '@/lib/json';
import { checksOf } from './derive';
import { humanize } from '@/lib/format';
import { KeyValueList } from '@/components/KeyValueList';
import { StackTable } from '@/components/StackTable';
import { NotYet, Section } from './Section';
import { capitalReceiverNoun, receiverNoun } from './receiver';

const STAGES: Record<string, string> = {
  proposal: 'At proposal, before the rehearsal',
  approval: 'At approval',
  dispatch: 'At dispatch, after the approval and a fresh read of the receiver',
};

/** What each of the gate's checks asks, in a line, under its name. */
const CHECK_QUESTIONS: Record<string, string> = {
  identity: 'Same patient and encounter at the receiver?',
  conformance: 'Does the message parse against its schema?',
  intent: "Does the plan send only the case's own operation, unchanged?",
  ordering: 'Has no later event moved the encounter on?',
  state_transition: "Can the encounter's state at the receiver take this event?",
  effect: 'Is the operation not committed at the receiver already?',
  authorization: "Has a person, or the site's written policy, released the write?",
  concurrency: 'Is the receiver still at the version the plan is conditional on?',
  evidence: 'Is the evidence recent enough to act on?',
  capability: 'Does the receiver take conditional writes and keep receipts?',
  catalogue: 'Does an entry of the scenario catalogue match the evidence?',
  rehearsal: "Did the receiver's dry run say this would apply?",
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
      {/* On a phone each check is a card: its name and question beside the result, then the code and the detail */}
      <Table.ScrollContainer minWidth={560} className="stack-scroll">
        <StackTable verticalSpacing={4} className="stack-table stack-cards">
          <StackTable.Thead>
            <StackTable.Tr>
              <StackTable.Th w="26%">Check</StackTable.Th>
              <StackTable.Th w={150}>Result</StackTable.Th>
              <StackTable.Th w={210}>Reason code</StackTable.Th>
              <StackTable.Th>Detail</StackTable.Th>
            </StackTable.Tr>
          </StackTable.Thead>
          <StackTable.Tbody>
            {checks.map((c) => {
              const r = CHECK_STATES[checkState(c)];
              return (
                <StackTable.Tr key={c.check}>
                  <StackTable.Td>
                    <Text size="sm">{humanize(c.check)}</Text>
                    {CHECK_QUESTIONS[c.check] ? (
                      <Text size="xs" c="dimmed">
                        {CHECK_QUESTIONS[c.check]}
                      </Text>
                    ) : null}
                  </StackTable.Td>
                  <StackTable.Td data-label="Result">
                    <StatusBadge {...r} hint={undefined} size="sm" />
                  </StackTable.Td>
                  <StackTable.Td data-label="Reason code">
                    <Text size="xs" className="mono-wrap">
                      {c.reason_code}
                    </Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="Detail">
                    <Text size="sm">{c.detail}</Text>
                  </StackTable.Td>
                </StackTable.Tr>
              );
            })}
          </StackTable.Tbody>
        </StackTable>
      </Table.ScrollContainer>
    </Stack>
  );
}

export function PlanPanel({
  view,
  loading,
  error,
  onRetry,
  receiver,
}: {
  view: PlanView | null | undefined;
  loading: boolean;
  /** The case's receiver (its production item), named where the plan says what it writes. */
  receiver?: string;
  /** The plan's read error: shown in place of the panel's body. */
  error?: unknown;
  onRetry?: () => void;
}) {
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
      note="One plan, bound by its digest, a fingerprint of its exact content that any change alters: what the gate checks, and what a release names."
      aside={p ? <DispositionBadge disposition={p.disposition} /> : null}
    >
      {!p && error ? <ErrorAlert error={error} title="The plan could not be read" onRetry={onRetry} /> : null}
      {!p && !error ? (
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
                  : `Nothing is written to ${receiverNoun(receiver)}`,
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
                p.catalogueEntry ? (
                  <Stack key="c" gap={0}>
                    <Text size="sm">
                      {`${p.catalogueEntry}, ${p.outcome === 'preferred' || !p.outcome ? 'the preferred outcome' : humanize(p.outcome).toLowerCase()}${p.why ? `: ${p.why}` : ''}`}
                    </Text>
                    <Text size="xs" c="dimmed">
                      The scenario catalogue lists the failures Shutter knows and the safe outcome of each.
                    </Text>
                  </Stack>
                ) : (
                  ''
                ),
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
                Preconditions as the plan's author wrote them, when it ran
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
export function GatePanel({
  view,
  loading,
  error,
  onRetry,
}: {
  view: PlanView | null | undefined;
  loading: boolean;
  /** The plan's read error: shown in place of the panel's body. */
  error?: unknown;
  onRetry?: () => void;
}) {
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
      ) : error && !view ? (
        <ErrorAlert error={error} title="The gate's decisions could not be read" onRetry={onRetry} />
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

/** The receiver's dry run of the exact action, read from the rehearsal's own response (CONTRACTS 1.4, WIC-2.5). */
export function RehearsalPanel({
  view,
  write,
  receiver,
}: {
  view: PlanView | null | undefined;
  write: boolean;
  /** The case's receiver (its production item). */
  receiver?: string;
}) {
  const noun = receiverNoun(receiver);
  const r = view?.rehearsal;
  const response = asObject(r?.response) ?? {};
  const before = asObject(response.encounter_before);
  const after = asObject(response.encounter_after);
  const describe = (e: Record<string, unknown> | undefined) =>
    e
      ? `${humanize(String(e.state ?? ''))}${e.ward ? ` in ${String(e.ward)}` : ''}, version ${String(e.version ?? '')}`
      : `not known to ${noun}`;
  return (
    <Section
      id="rehearsal"
      title="Rehearsal"
      note={`A dry run of the exact action on ${noun} itself, inside a transaction it rolls back. It shows the action would validate and apply against the state it read; it reserves nothing. The dispatch is a separate conditional write, checked again first.`}
      aside={
        r ? (
          <StatusBadge
            tone={r.wouldApply ? 'positive' : 'blocking'}
            label={
              r.wouldApply
                ? 'Would apply'
                : !r.httpStatus
                  ? 'No answer'
                  : `Would not apply${r.reason ? `: ${r.reason}` : ''}`
            }
            hint={
              r.httpStatus
                ? 'The dry run checks the action against the receiver; it was rolled back'
                : 'The receiver did not answer the dry run, so it shows nothing either way'
            }
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
            [
              `${capitalReceiverNoun(receiver)} answered`,
              // No answer shows nothing either way: not that it would fail, and not that anything rolled back
              r.httpStatus ? `HTTP ${r.httpStatus}${r.reason ? `, ${r.reason}` : ''}` : 'No answer',
            ],
            ...(r.httpStatus
              ? [['Rolled back', 'Yes: nothing was committed and no receipt was stored'] as [string, string]]
              : []),
            ['When', <Timestamp key="t" iso={r.at} />],
          ]}
        />
      ) : null}
    </Section>
  );
}
