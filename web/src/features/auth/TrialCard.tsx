import { Badge, Button, Group, Paper, Stack, Text, Title, VisuallyHidden } from '@mantine/core';
import { IconLockOpen, IconTestPipe } from '@tabler/icons-react';
import { useId } from 'react';
import { trialHref } from '@/env/mode';
import { HOSPITAL_NAME } from '@/lib/hospital';

/**
 * The way into the trial from the live sign-in page: a card of its own under the form, in the trial's colour (a grape
 * top edge and icon, the only grape on a live page), with two real links, so they also open in a new tab. It says what
 * the trial is in one breath, and in no more words than before: made-up patients, each action replays a recording, so
 * there is no new inference and nothing reaches IRIS. No password:
 * the trial opens signed in, and the card says so in a badge beside its title ("No sign-in required").
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
        <Group gap="xs" wrap="wrap" align="center">
          <IconTestPipe
            size={20}
            aria-hidden
            style={{ color: 'var(--shutter-trial-accent)', flex: 'none' }}
          />
          <Title order={2} size="h3" id={heading}>
            New to Shutter?
          </Title>
          <Badge color="grape" variant="light" leftSection={<IconLockOpen size={12} aria-hidden />}>
            No sign-in required
          </Badge>
        </Group>
        <Text size="sm">
          Try the trial: {HOSPITAL_NAME}, with made-up patients. Each action replays a recording: no new
          inference, and nothing reaches IRIS.
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
