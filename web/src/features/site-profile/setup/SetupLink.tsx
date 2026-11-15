import { ActionIcon, Tooltip } from '@mantine/core';
import { IconListCheck } from '@tabler/icons-react';
import { Link } from 'react-router';
import type { SiteReceiver } from '@/api/types';
import { HINT_EVENTS } from '@/theme';

/**
 * The Site profile page's ways into Set up the site: icons whose tooltip and name are the words, so the page's own
 * words stay within their budget. With a receiver, the way to its checklist: a draft receiver from onboarding is
 * finished there, any other is changed there. Without one, the page's header action.
 */
export function SetupLink({ r }: { r?: SiteReceiver }) {
  const words = r
    ? `${r.draft === true ? 'Finish' : 'Change'} in Set up the site`
    : 'Set up with Ask Shutter';
  return (
    <Tooltip label={words} events={HINT_EVENTS}>
      <ActionIcon
        component={Link}
        to={r ? `/site-setup?receiver=${encodeURIComponent(r.name)}` : '/site-setup'}
        variant={r ? 'subtle' : 'light'}
        color={r ? 'gray' : undefined}
        size={r ? 28 : 36}
        radius="xl"
        aria-label={r ? `${words}: ${r.name}` : words}
        style={{ flex: 'none' }}
      >
        <IconListCheck size={r ? 16 : 20} aria-hidden />
      </ActionIcon>
    </Tooltip>
  );
}
