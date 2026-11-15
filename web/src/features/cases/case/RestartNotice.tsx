import { Box, Text } from '@mantine/core';
import { IconRefresh } from '@tabler/icons-react';
import { resolveCan } from '@/api/can';
import { useMe } from '@/api/hooks';
import type { CaseDetail, CaseEvent } from '@/api/types';
import { StatusNotice } from '@/components/StatusBadge';
import { useNow } from '@/lib/useNow';
import { ABANDON_AFTER_MINUTES } from './AbandonPanel';
import { restartOf, restartWords } from './restart';

/**
 * A restart the case has not moved on from, said under the progress strip: when Shutter's production started, what
 * the case was doing, and what a person does now (decide as before, wait, or abandon it once the quiet minutes are
 * over). Read from the start sweep's note in the case's events; nothing is sent from here. Gone as soon as anything
 * else is recorded on the case.
 */
export function RestartNotice({ c, events }: { c: CaseDetail; events: CaseEvent[] | null | undefined }) {
  const me = useMe().data;
  const now = useNow();
  const restart = restartOf(c, events, ABANDON_AFTER_MINUTES);
  if (!restart) return null;
  const { title, body } = restartWords(restart, now, resolveCan(me).approve);
  return (
    <Box mb="sm" data-testid="case-restart">
      <StatusNotice tone="info" icon={IconRefresh} title={title} role="note">
        <Text size="sm">{body}</Text>
      </StatusNotice>
    </Box>
  );
}
