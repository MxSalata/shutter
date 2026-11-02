import { Button, Group, Paper, Stack, Text, Title, VisuallyHidden } from '@mantine/core';
import { IconTestPipe } from '@tabler/icons-react';
import { useId } from 'react';
import { trialHref } from '@/env/mode';

/**
 * The way into the trial from the live sign-in page: a card of its own under the form, in the trial's colour (a grape
 * top edge and icon, the only grape on a live page), with two real links, so they also open in a new tab. It says what
 * the trial is in one breath: made-up patients, each action replays a recording, nothing reaches IRIS. No password:
 * the trial opens signed in.
 */
export function TrialCard() {
  const heading = useId();
  return (
    <Paper
      component="section"
      aria-labelledby={heading}
      withBorder
      radius="md"
      p="md"
      shadow="xs"
      style={{ borderTop: '4px solid var(--shutter-trial-accent)' }}
    >
      <Stack gap="xs">
        <Group gap="xs" wrap="nowrap" align="center">
          <IconTestPipe
            size={20}
            aria-hidden
            style={{ color: 'var(--shutter-trial-accent)', flex: 'none' }}
          />
          <Title order={2} size="h3" id={heading}>
            New to Shutter?
          </Title>
        </Group>
        <Text size="sm">
          Try it in the trial environment: a demo hospital with made-up patients, where each action replays a
          recording. Nothing reaches IRIS.
        </Text>
        <Group gap="xs" mt={4}>
          <Button component="a" href={trialHref('#/scenarios', { tour: true })} color="grape" mih={44}>
            Take the guided tour
            <VisuallyHidden> of the trial</VisuallyHidden>
          </Button>
          <Button component="a" href={trialHref()} variant="default" mih={44}>
            Open the trial
          </Button>
        </Group>
      </Stack>
    </Paper>
  );
}
