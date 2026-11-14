import { Accordion, Group, List, Stack, Table, Text } from '@mantine/core';
import { IconCircleCheck, IconCircleX } from '@tabler/icons-react';
import type { GateDecision, PlanView, ReceiverKind, Snapshot } from '@/api/types';
import { Digest } from '@/components/Digest';
import { ErrorAlert } from '@/components/ErrorAlert';
import { DispositionBadge } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { checkCounts, CHECK_STATES, checkState, gateOutcome } from '@/lib/status';
import { asArray, asObject } from '@/lib/json';
import { checksOf, fhirSummary, kindOfPlan, quotedVersion, receiverKind, shownFailureText } from './derive';
import { planLeader } from './follows';
import { humanize } from '@/lib/format';
import { KeyValueList } from '@/components/KeyValueList';
import { StackTable } from '@/components/StackTable';
import { NotYet, Section } from './Section';
import { PlanHeadline } from './PlanHeadline';
import { planWords, type ActionCase } from './planAction';
import { capitalReceiverNoun, receiverNoun } from './receiver';
import { useDetail } from '@/stores/appearance';

const STAGES: Record<string, string> = {
  proposal: 'At proposal, before the rehearsal',
  approval: 'At approval',
  dispatch: 'At dispatch, after the approval and a fresh read of the receiver',
};

/** A FHIR case's stages: no dry run exists for that receiver, so no stage comes before a rehearsal. */
const FHIR_STAGES: Record<string, string> = {
  ...STAGES,
  proposal: 'At proposal',
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
  capability: 'Does the receiver take conditional writes, keep receipts and history?',
  catalogue: 'Does an entry of the scenario catalogue match the evidence?',
  rehearsal: "Did the receiver's dry run say this would apply?",
};

/**
 * The FHIR gate's questions: its own rows, and the two whose ADT question would be false there (no dry run exists for a
 * FHIR receiver; its capability is what was measured, not what it declares).
 */
const FHIR_CHECK_QUESTIONS: Record<string, string> = {
  ...CHECK_QUESTIONS,
  rehearsal: 'No dry run exists for this receiver. What stands in its place?',
  capability: 'Does the server refuse a stale If-Match and keep version history, as measured?',
  enablement: 'Has the site turned recovery on for this receiver?',
  representation: 'Is the record whole enough to change?',
  mapping: 'Are both wards mapped to Locations that still match?',
  plan_shape: 'Is the change exactly the one move?',
  history: 'Was the history read, and is it free of an earlier update?',
  earlier_write: 'Is an earlier update of this case still unsettled?',
};

/** The receiver kind behind a plan's panels: the evidence's route.kind, else the FHIR gate's own policy version. */
function planKind(view: PlanView | null | undefined, snapshot?: Snapshot | null): ReceiverKind | undefined {
  return receiverKind(snapshot) ?? kindOfPlan(view);
}

/** The Encounter version a FHIR plan is conditional on: the version id quoted and the ETag verbatim, from the evidence. */
function encounterVersion(snapshot: Snapshot | null | undefined): string {
  const e = fhirSummary(snapshot)?.encounter;
  if (!e?.etag) return '';
  return `${quotedVersion(e.version_id)} (ETag ${e.etag})`;
}

