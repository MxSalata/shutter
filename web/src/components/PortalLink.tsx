import { Anchor, Image, Modal, Stack, Text, Tooltip } from '@mantine/core';
import { IconExternalLink, IconExternalLinkOff } from '@tabler/icons-react';
import { useState } from 'react';
import { TRIAL } from '@/env/mode';
import type { Screenshot } from '@/lib/screenshots';
import { HINT_EVENTS } from '@/theme';

/**
 * A link into the Management Portal (a message trace, a workflow trace, an agent's message). The portal is part of a
 * running IRIS instance, which the trial doesn't have, so there the link is a note saying what it would open, or, when
 * a screenshot of that page is given, a button that shows it. The trial's words: a trial page calls itself the trial,
 * whether it is the demo build or a trial opened on an instance.
 */
export function PortalLink({
  href,
  children,
  what,
  size = 'sm',
  screenshot,
  tourAction,
  quiet = false,
}: {
  href: string;
  children: React.ReactNode;
  /** What the link opens, for the trial's note: "the Visual Trace of session 11714". */
  what: string;
  size?: 'xs' | 'sm';
  /** A picture of the page the link opens, which the trial shows instead. */
  screenshot?: Screenshot;
  /** The guide's name for the control, when a step invites the reader to use it (`data-tour-action`). */
  tourAction?: string;
  /** In the trial, leave out "(needs a real install)": a link beside it has said so already. */
  quiet?: boolean;
}) {
  const [shown, setShown] = useState(false);
  if (TRIAL && screenshot)
    return (
      <>
        <Anchor
          component="button"
          type="button"
          size={size}
          onClick={() => setShown(true)}
          data-tour-action={tourAction}
        >
          {children} (screenshot)
        </Anchor>
        <Modal opened={shown} onClose={() => setShown(false)} title={screenshot.alt} size="auto" centered>
          <Stack gap="xs">
            <Image src={screenshot.src} alt={screenshot.alt} maw="min(1880px, 90vw)" />
            <Text size="sm" c="dimmed" maw={900}>
              {screenshot.caption} On an IRIS instance this link opens {what} in the Management Portal.
            </Text>
          </Stack>
        </Modal>
      </>
    );
  if (TRIAL)
    return (
      <Tooltip
        label={`On an IRIS instance this opens ${what} in the Management Portal. The trial runs in the browser, with no instance behind it.`}
        multiline
        maw={300}
        events={HINT_EVENTS}
      >
        {/* Not a link here: dimmed and plain, with an icon that says so, and the tooltip says where it would go */}
        <Text
          span
          size={size}
          c="dimmed"
          tabIndex={0}
          style={{ cursor: 'help', whiteSpace: 'nowrap' }}
          data-tour-action={tourAction}
        >
          <IconExternalLinkOff size={12} aria-hidden style={{ verticalAlign: 'middle', marginRight: 2 }} />
          {children}
          {quiet ? '' : ' (needs a real install)'}
        </Text>
      </Tooltip>
    );
  return (
    // Underlined: these links sit in running text (the IRIS row, a run's line), where colour alone does not mark them
    <Anchor
      href={href}
      target="_blank"
      rel="noreferrer"
      size={size}
      underline="always"
      data-tour-action={tourAction}
    >
      {children} {size === 'sm' ? <IconExternalLink size={12} /> : null}
    </Anchor>
  );
}
