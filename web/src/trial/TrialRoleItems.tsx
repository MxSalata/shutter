import { Menu } from '@mantine/core';
import { IconCheck, IconUserCircle } from '@tabler/icons-react';
import { useQueryClient } from '@tanstack/react-query';
import { useMe, useSignIn } from '@/api/hooks';
import { rememberTrialRole, trialUser } from '@/env/mode';
import { TRIAL_ROLES } from './roles';

/**
 * "Switch trial role" in the user menu of a trial page: each role signs the trial's own user of that name in at
 * once, so a judge can see what each role may do without leaving; the tab keeps the choice for its reloads.
 */
export function TrialRoleItems() {
  const me = useMe().data;
  const signIn = useSignIn();
  const client = useQueryClient();
  return (
    <>
      <Menu.Label>Switch trial role</Menu.Label>
      {TRIAL_ROLES.map((r) => {
        const current = me?.username === r.role;
        return (
          <Menu.Item
            key={r.role}
            leftSection={
              current ? <IconCheck size={16} aria-hidden /> : <IconUserCircle size={16} aria-hidden />
            }
            aria-label={`${r.name}${current ? ' (current trial role)' : ''}`}
            // Marked, not disabled: with the approver current, every item before Sign out was disabled and the arrow
            // keys found nothing to move to. Pressing it just closes the menu.
            aria-current={current ? 'true' : undefined}
            onClick={() => {
              if (current) return;
              signIn.mutate(trialUser(r.role), {
                onSuccess: async () => {
                  rememberTrialRole(r.role);
                  // What each page may show depends on the role: read everything again as the new one
                  await client.invalidateQueries();
                },
              });
            }}
          >
            {r.name}
          </Menu.Item>
        );
      })}
    </>
  );
}
