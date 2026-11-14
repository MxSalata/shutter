import { Accordion, Card, Stack, Text } from '@mantine/core';
import { useAttempts } from '@/api/hooks';
import type { Attempt, AttemptView, ReceiverKind, Snapshot, Verification } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { JsonBlock } from '@/components/JsonBlock';
import { KeyValueList } from '@/components/KeyValueList';
import { Digest } from '@/components/Digest';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { attempt, caseState, fhirAttempt, fhirVerification, FHIR_NOT_SENT, verification } from '@/lib/status';
import { asObject } from '@/lib/json';
import { kindOfAttempts, receiverKind } from './derive';
import { NotCheckedWords } from './NotCheckedWords';
import { STOPPED_STATES, WRITE_OUTCOMES } from './receipt';
import { NotYet, Section } from './Section';
import { AT_THE_RECEIVER, receiverNoun, type NotChecked } from './receiver';

/** The note under Dispatch on a FHIR case. */
export const FHIR_DISPATCH_NOTE =
  "At most one version-aware update (If-Match), sent only after this case's own approval";

/** The note under Verification on a FHIR case. */
export const FHIR_VERIFIED_NOTE =
  'Verified means Shutter found the version carrying its marker in the history the receiver returned, read it back by id when the answer named it, checked it against the approved base, and checked that the current record has not undone the move.';

/** The receiver kind behind the write panels: the evidence's route.kind, else what the attempts themselves say. */
function writeKind(
  snapshot: Snapshot | null | undefined,
  attempts: AttemptView[] | null | undefined,
): ReceiverKind | undefined {
  return receiverKind(snapshot) ?? kindOfAttempts(attempts);
}

/** A FHIR case's one update: the ETag it was conditional on, the server's answer and the body's digest, verbatim. */
function FhirAttemptCard({ a, receipt }: { a: Attempt; receipt: Record<string, unknown> }) {
  const s = fhirAttempt(a.outcome);
  const responseEtag = String(receipt.response_etag ?? '');
  const response = asObject(a.response);
  // Refused by Shutter's own last check before the socket: nothing went, so nothing reads as sent or as the server's
  if (response?.sent === false)
    return (
      <Stack gap={6}>
        <StatusBadge {...FHIR_NOT_SENT} w="fit-content" />
        <KeyValueList
          rows={[
            ['Stopped', <Timestamp key="t" iso={a.at} />],
            ['Reason', String(response.reason_code ?? '')],
            ['Error', a.error],
          ]}
        />
      </Stack>
    );
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
          ['Sent with If-Match', String(receipt.expected_etag ?? '')],
          [
            'Answer',
            a.httpStatus
              ? `HTTP ${a.httpStatus}${responseEtag ? `, ETag ${responseEtag}` : ''}`
              : 'No answer',
          ],
          [
            'Body digest',
            receipt.body_digest ? (
              <Digest key="d" value={String(receipt.body_digest)} label="body digest" />
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

function AttemptCard({ a }: { a: Attempt }) {
  const s = attempt(a.outcome);
  const receipt = asObject(a.receipt);
  if (receipt?.kind === 'fhir') return <FhirAttemptCard a={a} receipt={receipt} />;
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

function VerificationCard({ v, fhir }: { v: Verification; fhir: boolean }) {
  const detail = asObject(v.detail);
  const verdict = detail?.verdict;
  const words = fhir || detail?.kind === 'fhir' ? fhirVerification : verification;
  return (
    <Stack gap={6}>
      <StatusBadge {...words(v.outcome)} w="fit-content" />
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
  /** Set on a case with no receipt: what it reads in place of a verification. */
  notChecked?: NotChecked | null;
  /** The case's evidence, for its route.kind. */
  snapshot?: Snapshot | null;
}

/** The writes Shutter sent: each attempt and what the receiver answered. */
export function DispatchPanel({
  caseId,
  open,
  write,
  planned,
  byHand,
  state,
  receiver,
  notChecked,
  snapshot,
}: Props) {
  const attempts = useAttempts(caseId, open);
  const list = (attempts.data ?? []).filter((x) => x.attempt);
  const fhir = writeKind(snapshot, attempts.data) === 'fhir_r4';
  return (
    <Section
      id="dispatch"
      title="Dispatch"
      note={
        notChecked
          ? `What Shutter itself sent to ${receiverNoun(receiver)}. A delivery by the engine is not a write of Shutter's.`
          : fhir
            ? `${FHIR_DISPATCH_NOTE}. An acknowledgement only says ${receiverNoun(receiver)} answered.`
            : `The conditional write, sent only after the release, a fresh read of the receiver and the gate at dispatch. An acknowledgement only says ${receiverNoun(receiver)} answered.`
      }
    >
      {attempts.isError ? <ErrorAlert error={attempts.error} title="The attempts could not be read" /> : null}
      {attempts.isSuccess && list.length === 0 ? (
        write && !byHand && !STOPPED_STATES.includes(state) && !notChecked ? (
          <NotYet>Nothing dispatched yet.</NotYet>
        ) : (
          <Text size="sm" c="dimmed">
            {planned || byHand || notChecked || STOPPED_STATES.includes(state)
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

/**
 * What the verifier found at the receiver after each write, or why there is nothing of Shutter's to verify; on a case
 * with no receipt, its outcome and that nobody checked the receiver.
 */
export function VerificationPanel({
  caseId,
  open,
  write,
  planned,
  byHand,
  state,
  notChecked,
  snapshot,
}: Props) {
  const attempts = useAttempts(caseId, open);
  const fhir = writeKind(snapshot, attempts.data) === 'fhir_r4';
  const list = (attempts.data ?? []).filter((x) => x.verification);
  const sent = (attempts.data ?? []).some((x) => x.attempt);
  // A case stopped with a write and no verification, as a write call that errored: nothing is coming to verify it
  const unverified =
    STOPPED_STATES.includes(state) &&
    (attempts.data ?? []).some((x) => WRITE_OUTCOMES.includes(String(x.attempt?.outcome)));
  if (notChecked)
    return (
      <Section id="verification" title={AT_THE_RECEIVER}>
        <NotCheckedWords outcome={notChecked.outcome} accepted={notChecked.accepted} />
      </Section>
    );
  return (
    <Section
      id="verification"
      title="Verification"
      note={
        fhir
          ? FHIR_VERIFIED_NOTE
          : "Verified means Shutter read the receiver's committed history and the receipt after the write and found the effect there."
      }
    >
      {attempts.isError ? <ErrorAlert error={attempts.error} title="The attempts could not be read" /> : null}
      {attempts.isSuccess && list.length === 0 ? (
        sent ? (
          <StatusBadge
            {...(fhir ? fhirVerification : verification)(unverified ? 'unresolved' : 'pending')}
            w="fit-content"
          />
        ) : (
          <NoWrite write={write} planned={planned} byHand={byHand} state={state} />
        )
      ) : null}
      {list.map((x, i) => (
        <Card key={i} padding="sm" withBorder>
          <VerificationCard v={x.verification!} fhir={fhir} />
        </Card>
      ))}
    </Section>
  );
}
