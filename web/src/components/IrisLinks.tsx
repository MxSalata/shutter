import { Group, Text } from '@mantine/core';
import { Fragment } from 'react';
import { useSettings } from '@/api/hooks';
import { TRIAL } from '@/env/mode';
import { resetsHourly } from '@/lib/budget';
import { PORTAL_SIGN_IN } from '@/lib/hospital';
import type { Screenshot } from '@/lib/screenshots';
import { traceScreenshot } from '@/lib/screenshots';
import { CodeChip } from './CodeChip';
import { PortalLink } from './PortalLink';

export interface IrisLink {
  /** The link's words: "Message trace", "Workflow trace", "Source message". */
  label: string;
  /** The number it opens, shown as a code after the words: the session, the message. */
  number?: string;
  /** What the number is ("session", "message"), before it. */
  numberLabel?: string;
  href: string;
  /** What the link opens, for the trial's note: "the Visual Trace of session 16603". */
  what: string;
  screenshot?: Screenshot;
  /** The guide's name for the link, when a step invites the reader to open it. */
  tourAction?: string;
}

/**
 * The IRIS row of a case or an incident header, always visible in both modes: "In IRIS: Message trace (session 16603)
 * · Workflow trace · Source message (MSG00802)", each a Management Portal link (in the trial, the recorded screenshot
 * or a note, as PortalLink does), the numbers as codes. It is the expert's proof that a real production carried the
 * case, at the cost of one quiet line for the newcomer.
 */
export function IrisLinks({ links }: { links: IrisLink[] }) {
  const settings = useSettings().data;
  const onlineDemo = !TRIAL && resetsHourly(settings);
  if (!links.length) return null;
  const firstNote = links.findIndex((l) => !l.screenshot);
  return (
    <Group gap={6} wrap="wrap" align="center" data-tour="case-iris" className="iris-links">
      <Text size="sm" fw={600} span>
        In IRIS:
      </Text>
      {links.map((l, i) => (
        <Fragment key={l.label}>
          {i > 0 ? (
            <Text size="sm" c="dimmed" span aria-hidden>
              ·
            </Text>
          ) : null}
          <Text size="sm" span>
            <PortalLink
              href={l.href}
              what={l.what}
              screenshot={l.screenshot}
              tourAction={l.tourAction}
              quiet={i !== firstNote}
            >
              {l.label}
            </PortalLink>
            {l.number ? (
              <>
                {' ('}
                {l.numberLabel ? `${l.numberLabel} ` : ''}
                <CodeChip>{l.number}</CodeChip>
                {')'}
              </>
            ) : null}
          </Text>
        </Fragment>
      ))}
      {onlineDemo ? (
        <Text size="xs" c="dimmed" span data-testid="iris-sign-in">
          Opens IRIS&apos;s Management Portal in a new tab; it first asks for {PORTAL_SIGN_IN}.
        </Text>
      ) : null}
    </Group>
  );
}

/** A case's IRIS row: its message trace (with the guide's `open-trace` mark), its workflow and its source message. */
export function caseIrisLinks(
  c: {
    ensSessionId?: string;
    workflowSessionId?: string;
    sourceMessageId?: string;
    sourceHeaderId?: string;
    links?: { visualTrace?: string; workflowTrace?: string };
    scenario?: string;
    mode?: string;
  },
  portalBase: string,
): IrisLink[] {
  const links: IrisLink[] = [];
  if (c.links?.visualTrace)
    links.push({
      label: 'Message trace',
      number: c.ensSessionId || undefined,
      numberLabel: 'session',
      href: c.links.visualTrace,
      what: `the Visual Trace of session ${c.ensSessionId}`,
      screenshot: traceScreenshot(c),
      tourAction: 'open-trace',
    });
  // A workflow that ran in the message's own session is the same trace: one link is enough
  if (c.links?.workflowTrace && c.workflowSessionId !== c.ensSessionId)
    links.push({
      label: 'Workflow trace',
      number: c.workflowSessionId || undefined,
      numberLabel: 'session',
      href: c.links.workflowTrace,
      what: `the trace of the case's workflow session ${c.workflowSessionId}`,
    });
  if (c.sourceHeaderId)
    links.push({
      label: 'Source message',
      number: c.sourceMessageId || c.sourceHeaderId,
      href: `${portalBase}EnsPortal.MessageContents.zen?HeaderId=${encodeURIComponent(c.sourceHeaderId)}`,
      what: `message ${c.sourceHeaderId}, the HL7 message whose delivery failed`,
    });
  return links;
}
