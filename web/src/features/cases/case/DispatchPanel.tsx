import { Accordion, Card, Stack, Text } from '@mantine/core';
import { useAttempts } from '@/api/hooks';
import type { Attempt, Verification } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { JsonBlock } from '@/components/JsonBlock';
import { KeyValueList } from '@/components/KeyValueList';
import { Digest } from '@/components/Digest';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { attempt, caseState, verification } from '@/lib/status';
import { asObject } from '@/lib/json';
import { STOPPED_STATES, WRITE_OUTCOMES } from './receipt';
import { NotYet, Section } from './Section';
import { receiverNoun } from './receiver';

function AttemptCard({ a }: { a: Attempt }) {
  const s = attempt(a.outcome);
  const receipt = asObject(a.receipt);
  return (
    <Stack gap={6}>
      <StatusBadge
        {...s}
        label={`${s.label}${a.httpStatus ? ` (HTTP ${a.httpStatus})` : ''}`}
        w="fit-content"
      />
      <KeyValueList
        rows={[
          ['Sent', <Timestamp key="t" iso={a.at} />],
          ['Conditional on version', String(a.expectedVersion ?? '')],
          [
            'Receipt',
            receipt
              ? `${String(receipt.status ?? '')}: version ${String(receipt.version_before ?? '')} to ${String(receipt.version_after ?? '')}`
              : '',
          ],
          [
            'Payload digest',
            receipt?.payload_digest ? (
              <Digest key="d" value={String(receipt.payload_digest)} label="payload digest" />
            ) : (
              ''
            ),
          ],
          ['Error', a.error],
        ]}
      />
    </Stack>
  );
}

function VerificationCard({ v }: { v: Verification }) {
  const verdict = asObject(v.detail)?.verdict;
  return (
    <Stack gap={6}>
      <StatusBadge {...verification(v.outcome)} w="fit-content" />
      {typeof verdict === 'string' && verdict ? (
        <Text size="xs" c="dimmed">
          Verdict: {verdict}
        </Text>
      ) : null}
      <Text size="sm">{v.summary}</Text>
      <Timestamp iso={v.at} size="xs" c="dimmed" />
      <Accordion variant="contained" chevronPosition="left">
        <Accordion.Item value="detail">
          <Accordion.Control>
            <Text size="xs">What the verifier read</Text>
          </Accordion.Control>
          <Accordion.Panel>
            <JsonBlock value={v.detail} label="verification detail" />
          </Accordion.Panel>
        </Accordion.Item>
      </Accordion>
    </Stack>
  );
}

/**
 * Why a case has no write of Shutter's to verify: a plan that writes nothing, a correction the team made by hand, a
 * case that stopped before its write went out; or a write still to come, or no plan yet.
 */
function NoWrite({
  write,
  planned,
  byHand,
  state,
}: {
  write: boolean;
  planned: boolean;
  byHand: boolean;
  state: string;
}) {
  // A hand closure reads the same whatever the plan was, and a stopped case's write will not go out now
  const stopped = STOPPED_STATES.includes(state);
  if (write && !byHand && !stopped)
    return <NotYet>Nothing to verify yet: nothing has been dispatched.</NotYet>;
  if (byHand || stopped || planned)
    return (
      <Stack gap={4}>
        <StatusBadge {...verification(byHand ? 'by_hand' : 'not_applicable')} w="fit-content" />
        <Text size="sm" c="dimmed">
          {byHand
            ? 'The team corrected the systems by hand and a person closed the case; Shutter wrote nothing and did not check the correction.'
            : planned && !write
              ? "The plan writes nothing to the receiver, so there is no write of Shutter's to verify."
              : `The case was ${caseState(state).label.toLowerCase()} with nothing written, so there is no write of Shutter's to verify.`}
        </Text>
      </Stack>
    );
  return <NotYet>Nothing to verify yet: there is no plan.</NotYet>;
}

interface Props {
  caseId: string;
  open: boolean;
  write: boolean;
  planned: boolean;
  byHand: boolean;
  state: string;
  /** The case's receiver (its production item). */
  receiver?: string;
}

/** The writes Shutter sent: each attempt and what the receiver answered. */
export function DispatchPanel({ caseId, open, write, planned, byHand, state, receiver }: Props) {
  const attempts = useAttempts(caseId, open);
  const list = (attempts.data ?? []).filter((x) => x.attempt);
  return (
    <Section
      id="dispatch"
      title="Dispatch"
      note={`The conditional write, sent only after the release, a fresh read of the receiver and the gate at dispatch. An acknowledgement only says ${receiverNoun(receiver)} answered.`}
    >
      {attempts.isError ? <ErrorAlert error={attempts.error} title="The attempts could not be read" /> : null}
      {attempts.isSuccess && list.length === 0 ? (
        write && !byHand && !STOPPED_STATES.includes(state) ? (
          <NotYet>Nothing dispatched yet.</NotYet>
        ) : (
          <Text size="sm" c="dimmed">
            {planned || byHand || STOPPED_STATES.includes(state)
              ? 'Nothing was sent: Shutter made no write.'
              : 'Nothing to send yet: there is no plan.'}
          </Text>
        )
      ) : null}
      {list.map((x, i) => (
        <Card key={i} padding="sm" withBorder>
          <AttemptCard a={x.attempt!} />
        </Card>
      ))}
    </Section>
  );
}

/** What the verifier found at the receiver after each write, or why there is nothing of Shutter's to verify. */
export function VerificationPanel({ caseId, open, write, planned, byHand, state }: Props) {
  const attempts = useAttempts(caseId, open);
  const list = (attempts.data ?? []).filter((x) => x.verification);
  const sent = (attempts.data ?? []).some((x) => x.attempt);
  // A case stopped with a write and no verification, as a write call that errored: nothing is coming to verify it
  const unverified =
    STOPPED_STATES.includes(state) &&
    (attempts.data ?? []).some((x) => WRITE_OUTCOMES.includes(String(x.attempt?.outcome)));
  return (
    <Section
      id="verification"
      title="Verification"
      note="Verified means Shutter read the receiver's committed history and the receipt after the write and found the effect there."
    >
      {attempts.isError ? <ErrorAlert error={attempts.error} title="The attempts could not be read" /> : null}
      {attempts.isSuccess && list.length === 0 ? (
        sent ? (
          <StatusBadge {...verification(unverified ? 'unresolved' : 'pending')} w="fit-content" />
        ) : (
          <NoWrite write={write} planned={planned} byHand={byHand} state={state} />
        )
      ) : null}
      {list.map((x, i) => (
        <Card key={i} padding="sm" withBorder>
          <VerificationCard v={x.verification!} />
        </Card>
      ))}
    </Section>
  );
}
