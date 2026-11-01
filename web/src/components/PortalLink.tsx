import { Anchor, Image, Modal, Stack, Text, Tooltip } from '@mantine/core';
import { IconExternalLink, IconExternalLinkOff } from '@tabler/icons-react';
import { useState } from 'react';
import { TRIAL } from '@/env/mode';
import type { Screenshot } from '@/lib/screenshots';

/**
 * A link into the Management Portal (a message trace, a workflow trace, an agent's message). The portal is part of a
 * running IRIS instance, which the demo doesn't have, so there the link is a note saying what it would open, or, when
 * a screenshot of that page is given, a button that shows it.
 */
export function PortalLink({
  href,
  children,
  what,
  size = 'sm',
  screenshot,
}: {
  href: string;
  children: React.ReactNode;
  /** What the link opens, for the demo's note: "the Visual Trace of session 11714". */
  what: string;
  size?: 'xs' | 'sm';
  /** A picture of the page the link opens, which the demo shows instead. */
  screenshot?: Screenshot;
}) {
  const [shown, setShown] = useState(false);
  if (TRIAL && screenshot)
    return (
      <>
        <Anchor component="button" type="button" size={size} onClick={() => setShown(true)}>
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
        label={`On an IRIS instance this opens ${what} in the Management Portal. The demo runs in the browser, with no instance behind it.`}
        multiline
        maw={300}
      >
        {/* Not a link here: dimmed and plain, with an icon that says so, and the tooltip says where it would go */}
        <Text span size={size} c="dimmed" tabIndex={0} style={{ cursor: 'help', whiteSpace: 'nowrap' }}>
          <IconExternalLinkOff size={12} aria-hidden style={{ verticalAlign: 'middle', marginRight: 2 }} />
          {children} (on an instance)
        </Text>
      </Tooltip>
    );
  return (
    <Anchor href={href} target="_blank" rel="noreferrer" size={size}>
      {children} {size === 'sm' ? <IconExternalLink size={12} /> : null}
    </Anchor>
  );
}
