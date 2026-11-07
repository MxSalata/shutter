import { Alert, List, Stack, Text } from '@mantine/core';
import type { CaseDetail } from '@/api/types';
import { KeyValueList } from '@/components/KeyValueList';
import { Section } from './Section';

const STATUS_WORDS: Record<string, Record<string, string>> = {
  completion: {
    DI: 'Dictated',
    DO: 'Documented',
    IP: 'In progress',
    IN: 'Incomplete',
    PA: 'Pre-authenticated',
    AU: 'Authenticated',
    LA: 'Legally authenticated',
  },
  confidentiality: { V: 'Very restricted', R: 'Restricted', U: 'Usual control' },
  availability: { AV: 'Available', CA: 'Cancelled', OB: 'Obsolete', UN: 'Unavailable' },
};

/** A status in words with its code beside it; a value the standard does not list stays as the message has it. */
function status(kind: string, code?: string): string {
  if (!code) return 'Not stated';
  const word = STATUS_WORDS[kind]?.[code];
  return word ? `${word} (${code})` : `${code}, not a value the standard lists`;
}

/**
 * A document case's own section (CONTRACTS 11.2): the document's identity, its parent, its patient, the delivery and what
 * the message store holds for its chain. Nothing of the document's content reaches this page, and a restricted document's
 * identity reaches only an authorised reviewer.
 */
export function DocumentPanel({ c }: { c: CaseDetail }) {
  const d = c.document;
  if (!d) return null;
  const refusal = d.refusal;
  const code = [refusal?.ack_code, refusal?.reason_code].filter(Boolean).join(', ');
  return (
    <Section
      id="document"
      title="Document"
      note="Metadata only. Shutter keeps no copy of the document: it stays in the source's message store, under that store's retention."
    >
      <Stack gap="sm">
        <Alert color={d.restricted ? 'orange' : 'blue'} variant="light" title={d.headline}>
          <Text size="sm">Shutter has sent nothing, and it resends no document.</Text>
        </Alert>
        {d.identity_withheld ? null : (
          <KeyValueList
            rows={[
              ['Document', d.document?.id || 'No usable document identifier'],
              ['Parent document', d.document?.parent],
              [
                'Patient identifiers',
                d.patient?.keys?.map((k) => [k.id, k.authority, k.type].filter(Boolean).join(' ')).join('; '),
              ],
              ['Completion', status('completion', d.document?.completion)],
              ['Confidentiality', status('confidentiality', d.document?.confidentiality)],
              ['Availability', status('availability', d.document?.availability)],
            ]}
          />
        )}
        <KeyValueList
          rows={[
            ['Trigger', d.trigger],
            ['At the operation', d.delivery?.status],
            [
              'Stored size',
              d.size?.stored_bytes ? `${d.size.stored_bytes.toLocaleString('en-GB')} bytes` : '',
            ],
            ['What the receiver answered', code],
            [
              'Its words',
              refusal?.text_withheld ? 'For an authorised reviewer' : refusal?.ack_code ? refusal?.text : '',
            ],
          ]}
        />
        {d.reasons?.length ? (
          <List size="sm" aria-label="Why a person needs to look">
            {d.reasons.map((r) => (
              <List.Item key={r.code}>{r.words}</List.Item>
            ))}
          </List>
        ) : null}
        {d.chain?.says?.length ? (
          <Stack gap={4}>
            <Text size="sm" fw={500}>
              What the message store holds for this document
            </Text>
            {d.chain.says.map((line) => (
              <Text size="sm" key={line}>
                {line}
              </Text>
            ))}
          </Stack>
        ) : null}
      </Stack>
    </Section>
  );
}
