import { Button, Group, Stack, Text } from '@mantine/core';
import { IconPlugConnectedX } from '@tabler/icons-react';
import { useState } from 'react';
import { newIdempotencyKey } from '@/api/client';
import { useStartStorm } from '@/api/hooks';
import { ConfirmModal } from '@/components/ConfirmModal';
import { ErrorAlert } from '@/components/ErrorAlert';
import { StatusNotice } from '@/components/StatusBadge';
import type { Tone } from '@/lib/tone';
import { refusalWords, stormRefusal, type StormRefusal } from './view';
import './storm.css';

/** The button's words, and the confirm's title and its button (DESIGN.md 1.4: verb first, at most 4 words). */
export const BREAK_THE_FEED = 'Break the feed';

/** What a press does, said before it happens (the live voice: the consequence first, then what Shutter does). */
export const STORM_CONFIRM =
  "The demo hospital's bed manager goes down for a minute and eight movements for four new patients fail. Shutter groups them into one incident and puts them right, in order, when the bed manager is back. It takes a few minutes and spends little.";

/** "Break the feed" on the live hospital's banner: the button, its confirm, and the press with its own key. */
export function StormButton({ onRefused }: { onRefused: (refusal: StormRefusal | null) => void }) {
  const start = useStartStorm();
  const [opened, setOpened] = useState(false);
  // One key per press of the button: a confirm sent again after an error is the same press, so the server replays
  // its first answer instead of starting a second storm
  const [key, setKey] = useState('');
  const failure = start.error && !stormRefusal(start.error) ? start.error : null;
  const open = () => {
    start.reset();
    setKey(newIdempotencyKey());
    setOpened(true);
  };
  const close = () => setOpened(false);
  const confirm = () => {
    onRefused(null);
    start.mutate(key, {
      onSuccess: close,
      onError: (e) => {
        const refusal = stormRefusal(e);
        if (!refusal) return;
        onRefused(refusal);
        close();
      },
    });
  };
  return (
    <>
      <Button
        variant="default"
        size="xs"
        leftSection={<IconPlugConnectedX size={14} aria-hidden />}
        onClick={open}
        style={{ flex: 'none' }}
      >
        {BREAK_THE_FEED}
      </Button>
      <ConfirmModal opened={opened} onClose={close} title={BREAK_THE_FEED} centered>
        <Stack gap="md">
          <Text size="sm">{STORM_CONFIRM}</Text>
          {failure ? <ErrorAlert error={failure} title="The storm could not be asked for" /> : null}
          <Group justify="flex-end" gap="sm">
            <Button variant="default" onClick={close}>
              Cancel
            </Button>
            <Button onClick={confirm} loading={start.isPending}>
              {BREAK_THE_FEED}
            </Button>
          </Group>
        </Stack>
      </ConfirmModal>
    </>
  );
}

const REFUSAL_TONES: Record<StormRefusal['code'], Tone> = {
  live_off: 'neutral',
  storm_in_progress: 'info',
  cooldown: 'neutral',
  no_service: 'neutral',
};

/** A refusal, under the banner's line: a calm notice in one sentence, said once to a screen reader, closable. */
export function StormNotice({ refusal, onClose }: { refusal: StormRefusal; onClose: () => void }) {
  return (
    <StatusNotice
      tone={REFUSAL_TONES[refusal.code]}
      role="status"
      onClose={onClose}
      closeLabel="Dismiss"
      className="storm-notice"
    >
      <Text size="sm" data-testid="storm-notice">
        {refusalWords(refusal)}
      </Text>
    </StatusNotice>
  );
}
