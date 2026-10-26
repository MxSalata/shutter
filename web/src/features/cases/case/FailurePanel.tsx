import { Text } from '@mantine/core';
import type { CaseDetail } from '@/api/types';
import { KeyValueList } from '@/components/KeyValueList';
import { Digest } from '@/components/Digest';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { receiverNoun } from './receiver';
import { Section } from './Section';

const kinds = (receiver: string): Record<string, string> => ({
  delivery_failed: `Not delivered: ${receiver} did not accept it`,
  uncertain_outcome: `Outcome unknown: ${receiver} may or may not have applied it`,
  rejected: `Refused by ${receiver}`,
  unmappable: 'Could not be mapped to a downstream operation',
  withheld:
    'Withheld: never sent (a merge the site keeps for the PAS team, or a cancellation the receiver cannot reverse)',
});

export function FailurePanel({ c }: { c: CaseDetail }) {
  return (
    <Section
      id="failure"
      title="What failed"
      note="The production's own record of the delivery that failed. The operation key names the business operation, not the message: a resend keeps it."
    >
      <KeyValueList
        rows={[
          ['Failure', kinds(receiverNoun(c.receiver))[c.failureKind] ?? humanize(c.failureKind)],
          [
            `What ${receiverNoun(c.receiver)} answered`,
            c.failureText ? (
              <Text size="sm" className="mono-wrap">
                {c.failureText}
              </Text>
            ) : (
              ''
            ),
          ],
          ['Operation', `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`],
          ['Event time', <Timestamp key="t" iso={c.eventTime} />],
          ['Encounter', c.encounterId],
          ['Patient', c.patientId ? `${c.patientId} (${c.patientIdAuthority})` : ''],
          ['Sent by', c.sourceSystem ? `${c.sourceSystem}, message ${c.sourceMessageId}` : ''],
          ['Operation key', <Digest key="k" value={c.operationKey} label="operation key" length={80} />],
        ]}
      />
    </Section>
  );
}
