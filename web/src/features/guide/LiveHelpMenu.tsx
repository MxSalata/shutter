import { ActionIcon, Menu, Tooltip } from '@mantine/core';
import { IconHelp, IconPlayerPlay, IconTestPipe } from '@tabler/icons-react';
import { trialHref } from '@/env/mode';

/**
 * Help on a live page: the guide runs only in the trial, so both items open it, as real links (a new tab is one
 * middle-click away). It carries none of the guide's code, which only trial pages load.
 */
export function LiveHelpMenu() {
  return (
    <Menu shadow="md" width={260} position="bottom-end" withinPortal>
      <Menu.Target>
        <Tooltip label="Help">
          <ActionIcon variant="subtle" color="gray" size="lg" aria-label="Help">
            <IconHelp size={18} />
          </ActionIcon>
        </Tooltip>
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
