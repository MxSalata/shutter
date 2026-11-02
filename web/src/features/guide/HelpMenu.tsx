import { ActionIcon, Menu, Tooltip } from '@mantine/core';
import { IconHelp, IconList, IconPlayerPlay, IconRotate } from '@tabler/icons-react';
import { ENV } from '@/env/mode';
import { LeaveTrialItem } from '@/trial/LeaveTrial';
import { positionOf } from './controller';
import { useGuide } from './store';

/** Help in a trial page's header: resume the tour where it was left, start it again, open one chapter, or leave. */
export function TrialHelpMenu() {
  const progress = useGuide((s) => s.progress);
  const resume = useGuide((s) => s.resume);
  const openWelcome = useGuide((s) => s.openWelcome);
  const openChapters = useGuide((s) => s.openChapters);
  const pos = positionOf(progress);
  const started = !!pos || progress.completed.length > 0 || progress.dismissed;
  return (
    <Menu shadow="md" width={220} position="bottom-end" withinPortal>
      <Menu.Target>
        <Tooltip label="Help">
          <ActionIcon variant="subtle" color="gray" size="lg" aria-label="Help">
            <IconHelp size={18} />
          </ActionIcon>
        </Tooltip>
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Label>The tour</Menu.Label>
        {pos ? (
          <Menu.Item className="guide-control" leftSection={<IconPlayerPlay size={16} />} onClick={resume}>
            Resume the tour
          </Menu.Item>
        ) : null}
        <Menu.Item
          className="guide-control"
          leftSection={started ? <IconRotate size={16} /> : <IconPlayerPlay size={16} />}
          // The welcome again, with its choice of tours; Start the tour there begins from the first step
          onClick={openWelcome}
        >
          {started ? 'Restart the tour' : 'Start the tour'}
        </Menu.Item>
        <Menu.Item className="guide-control" leftSection={<IconList size={16} />} onClick={openChapters}>
          Choose a chapter
        </Menu.Item>
        {ENV.canLeave ? (
          <>
            <Menu.Divider />
            <LeaveTrialItem />
          </>
        ) : null}
      </Menu.Dropdown>
    </Menu>
  );
}
