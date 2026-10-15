import { Accordion, Badge, Card, Stack, Text, Tooltip } from '@mantine/core';
import { useAttempts } from '@/api/hooks';
import type { Attempt, Verification } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { JsonBlock } from '@/components/JsonBlock';
import { KeyValueList } from '@/components/KeyValueList';
import { Digest } from '@/components/Digest';
import { Timestamp } from '@/components/Timestamp';
import { asObject } from '@/lib/json';
import { NotYet, Section } from './Section';

/** What the ward answered. An acknowledgement is never called verified: only the verifier's read says that. */
const ATTEMPT: Record<string, { colour: string; label: string; hint: string }> = {
  applied: {
    colour: 'blue',
    label: 'Acknowledged',
    hint: 'The ward answered 201; verification reads what it committed',
  },
  already_committed: {
    colour: 'blue',
    label: 'Already committed',
    hint: 'The ward had committed this operation before',
  },
  uncertain: {
    colour: 'orange',
    label: 'No answer: outcome unknown',
    hint: 'The write may or may not have been committed; reconciled by its key',
  },
  version_conflict: {
    colour: 'red',
    label: 'Refused: the receiver changed',
    hint: 'The expected version no longer matched; nothing was written',
  },
  refused: { colour: 'red', label: 'Refused', hint: 'The ward refused the write' },
  error: { colour: 'red', label: 'Error', hint: 'The write could not be sent' },
};

const VERIFIED: Record<string, { colour: string; label: string }> = {
  verified: { colour: 'green', label: 'Verified at the receiver' },
  unresolved: { colour: 'orange', label: 'Not established' },
  failed: { colour: 'red', label: 'Not committed' },
};

function AttemptCard({ a }: { a: Attempt }) {
  const s = ATTEMPT[a.outcome] ?? { colour: 'gray', label: a.outcome, hint: '' };
  const receipt = asObject(a.receipt);
  return (
    <Stack gap={6}>
      <Tooltip label={s.hint} disabled={!s.hint} multiline maw={320}>
        <Badge color={s.colour} style={{ textTransform: 'none' }} tabIndex={0} w="fit-content">
          {s.label} {a.httpStatus ? `(HTTP ${a.httpStatus})` : ''}
        </Badge>
      </Tooltip>
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
  const s = VERIFIED[v.outcome] ?? { colour: 'gray', label: v.outcome };
  return (
    <Stack gap={6}>
      <Badge color={s.colour} style={{ textTransform: 'none' }} w="fit-content">
        {s.label}
      </Badge>
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

export function ExecutionPanel({ caseId, open, write }: { caseId: string; open: boolean; write: boolean }) {
  const attempts = useAttempts(caseId, open);
  const list = attempts.data ?? [];
  return (
    <Section
      id="execution"
      title={write ? 'Dispatch and verification' : 'Verification'}
      note="An acknowledgement only says the ward answered. Verified means Interlock read the ward's committed history and the receipt afterwards and found the effect there."
    >
      {attempts.isError ? <ErrorAlert error={attempts.error} title="The attempts could not be read" /> : null}
      {attempts.isSuccess && list.length === 0 ? (
        <NotYet>{write ? 'Nothing dispatched yet.' : 'Not verified yet.'}</NotYet>
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
