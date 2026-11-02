import {
  ActionIcon,
  Box,
  Button,
  Drawer,
  Group,
  List,
  Popover,
  Stack,
  Text,
  Title,
  Tooltip,
} from '@mantine/core';
import { useDisclosure, useMediaQuery } from '@mantine/hooks';
import { IconInfoCircle, IconTestPipe } from '@tabler/icons-react';
import { useSyncExternalStore, type ReactNode } from 'react';
import { TechDetail } from '@/components/TechDetail';
import { ENV } from '@/env/mode';
import { journal } from './journal';
import { journalLine, TRIAL_WORDS, TRIAL_WORDS_SHORT } from './words';
import { LeaveTrialButton } from './LeaveTrial';
import { bannerForm } from './visit';

const WORKS = [
  'Approve or reject a plan',
  'Run a scenario',
  'Save the site profile',
  'Draft and send an escalation',
  'Start a production review',
  'Ask a suggested question',
  'Switch role',
];
const NOT_HERE = [
  'A real model: Convene the board, Reinvestigate',
  'Questions in your own words',
  'Abandoning a case',
];

/** "20 Oct 2026, 17:55 UTC", for the recording's date. */
function recordedOn(iso: string): string {
  const d = new Date(iso);
  if (Number.isNaN(d.getTime())) return iso;
  const day = d.toLocaleDateString('en-GB', {
    day: 'numeric',
    month: 'short',
    year: 'numeric',
    timeZone: 'UTC',
  });
  const time = d.toLocaleTimeString('en-GB', { hour: '2-digit', minute: '2-digit', timeZone: 'UTC' });
  return `${day}, ${time} UTC`;
}

function useJournal() {
  const counts = useSyncExternalStore(journal.subscribe, journal.counts);
  const recording = useSyncExternalStore(journal.subscribe, journal.recording);
  return { counts, recording };
}

/** What "What's different?" holds, in DESIGN.md 7.1's order. */
export function TrialDifferences() {
  const { counts, recording } = useJournal();
  return (
    <Stack gap="xs" maw={420}>
      <Text size="sm">{TRIAL_WORDS}</Text>
      <div>
        <Title order={3} fz="sm">
          Works here (replayed)
        </Title>
        <List size="sm" spacing={2}>
          {WORKS.map((w) => (
            <List.Item key={w}>{w}</List.Item>
          ))}
        </List>
      </div>
      <div>
        <Title order={3} fz="sm">
          Not in the trial
        </Title>
        <List size="sm" spacing={2}>
          {NOT_HERE.map((w) => (
            <List.Item key={w}>{w}</List.Item>
          ))}
        </List>
      </div>
      <Text size="sm">Resets when you reload or leave.</Text>
      <Text size="sm" data-testid="trial-journal">
        {journalLine(counts)}
      </Text>
      {recording ? (
        <Text size="sm">Recorded from Shutter&apos;s REST API on {recordedOn(recording.at)}.</Text>
      ) : null}
      <TechDetail kind="data" label="How the trial is kept apart">
        <Stack gap={4}>
          <Text size="sm">
            Every call is answered in this browser by the recorded mock; the app has no route to the network
            here.
          </Text>
          <Text size="sm">A guard refuses any request to /api/shutter.</Text>
          <Text size="sm">
            The page&apos;s Content-Security-Policy is connect-src &apos;none&apos;, so the browser itself
            refuses every network call.
          </Text>
          <Text size="sm">
            Check it yourself: the Network panel shows no /api/shutter request, and
            fetch(&apos;/api/shutter/me&apos;) in the console is refused.
          </Text>
          {recording ? (
            <Text size="xs" c="dimmed">
              {recording.source}
            </Text>
          ) : null}
        </Stack>
      </TechDetail>
    </Stack>
  );
}

/** "What's different?": a popover beside the banner, a sheet on a phone. */
function WhatsDifferent({ iconOnly }: { iconOnly: boolean }) {
  const phone = useMediaQuery('(max-width: 47.99em)', false);
  const [opened, { toggle, close }] = useDisclosure(false);
  const target: ReactNode = iconOnly ? (
    <Tooltip label="What's different?">
      <ActionIcon
        variant="subtle"
        color="grape"
        size="md"
        aria-label="What's different?"
        onClick={toggle}
        className="trial-banner-control"
      >
        <IconInfoCircle size={18} aria-hidden />
      </ActionIcon>
    </Tooltip>
  ) : (
    <Button
      variant="subtle"
      color="grape"
      size="compact-sm"
      onClick={toggle}
      className="trial-banner-control"
    >
      What&apos;s different?
    </Button>
  );
  if (phone)
    return (
      <>
        {target}
        <Drawer opened={opened} onClose={close} position="bottom" title="The trial environment" padding="md">
          <TrialDifferences />
        </Drawer>
      </>
    );
  return (
    <Popover
      opened={opened}
      onChange={(o) => (o ? undefined : close())}
      position="bottom-end"
      withinPortal
      shadow="md"
    >
      <Popover.Target>{target}</Popover.Target>
      <Popover.Dropdown aria-label="The trial environment">
        <TrialDifferences />
      </Popover.Dropdown>
    </Popover>
  );
}

/**
 * The trial's banner, above the header's row on every trial page, so it cannot scroll away: "Trial environment",
 * whose data it is and that nothing leaves, "What's different?" and "Leave trial" (not on the demo build, which has no
 * live system to go to). Full on the tab's first trial page, one line once the guide's welcome has closed; one line
 * on a phone, where "Leave trial" is in the user menu. A region, not a live region.
 */
export function TrialBanner() {
  const form = useSyncExternalStore(bannerForm.subscribe, bannerForm.get);
  const compact = form === 'compact';
  const phone = useMediaQuery('(max-width: 47.99em)', false);
  return (
    <Box
      role="region"
      aria-label="Trial environment"
      className="trial-banner"
      data-compact={compact || undefined}
      data-testid="trial-banner"
    >
      <Group gap="sm" justify="space-between" wrap="nowrap" h="100%">
        <Group gap={8} wrap="nowrap" style={{ minWidth: 0 }}>
          <IconTestPipe size={18} aria-hidden style={{ flex: 'none' }} />
          <Text fw={700} size="sm" style={{ flex: 'none' }}>
            Trial environment
          </Text>
          <Text size="sm" className="trial-banner-words" visibleFrom="sm">
            {compact ? (
              `· ${TRIAL_WORDS_SHORT}`
            ) : (
              <>
                <span className="trial-banner-long">{TRIAL_WORDS}</span>
                <span className="trial-banner-short">{TRIAL_WORDS_SHORT}</span>
              </>
            )}
          </Text>
        </Group>
        <Group gap={4} wrap="nowrap" style={{ flex: 'none' }}>
          <WhatsDifferent iconOnly={compact || phone} />
          {ENV.canLeave ? (
            <Box visibleFrom="sm">
              <LeaveTrialButton />
            </Box>
          ) : null}
        </Group>
      </Group>
    </Box>
  );
}
