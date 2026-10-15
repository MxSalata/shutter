import { Alert, List, Stack, Text } from '@mantine/core';
import { useBlockedReason, useClosure } from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import { KeyValueList } from '@/components/KeyValueList';
import { Timestamp } from '@/components/Timestamp';
import { asArray } from '@/lib/json';
import { humanize } from '@/lib/format';
import { Section } from './Section';

const TITLES: Record<string, string> = {
  resolved: 'Closed: verified',
  blocked: 'Closed: blocked',
  escalated: 'Closed: handed to a person',
  failed: 'Closed: the workflow failed',
};

const text = (x: unknown) => (typeof x === 'string' ? x : JSON.stringify(x));

/** The closing record (the closure receipt) and, for a blocked or escalated case, what it waits for. */
export function OutcomePanel({ c }: { c: CaseDetail }) {
  const closed = ['resolved', 'blocked', 'escalated', 'failed'].includes(c.state);
  const stopped = c.state === 'blocked' || c.state === 'escalated';
  const closure = useClosure(c.caseId, closed);
  const reason = useBlockedReason(c.caseId, stopped);
  if (!closed) return null;
  const cl = closure.data;
  const r = reason.data;
  return (
    <Section id="outcome" title={TITLES[c.state] ?? humanize(c.state)} note={c.outcome || undefined}>
      {r ? (
        <Alert color={c.state === 'blocked' ? 'red' : 'orange'} variant="light" title={r.title || r.code}>
          <Stack gap="xs">
            {r.text ? <Text size="sm">{r.text}</Text> : null}
            <KeyValueList
              rows={[
                ['Reason code', r.code],
                ['Missing', r.prerequisite],
                ['Next action', r.nextAction],
                ['Whose', r.owner],
                ['Look again when', r.reevaluateWhen],
              ]}
            />
            {r.checks?.length ? (
              <List size="sm" spacing={2}>
                {r.checks.map((ch) => (
                  <List.Item key={ch.check}>
                    {humanize(ch.check)}: {ch.reason_code}, {ch.detail}
                  </List.Item>
                ))}
              </List>
            ) : null}
          </Stack>
        </Alert>
      ) : null}
      {cl ? (
        <Stack gap="xs">
          <KeyValueList
            rows={[
              ['Disposition', humanize(cl.disposition)],
              ['Outcome', cl.outcome],
              ['Gate policy', cl.policyVersion],
              ['Closed', <Timestamp key="c" iso={cl.closedAt} />],
              ['People and systems', asArray(cl.actors).map(text).join(', ')],
            ]}
          />
          <Text size="xs" fw={600} c="dimmed">
            Verified at the receiver
          </Text>
          {asArray(cl.verifiedEffects).length ? (
            <List size="sm" spacing={2}>
              {asArray(cl.verifiedEffects).map((x, i) => (
                <List.Item key={i}>{text(x)}</List.Item>
              ))}
            </List>
          ) : (
            <Text size="sm" c="dimmed">
              Nothing.
            </Text>
          )}
          <Text size="xs" fw={600} c="dimmed">
            Not verified
          </Text>
          {asArray(cl.unverified).length ? (
            <List size="sm" spacing={2}>
              {asArray(cl.unverified).map((x, i) => (
                <List.Item key={i}>{text(x)}</List.Item>
              ))}
            </List>
          ) : (
            <Text size="sm" c="dimmed">
              Nothing left unverified.
            </Text>
          )}
        </Stack>
      ) : null}
    </Section>
  );
}
