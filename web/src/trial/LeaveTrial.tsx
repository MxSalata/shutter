import { Button, Group, Menu, Modal, Stack, Text } from '@mantine/core';
import { IconDoorExit } from '@tabler/icons-react';
import { leaveTrial, useLeaveTrial } from './leave';

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
