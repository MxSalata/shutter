import { Anchor, Button, Group, Modal, Stack, Text } from '@mantine/core';
import { useState } from 'react';
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
 * a first look never happens on a hospital's live data.
 */
export function LiveWelcome() {
  const [open, setOpen] = useState(() => !dismissed());
  const close = () => {
    try {
      window.localStorage.setItem(LIVE_WELCOME_KEY, new Date().toISOString());
    } catch {
      // Storage refused: the prompt closes for this visit only
    }
    setOpen(false);
  };
  return (
    <Modal opened={open} onClose={close} title="New here?" centered transitionProps={{ exitDuration: 0 }}>
      <Stack gap="md">
        <Text>
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
    </Modal>
  );
}
