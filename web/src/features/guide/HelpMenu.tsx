import { Menu } from '@mantine/core';
import { IconList, IconPlayerPlay, IconRotate } from '@tabler/icons-react';
import { HeaderHelpButton } from '@/components/HeaderHelpButton';
import { ENV } from '@/env/mode';
import { LeaveTrialItem, TRIAL_ONLY_ID, TrialOnlyNote } from '@/trial/LeaveTrial';
import { positionOf } from './controller';
import { useMenuHandOver } from './reveal';
import { useGuide } from './store';

/** The button's word in the trial: "Resume tour" while a tour left part way waits on this device, else "Tour". */
function tourLabel(phase: string, resumable: boolean): string {
  return phase === 'closed' && resumable ? 'Resume tour' : 'Tour';
}

/**
 * Help in a trial page's header, named for the tour it runs: resume the tour where it was left, start it again, open
 * one chapter, or leave. In the demo build there is no live system to leave for, and the menu says so.
 */
export function TrialHelpMenu() {
  const progress = useGuide((s) => s.progress);
  const phase = useGuide((s) => s.phase);
  const resume = useGuide((s) => s.resume);
  const openWelcome = useGuide((s) => s.openWelcome);
  const openChapters = useGuide((s) => s.openChapters);
  const pos = positionOf(progress);
  const started = !!pos || progress.completed.length > 0 || progress.dismissed;
  const noteId = `${TRIAL_ONLY_ID}-help`;
  const { menu, handOver } = useMenuHandOver();
  return (
    <Menu shadow="md" width={260} position="bottom-end" withinPortal {...menu}>
      <Menu.Target>
        <HeaderHelpButton label={tourLabel(phase, !!pos)} />
      </Menu.Target>
      <Menu.Dropdown aria-describedby={ENV.canLeave ? undefined : noteId}>
        <Menu.Label>The tour</Menu.Label>
        {pos ? (
          <Menu.Item
            className="guide-control"
            leftSection={<IconPlayerPlay size={16} />}
            onClick={handOver(resume)}
          >
            Resume the tour
          </Menu.Item>
        ) : null}
        <Menu.Item
          className="guide-control"
          leftSection={started ? <IconRotate size={16} /> : <IconPlayerPlay size={16} />}
          // The welcome again, with its choice of tours; Start the tour there begins from the first step
          onClick={handOver(openWelcome)}
        >
          {started ? 'Restart the tour' : 'Start the tour'}
        </Menu.Item>
        <Menu.Item
          className="guide-control"
          leftSection={<IconList size={16} />}
          onClick={handOver(openChapters)}
        >
          Choose a chapter
        </Menu.Item>
        <Menu.Divider />
        {ENV.canLeave ? <LeaveTrialItem /> : <TrialOnlyNote id={noteId} />}
      </Menu.Dropdown>
    </Menu>
  );
}
