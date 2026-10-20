import { Anchor, Text, Tooltip } from '@mantine/core';
import { IconExternalLink } from '@tabler/icons-react';
import { DEMO } from '@/demo';

/**
 * A link into the Management Portal (a message trace, a workflow trace, an agent's message). The portal is part of a
 * running IRIS instance, which the demo doesn't have, so there the link is a note saying what it would open.
 */
export function PortalLink({
  href,
  children,
  what,
  size = 'sm',
}: {
  href: string;
  children: React.ReactNode;
  /** What the link opens, for the demo's note: "the Visual Trace of session 11714". */
  what: string;
  size?: 'xs' | 'sm';
}) {
  if (DEMO)
    return (
      <Tooltip
        label={`On an IRIS instance this opens ${what} in the Management Portal. The demo runs in the browser, with no instance behind it.`}
        multiline
        maw={300}
      >
        <Text span size={size} tabIndex={0} style={{ textDecoration: 'underline dotted', cursor: 'help' }}>
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
