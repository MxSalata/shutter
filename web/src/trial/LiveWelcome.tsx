import { Anchor, Button, Group, Paper, Stack, Text } from '@mantine/core';
import { useId, useState } from 'react';
import { trialHref } from '@/env/mode';

/** Where the live first-run prompt keeps its dismissal, on this device. */
export const LIVE_WELCOME_KEY = 'shutter:live-welcome:v1';

const dismissed = () => {
  try {
    return window.localStorage.getItem(LIVE_WELCOME_KEY) !== null;
  } catch {
    return true;
  }
};

/**
 * The live app's first-run prompt, once per device after sign-in: it points to the trial, where the guide runs, so
 * a first look never happens on a hospital's live data. A card at the corner of the page, never over it: on the online
 * demo the page itself holds a case to approve, and the first thing a visitor sees must not hide it.
 */
export function LiveWelcome() {
  const [open, setOpen] = useState(() => !dismissed());
  const title = useId();
  const close = () => {
    try {
      window.localStorage.setItem(LIVE_WELCOME_KEY, new Date().toISOString());
    } catch {
      // Storage refused: the prompt closes for this visit only
    }
    setOpen(false);
  };
  if (!open) return null;
  return (
    <Paper
      role="dialog"
      aria-labelledby={title}
      className="live-welcome"
      withBorder
      shadow="md"
      p="md"
      radius="md"
    >
      <Stack gap="sm">
        <Text id={title} fw={700}>
          New here?
        </Text>
        <Text size="sm">
          Try Shutter in the trial environment first: a demo hospital with made-up patients, where each action
          replays a recording and nothing reaches this hospital&apos;s systems.
        </Text>
        <Group gap="sm">
          <Button component="a" href={trialHref('#/scenarios', { tour: true })} color="grape" onClick={close}>
            Take the guided tour
          </Button>
          <Anchor href={trialHref()} onClick={close} c="grape.8">
            Open the trial
          </Anchor>
          <Button variant="subtle" color="gray" onClick={close}>
            Not now
          </Button>
        </Group>
      </Stack>
    </Paper>
  );
}
