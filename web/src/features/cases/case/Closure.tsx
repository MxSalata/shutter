import { Button, Group, List, Modal, Stack, Text, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { newIdempotencyKey } from '@/api/client';
import { useClosure, useMe, useReinvestigate } from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import { TRIAL } from '@/env/mode';
import { describeError } from '@/lib/errors';
import { KeyValueList } from '@/components/KeyValueList';
import { Timestamp } from '@/components/Timestamp';
import { asArray } from '@/lib/json';
import { humanize } from '@/lib/format';
import { Section } from './Section';

const text = (x: unknown) => (typeof x === 'string' ? x : JSON.stringify(x));

/**
 * Reopens a case that stopped (blocked, escalated or failed) once its cause may have changed: the case collects fresh
 * evidence and gets a new plan version, and the earlier plan and approval stay as history. For operators; the
 * recorded demo can't start new work, so it doesn't offer it.
 */
export function Reinvestigate({ c }: { c: CaseDetail }) {
  const me = useMe().data;
  const reopen = useReinvestigate(c.caseId);
  const [opened, setOpened] = useState(false);
  const [reason, setReason] = useState('');
  const [key, setKey] = useState('');
  if (TRIAL || !me?.operator) return null;
  const open = () => {
    setReason('');
    setKey(newIdempotencyKey());
    reopen.reset();
    setOpened(true);
  };
  const submit = () =>
    reopen.mutate(
      { reason: reason.trim(), idempotencyKey: key },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'blue',
            title: 'Reopened',
            message: 'Fresh evidence is being collected and the case is investigated again.',
          });
        },
      },
    );
  return (
    <>
      <Group gap="sm" wrap="wrap">
        <Button variant="default" onClick={open}>
          Reinvestigate
        </Button>
        <Text size="xs" c="dimmed">
          Reopens the case with fresh evidence and a new plan version; the earlier plan and approval stay as
          history.
        </Text>
      </Group>
      <Modal opened={opened} onClose={() => setOpened(false)} title={`Reinvestigate ${c.caseId}`}>
        <Stack gap="sm">
          <Textarea
            label="Why look again"
            description="Recorded on the case with your name"
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
            autosize
            minRows={2}
            data-autofocus
          />
          {reopen.error ? (
            <Text size="sm" c="red">
              {describeError(reopen.error)}
            </Text>
          ) : null}
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setOpened(false)}>
              Cancel
            </Button>
            <Button onClick={submit} loading={reopen.isPending} disabled={!reason.trim()}>
              Reopen the case
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}

/**
 * The closing record: how the case closed, who and what took part, and what was and was not verified at the receiver.
 * The reason a stopped case waits, and what comes next, are at the top of the page.
 */
export function ClosureRecord({ c }: { c: CaseDetail }) {
  const closed = ['resolved', 'blocked', 'escalated', 'failed'].includes(c.state);
  const closure = useClosure(c.caseId, closed);
  const cl = closure.data;
  if (!closed || !cl) return null;
  return (
    <Section id="closure" title="The closing record">
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
    </Section>
  );
}
