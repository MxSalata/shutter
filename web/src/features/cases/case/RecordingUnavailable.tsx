import { Anchor, Text } from '@mantine/core';
import { IconExternalLink } from '@tabler/icons-react';
import { RECORDINGS_URL } from './recordingLinks';

function PublicRecordings() {
  return (
    <Anchor href={RECORDINGS_URL} target="_blank" rel="noreferrer" underline="always" inherit>
      public recordings
      <IconExternalLink size={12} aria-hidden style={{ verticalAlign: 'middle', marginLeft: 2 }} />
    </Anchor>
  );
}

/** While the panel's code or its recording loads. */
export function RecordingReading() {
  return (
    <Text size="sm" c="dimmed">
      Reading the recording
    </Text>
  );
}

/** When a recording cannot be read here: a quiet line and the public files, never an error on the case page. */
export function RecordingUnavailable() {
  return (
    <Text size="sm" c="dimmed" maw="68ch">
      This recording could not be read here. It is one of the <PublicRecordings />.
    </Text>
  );
}

/** When only the plan's recording cannot be read: the panel can't say who dissented, and says that it can't. */
export function PlanUnavailable() {
  return (
    <Text size="sm" c="dimmed" maw="68ch" data-testid="recording-plan-unavailable">
      The coordinator&apos;s recording could not be read here, so any dissent it kept is missing from this
      panel. It is one of the <PublicRecordings />.
    </Text>
  );
}
