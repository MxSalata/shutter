import { Accordion, Card, Stack, Text } from '@mantine/core';
import { useAttempts } from '@/api/hooks';
import type { Attempt, Verification } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { JsonBlock } from '@/components/JsonBlock';
import { KeyValueList } from '@/components/KeyValueList';
import { Digest } from '@/components/Digest';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { attempt, verification } from '@/lib/status';
import { asObject } from '@/lib/json';
import { NotYet, Section } from './Section';

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
 * What the section says before any attempt: a write still to come, no write of Shutter's to verify (a plan that
 * writes nothing, or a correction the team made by hand), or no plan yet.
 */
function Empty({ write, planned, byHand }: { write: boolean; planned: boolean; byHand: boolean }) {
  if (write) return <NotYet>Nothing dispatched yet.</NotYet>;
  if (byHand || planned)
    return (
      <Stack gap={4}>
        <StatusBadge {...verification(byHand ? 'by_hand' : 'not_applicable')} w="fit-content" />
        <Text size="sm" c="dimmed">
          {byHand
            ? 'The team corrected the systems by hand and a person closed the case; Shutter wrote nothing and did not check the correction.'
            : "The plan writes nothing to the receiver, so there is no write of Shutter's to verify."}
        </Text>
      </Stack>
    );
  return <NotYet>Nothing to verify yet: there is no plan.</NotYet>;
}

export function ExecutionPanel({
  caseId,
  open,
  write,
  planned,
  byHand,
}: {
  caseId: string;
  open: boolean;
  write: boolean;
  planned: boolean;
  byHand: boolean;
}) {
  const attempts = useAttempts(caseId, open);
  const list = attempts.data ?? [];
  return (
    <Section
      id="execution"
      title={write ? 'Dispatch and verification' : 'Verification'}
      note="An acknowledgement only says the downstream system answered. Verified means Shutter read its committed history and the receipt afterwards and found the effect there."
    >
      {attempts.isError ? <ErrorAlert error={attempts.error} title="The attempts could not be read" /> : null}
      {attempts.isSuccess && list.length === 0 ? (
        <Empty write={write} planned={planned} byHand={byHand} />
      ) : null}
      {list.map((x, i) => (
        <Card key={i} padding="sm" withBorder>
          <Stack gap="sm">
            {x.attempt ? <AttemptCard a={x.attempt} /> : null}
            {x.verification ? <VerificationCard v={x.verification} /> : null}
          </Stack>
        </Card>
      ))}
    </Section>
  );
}