function GateTable({ d, fhir }: { d: GateDecision; fhir: boolean }) {
  const checks = checksOf(d);
  const questions = fhir ? FHIR_CHECK_QUESTIONS : CHECK_QUESTIONS;
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
            {checks.map((c, i) => {
              const r = CHECK_STATES[checkState(c)];
              // One check can be recorded twice (an order or result: conformance blocks UNMAPPABLE and passes PARSED)
              return (
                <StackTable.Tr key={`${c.check}:${c.reason_code ?? ''}:${i}`}>
                  <StackTable.Td>
                    <Text size="sm">{humanize(c.check)}</Text>
                    {questions[c.check] ? (
                      <Text size="xs" c="dimmed">
                        {questions[c.check]}
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
                    <Text size="sm">{shownFailureText(c.detail)}</Text>
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

/**
 * The plan, led by what it does: the action in plain words as the section's headline, with the conditions the write
 * goes on beside it, then why. Its exact terms (the operation key, the digests, the catalogue entry, its version and
 * the preconditions as its author wrote them) are one click away under "Plan details", open in Technical.
 */
export function PlanPanel({
  view,
  loading,
  error,
  onRetry,
  c,
  snapshot,
}: {
  view: PlanView | null | undefined;
  loading: boolean;
  /** The case, for its own operation and its receiver: the headline names both. */
  c: ActionCase;
  /** The case's evidence, once read: the mapped operation and what the route calls the receiver. */
  snapshot?: Snapshot | null;
  /** The plan's read error: shown in place of the panel's body. */
  error?: unknown;
  onRetry?: () => void;
}) {
  const p = view?.plan;
  const fhir = planKind(view, snapshot) === 'fhir_r4';
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
      aside={p ? <DispositionBadge disposition={p.disposition} kind={fhir ? 'fhir_r4' : undefined} /> : null}
    >
      {!p && error ? <ErrorAlert error={error} title="The plan could not be read" onRetry={onRetry} /> : null}
      {!p && !error ? (
        <NotYet>{loading ? 'Loading…' : 'No plan yet: the investigation is still running.'}</NotYet>
      ) : null}
      {p ? (
        <Stack gap="sm">
          <PlanHeadline words={planWords(p, c, snapshot)} />
          {p.why || p.summary ? (
            <Text size="sm" maw="75ch" data-testid="plan-why">
              <Text span inherit fw={600}>
                {'Why: '}
              </Text>
              {p.why || p.summary}
            </Text>
          ) : null}
          {disagreements.length ? (
            <Text size="sm">{`${disagreements.length} disagreement(s) kept in the plan.`}</Text>
          ) : null}
          <TechDetail label="Plan details" kind="data">
            <Stack gap="sm">
              <KeyValueList
                rows={[
                  ["The author's summary", p.why ? p.summary : ''],
                  fhir
                    ? ['Conditional on Encounter version', write ? encounterVersion(snapshot) : '']
                    : [
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
                  [
                    'Plan digest',
                    <Stack key="d" gap={0}>
                      <Digest value={p.digest} label="plan digest" />
                      <Text size="xs" c="dimmed">
                        A fingerprint of the exact plan: any change to it gives another digest.
                      </Text>
                    </Stack>,
                  ],
                  [
                    'Catalogue entry',
                    p.catalogueEntry ? (
                      <Stack key="c" gap={0}>
                        <Text size="sm">
                          {`${p.catalogueEntry}, ${p.outcome === 'preferred' || !p.outcome ? 'the preferred outcome' : humanize(p.outcome).toLowerCase()}`}
                        </Text>
                        <Text size="xs" c="dimmed">
                          The scenario catalogue lists the failures Shutter knows and the safe outcome of
                          each.
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
                            : planLeader(p.createdBy)
                              ? `the board of case ${planLeader(p.createdBy)}`
                              : p.createdBy
                    }`,
                  ],
                ]}
              />
              {preconditions.length ? (
                <Stack gap={2}>
                  <Text size="xs" fw={600} c="dimmed">
                    Preconditions as the plan&apos;s author wrote them, when it ran
                  </Text>
                  <List size="sm" spacing={2}>
                    {preconditions.map((x, i) => (
                      <List.Item key={i}>{x}</List.Item>
                    ))}
                  </List>
                </Stack>
              ) : null}
              {disagreements.length ? null : (
                <Text size="xs" c="dimmed">
                  No disagreements were recorded.
                </Text>
              )}
            </Stack>
          </TechDetail>
        </Stack>
      ) : null}
    </Section>
  );
}

/**
 * The gate's decisions on the plan, the latest open when it stopped the write or in Technical. The gate checks the plan mechanically against the evidence, before
 * the rehearsal and again before dispatch.
 */
export function GatePanel({
  view,
  loading,
  error,
  onRetry,
  snapshot,
}: {
  view: PlanView | null | undefined;
  loading: boolean;
  /** The plan's read error: shown in place of the panel's body. */
  error?: unknown;
  onRetry?: () => void;
  /** The case's evidence, for its route.kind. */
  snapshot?: Snapshot | null;
}) {
  const decisions = view?.gateDecisions ?? [];
  const fhir = planKind(view, snapshot) === 'fhir_r4';
  const stages = fhir ? FHIR_STAGES : STAGES;
  const technical = useDetail() === 'technical';
  // The latest decision opens by itself when it stopped the write, or for the engineer in Technical; a clean pass
  // stays closed under its badge ("Passed 10 of 10 applicable checks"), its rows a click away
  const latest = decisions.at(-1);
  const openLatest = technical || (!!latest && latest.outcome !== 'pass');
  return (
    <Section
      id="gate"
      title="The gate"
      note={
        fhir
          ? 'Mechanical checks of the plan against the evidence, at proposal and again before dispatch. No dry run exists for this receiver: the rehearsal row says what stands in its place. An unknown blocks a write as surely as a failed check.'
          : "Mechanical checks of the plan against the evidence, before the rehearsal and again before dispatch. An unknown blocks a write as surely as a failed check; the agents can explain the gate's result but cannot override it."
      }
    >
      {decisions.length ? (
        <Accordion
          variant="separated"
          multiple
          defaultValue={openLatest ? [String(decisions.length - 1)] : []}
          chevronPosition="left"
        >
          {decisions.map((d, i) => (
            <Accordion.Item key={`${d.stage}-${i}`} value={String(i)}>
              <Accordion.Control>
                <Group gap="sm" wrap="wrap">
                  <Text size="sm" fw={600}>
                    {stages[d.stage] ?? humanize(d.stage)}
                  </Text>
                  <StatusBadge {...gateOutcome(d.outcome, checksOf(d))} />
                </Group>
              </Accordion.Control>
              <Accordion.Panel>
                <GateTable d={d} fhir={fhir} />
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
  snapshot,
}: {
  view: PlanView | null | undefined;
  write: boolean;
  /** The case's receiver (its production item). */
  receiver?: string;
  /** The case's evidence, for its route.kind. */
  snapshot?: Snapshot | null;
}) {
  const noun = receiverNoun(receiver);
  const r = view?.rehearsal;
  if (planKind(view, snapshot) === 'fhir_r4' && !r)
    return (
      <Section
        id="rehearsal"
        title="Rehearsal"
        note="No dry run exists for this receiver. What stands in its place is the gate's rehearsal row, at proposal and again before dispatch, and an update sent only with If-Match on the version read."
      >
        <NotYet>
          {write ? 'No dry run exists for this receiver' : 'Nothing to rehearse: the plan writes nothing.'}
        </NotYet>
      </Section>
    );
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
