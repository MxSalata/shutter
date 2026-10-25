import { ActionIcon, Menu, Tooltip } from '@mantine/core';
import { IconHelp, IconList, IconPlayerPlay, IconRotate } from '@tabler/icons-react';
import { positionOf } from './controller';
import { useGuide } from './store';

/** Help in the header: resume the guide where it was left, start it again, or open one chapter. */
export function HelpMenu() {
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
        <Menu.Label>Guide</Menu.Label>
        {pos ? (
          <Menu.Item className="guide-control" leftSection={<IconPlayerPlay size={16} />} onClick={resume}>
            Resume guide
          </Menu.Item>
        ) : null}
        <Menu.Item
          className="guide-control"
          leftSection={started ? <IconRotate size={16} /> : <IconPlayerPlay size={16} />}
          // The welcome again, with its choice of scope; Start guide there begins from the first chapter
          onClick={openWelcome}
        >
          {started ? 'Restart guide' : 'Start guide'}
        </Menu.Item>
        <Menu.Item className="guide-control" leftSection={<IconList size={16} />} onClick={openChapters}>
          Choose a chapter
        </Menu.Item>
      </Menu.Dropdown>
    </Menu>
  );
}
