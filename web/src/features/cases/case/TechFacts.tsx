import { Group, Stack, Tooltip } from '@mantine/core';
import type { ReactNode } from 'react';
import type { CaseSummary } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { PortalLink } from '@/components/PortalLink';
import { formatUtc } from '@/lib/format';
import { HINT_EVENTS } from '@/theme';
import {
  catalogueEntryOf,
  failureCode,
  messageContentsLink,
  planLabel,
  portalBaseOf,
  utcMillis,
} from './technical';

/**
 * A code with what it is in its tooltip, for a line with no column name above each value. Not a tab stop: a row of
 * them on every case would bury the list's links, and the code reads the same without its hint.
 */
function Fact({ hint, children }: { hint: string; children: ReactNode }) {
  return (
    <Tooltip label={hint} multiline maw={300}>
      <CodeChip fz="xs">{children}</CodeChip>
    </Tooltip>
  );
}

/** When the feed reported the failure, in UTC to the millisecond, as the trace shows it; the full date in its tooltip. */
export function FailedAt({ iso, withDate = false }: { iso: string | undefined; withDate?: boolean }) {
  const shown = utcMillis(iso, withDate);
  if (!iso || !shown) return null;
  return (
    <Tooltip label={`Failed at ${formatUtc(iso)}`} events={HINT_EVENTS}>
      <CodeChip fz="xs" tabIndex={0}>
        <time dateTime={iso}>{shown}</time>
      </CodeChip>
    </Tooltip>
  );
}

/** A trace id that opens its page in the Management Portal (in the trial, the note of what it would open). */
function TraceId({ href, what, children }: { href: string; what: string; children: string }) {
  if (!href) return <CodeChip fz="xs">{children}</CodeChip>;
  return (
    <PortalLink href={href} what={what} size="xs" quiet>
      <CodeChip fz="xs">{children}</CodeChip>
    </PortalLink>
  );
}

/**
 * The list's Technical lines under what happened, each fact once and only when the server sent it: the message (its
 * HL7 type and trigger, else Shutter's event; the control id; the failure kind, the receiver's code and when it
 * failed), where it came in (the item and the production), and the trace and the plan (the session and the header,
 * each opening its Visual Trace or message, the catalogue entry and the plan's version and digest). Nothing of the
 * patient: Plain shows the encounter, and this adds none of the message's fields but MSH-9 and MSH-10.
 */
export function CaseTechLine({ c }: { c: CaseSummary }) {
  const base = portalBaseOf(c);
  const code = failureCode(c);
  const entry = catalogueEntryOf(c);
  const plan = planLabel(c);
  const from = c.sourceItem || c.production;
  return (
    <Stack gap={4} align="flex-start" className="case-tech" data-testid="case-tech">
      <Group gap={4} wrap="wrap" data-testid="case-tech-message">
        {c.messageType ? (
          <Fact hint="The message's type and trigger (MSH-9)">{c.messageType}</Fact>
        ) : c.event ? (
          <CodeChip fz="xs">{c.event}</CodeChip>
        ) : null}
        {c.sourceMessageId ? <Fact hint="The message control id (MSH-10)">{c.sourceMessageId}</Fact> : null}
        {c.failureKind ? <CodeChip fz="xs">{c.failureKind}</CodeChip> : null}
        {code ? <Fact hint="The receiver's answer: its HTTP status and reason code">{code}</Fact> : null}
        <FailedAt iso={c.failedAt} />
      </Group>
      {from ? (
        <Group gap={4} wrap="wrap" data-testid="case-tech-source">
          {c.sourceItem ? <Fact hint="The item the message came in by">{c.sourceItem}</Fact> : null}
          {c.production ? <Fact hint="The production it came in by">{c.production}</Fact> : null}
        </Group>
      ) : null}
      <Group gap={4} wrap="wrap" data-testid="case-tech-trace">
        {c.ensSessionId ? (
          <TraceId href={c.links?.visualTrace ?? ''} what={`the Visual Trace of session ${c.ensSessionId}`}>
            {`session ${c.ensSessionId}`}
          </TraceId>
        ) : null}
        {c.sourceHeaderId ? (
          <TraceId
            href={base ? messageContentsLink(base, c.sourceHeaderId) : ''}
            what={`message ${c.sourceHeaderId}, the HL7 message whose delivery failed`}
          >
            {`header ${c.sourceHeaderId}`}
          </TraceId>
        ) : null}
        {entry ? <CodeChip fz="xs">{`catalogue ${entry}`}</CodeChip> : null}
        {plan ? <Fact hint="The current plan's version and the start of its digest">{plan}</Fact> : null}
      </Group>
    </Stack>
  );
}
