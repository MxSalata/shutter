import { Button, Group, Menu, Modal, Stack, Text } from '@mantine/core';
import { IconDoorExit } from '@tabler/icons-react';
import { leaveTrial, useLeaveTrial } from './leave';
import { TRIAL_ONLY_WORDS } from './words';

/** The id of the trial-only line, which the menu holding it names as its description. */
export const TRIAL_ONLY_ID = 'trial-only-note';

/**
 * "Leave the trial?", then the live app at the same address: it asks who is signed in with the person's own session,
 * which the trial never used, and says "You are back in the live system" (BackFromTrial).
 */
export function LeaveTrialConfirm() {
  const asking = useLeaveTrial((s) => s.asking);
  const stay = useLeaveTrial((s) => s.stay);
  return (
    <Modal opened={asking} onClose={stay} title="Leave the trial?" centered>
      <Stack gap="md">
        <Text>What you did here is discarded. Nothing was sent to a hospital system or IRIS.</Text>
        <Group justify="flex-end" gap="sm">
          <Button variant="default" onClick={stay}>
            Stay in the trial
          </Button>
          <Button color="grape" leftSection={<IconDoorExit size={16} aria-hidden />} onClick={leaveTrial}>
            Leave trial
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

/** The banner's "Leave trial". */
export function LeaveTrialButton() {
  const ask = useLeaveTrial((s) => s.ask);
  return (
    <Button variant="subtle" color="grape" size="compact-sm" onClick={ask} className="trial-banner-control">
      Leave trial
    </Button>
  );
}

/** "Leave trial" as a menu item (the user menu, Help). */
export function LeaveTrialItem() {
  const ask = useLeaveTrial((s) => s.ask);
  return (
    <Menu.Item leftSection={<IconDoorExit size={16} aria-hidden />} onClick={ask}>
      Leave trial
    </Menu.Item>
  );
}

/**
 * In place of Leave trial where there is no live system to leave for (the demo build): one plain line, in the menu
 * where a person looks for Leave trial. It is the menu's description (`aria-describedby` on its dropdown), since a
 * menu's arrow keys move between its items only. `id` tells two menus' lines apart.
 */
export function TrialOnlyNote({ id = TRIAL_ONLY_ID }: { id?: string }) {
  return (
    <Text id={id} size="xs" c="dimmed" px="sm" py={6} maw={260} data-testid="trial-only-note">
      {TRIAL_ONLY_WORDS}
    </Text>
  );
}
