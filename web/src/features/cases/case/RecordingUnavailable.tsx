import { Anchor, Text } from '@mantine/core';
import { IconExternalLink } from '@tabler/icons-react';
import { RECORDINGS_URL } from './recordingLinks';

/** When a recording cannot be read here: a quiet line and the public files, never an error on the case page. */
export function RecordingUnavailable() {
  return (
    <Text size="sm" c="dimmed" maw="68ch">
      This recording could not be read here. It is one of the{' '}
      <Anchor href={RECORDINGS_URL} target="_blank" rel="noreferrer" underline="always" inherit>
        public recordings
        <IconExternalLink size={12} aria-hidden style={{ verticalAlign: 'middle', marginLeft: 2 }} />
      </Anchor>
      .
    </Text>
  );
}
