import { Group, Text } from '@mantine/core';
import type { CaseDetail } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { KeyValueList } from '@/components/KeyValueList';
import { Timestamp } from '@/components/Timestamp';
import { humanize } from '@/lib/format';
import { useTechnical } from '@/stores/appearance';
import { failureKindInWords } from './derive';
import { receiverNoun } from './receiver';
import { Section } from './Section';

const kinds = (receiver: string): Record<string, string> => ({
  delivery_failed: `Not delivered: ${receiver} did not accept it`,
  uncertain_outcome: `Outcome unknown: ${receiver} may or may not have applied it`,
  rejected: `Refused by ${receiver}`,
  unmappable: 'Could not be mapped to a downstream operation',
  unreadable: `Held: IRIS could not read it, since its HL7 schema is not loaded here, so nothing was sent to ${receiver}`,
  withheld:
    'Withheld: never sent (a merge the site keeps for the PAS team, or a cancellation the receiver cannot reverse)',
});

/**
 * What failed, as the production recorded it. The receiver's answer stays in its own words; in Technical its HTTP
 * status and reason code sit beside them as codes. The message id and the operation key are codes, wrapping rather
 * than cut, and the event time carries its date (and UTC in Technical).
 */
export function FailurePanel({ c }: { c: CaseDetail }) {
  const technical = useTechnical();
  const noun = receiverNoun(c.receiver);
  const codes =
    technical && (c.failureHttpStatus || c.failureReasonCode) ? (
      <Group gap={4} wrap="wrap">
        {c.failureHttpStatus ? <CodeChip>{`HTTP ${c.failureHttpStatus}`}</CodeChip> : null}
        {c.failureReasonCode ? <CodeChip>{c.failureReasonCode}</CodeChip> : null}
      </Group>
    ) : null;
  return (
    <Section
      id="failure"
      title="What failed"
      note="The production's own record of the delivery that failed. The operation key names the business operation, not the message: a resend keeps it."
    >
      <KeyValueList
        rows={[
          ['Failure', kinds(noun)[failureKindInWords(c)] ?? humanize(c.failureKind)],
          [
            `What ${noun} answered`,
            c.failureText || codes ? (
              <Group gap={6} wrap="wrap">
                {c.failureText ? (
                  <Text size="sm" className="mono-wrap">
                    {c.failureText}
                  </Text>
                ) : null}
                {codes}
              </Group>
            ) : (
              ''
            ),
          ],
          ['Operation', `${humanize(c.event)}${c.ward ? ` to ${c.ward}` : ''}`],
          ['Event time', <Timestamp key="t" iso={c.eventTime} />],
          ['Encounter', c.encounterId],
          ['Patient', c.patientId ? `${c.patientId} (${c.patientIdAuthority})` : ''],
          [
            'Sent by',
            c.sourceSystem ? (
              <Text key="s" size="sm">
                {`${c.sourceSystem}, message `}
                <CodeChip>{c.sourceMessageId}</CodeChip>
              </Text>
            ) : (
              ''
            ),
          ],
          ['Operation key', c.operationKey ? <CodeChip key="k">{c.operationKey}</CodeChip> : ''],
        ]}
      />
    </Section>
  );
}
