import { Menu } from '@mantine/core';
import { IconPlayerPlay, IconTestPipe } from '@tabler/icons-react';
import { HeaderHelpButton } from '@/components/HeaderHelpButton';
import { trialHref } from '@/env/mode';

/**
 * Help on a live page: the guide runs only in the trial, so both items open it, as real links (a new tab is one
 * middle-click away). It carries none of the guide's code, which only trial pages load.
 */
export function LiveHelpMenu() {
  return (
    <Menu shadow="md" width={260} position="bottom-end" withinPortal>
      <Menu.Target>
        <HeaderHelpButton label="Help" />
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Label>The trial environment</Menu.Label>
        <Menu.Item
          component="a"
          href={trialHref('#/scenarios', { tour: true })}
          className="guide-control"
          leftSection={<IconPlayerPlay size={16} aria-hidden />}
        >
          Take the guided tour (opens the trial)
        </Menu.Item>
        <Menu.Item
          component="a"
          href={trialHref()}
          className="guide-control"
          leftSection={<IconTestPipe size={16} aria-hidden />}
        >
          Open the trial environment
        </Menu.Item>
      </Menu.Dropdown>
    </Menu>
  );
}
