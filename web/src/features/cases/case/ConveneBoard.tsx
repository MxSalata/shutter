import { Button, Group, Modal, Stack, Text } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { resolveCan } from '@/api/can';
import { newIdempotencyKey } from '@/api/client';
import { useConveneBoard, useMe, useSettings } from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import { budgetSpent, budgetText } from '@/lib/budget';
import { describeError } from '@/lib/errors';

/** The states a reinvestigation reopens, and so the board may be convened on. */
const REOPENABLE: string[] = ['blocked', 'escalated', 'failed'];

/**
 * Convene the board on a case, live (CONTRACTS 5.3, v1.34): for those who may spend the day's model budget (a judge on
 * the public demo, a site's operator or approver). The case is investigated again on fresh evidence and the board
 * decides it whatever the site's policy says; its plan then meets the same gate, rehearsal and approval. It reopens a
 * case as a reinvestigation does, so it is offered on the same cases: blocked, escalated or failed. A case awaiting an
 * approval is approved or rejected first, and one still being investigated is left to finish.
 */
export function ConveneBoard({ c }: { c: CaseDetail }) {
  const can = resolveCan(useMe().data);
  const budget = useSettings().data?.budget;
  const convene = useConveneBoard(c.caseId);
  const [opened, setOpened] = useState(false);
  const [key, setKey] = useState('');
  if (!can.liveAgents || !REOPENABLE.includes(c.state)) return null;
  const words = budgetText(budget);
  const spent = budgetSpent(budget);
  const open = () => {
    setKey(newIdempotencyKey());
    convene.reset();
    setOpened(true);
  };
  const submit = () =>
    convene.mutate(
      { idempotencyKey: key },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'blue',
            title: 'The board is convening',
            message: 'Fresh evidence first, then the three specialists and the coordinator, live.',
          });
        },
      },
    );
  return (
    <>
      <Button variant="default" onClick={open}>
        Convene the board
      </Button>
      <Modal opened={opened} onClose={() => setOpened(false)} title={`Convene the board on ${c.caseId}`}>
        <Stack gap="sm">
          <Text size="sm">
            The case is investigated again on fresh evidence, and the board of specialists decides it live,
            whatever the site&apos;s policy says. Its plan meets the same gate, rehearsal and approval as any
            other; the earlier plan and approval stay as history.
          </Text>
          {words ? (
            <Stack gap={2}>
              <Text size="sm" c="dimmed">
                {words.today}
              </Text>
              {words.share ? (
                <Text size="sm" c="dimmed">
                  {words.share}
                </Text>
              ) : null}
            </Stack>
          ) : null}
          {convene.error ? (
            <Text size="sm" c="red">
              {describeError(convene.error)}
            </Text>
          ) : null}
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setOpened(false)}>
              Cancel
            </Button>
            <Button onClick={submit} loading={convene.isPending} disabled={spent}>
              Convene
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}
