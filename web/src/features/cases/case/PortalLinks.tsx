import { List, Text } from '@mantine/core';
import type { AgentRun, CaseDetail } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { humanize } from '@/lib/format';
import { traceScreenshot } from '@/lib/screenshots';
import { NotYet, Section } from './Section';

/** The case in the Management Portal, in one place: its message trace, its workflow and each agent run's message. */
export function PortalLinks({
  c,
  runs,
  portalBase,
}: {
  c: CaseDetail;
  runs: AgentRun[] | null | undefined;
  portalBase: string;
}) {
  const withMessage = (runs ?? []).filter((r) => r.ensMessageId);
  const any = c.links?.visualTrace || c.links?.workflowTrace || withMessage.length;
  return (
    <Section
      id="portal"
      tour="case-iris"
      title="In the Management Portal"
      note="The production's own record of this case: the messages, the workflow and each agent's request and answer."
    >
      {!any ? <NotYet>No portal links for this case.</NotYet> : null}
      <List size="sm" spacing={4}>
        {c.links?.visualTrace ? (
          <List.Item>
            <PortalLink
              href={c.links.visualTrace}
              what={`the Visual Trace of session ${c.ensSessionId}`}
              screenshot={traceScreenshot(c)}
              tourAction="open-trace"
            >
              Message trace
            </PortalLink>
          </List.Item>
        ) : null}
        {c.links?.workflowTrace ? (
          <List.Item>
            <PortalLink
              href={c.links.workflowTrace}
              what={`the trace of the case's workflow session ${c.workflowSessionId}`}
            >
              Workflow trace
            </PortalLink>
          </List.Item>
        ) : null}
        {withMessage.map((r) => (
          <List.Item key={String(r.id ?? r.ensMessageId)}>
            <PortalLink
              href={
                r.messageLink ||
                `${portalBase}EnsPortal.MessageContents.zen?HeaderId=${encodeURIComponent(r.ensMessageId)}`
              }
              what={`message ${r.ensMessageId}, the agent's request and answer`}
            >
              {`${r.member?.name ?? humanize(r.memberCode || r.role)}: its message`}
            </PortalLink>
            <Text span size="xs" c="dimmed">{` (message ${r.ensMessageId})`}</Text>
          </List.Item>
        ))}
      </List>
    </Section>
  );
}
