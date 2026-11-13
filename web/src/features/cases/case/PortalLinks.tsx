import { List, Text } from '@mantine/core';
import type { AgentRun, CaseDetail } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { humanize } from '@/lib/format';
import { runMessageLink } from '@/lib/messageLink';
import { traceScreenshot } from '@/lib/screenshots';
import { NotYet, Section } from './Section';

/**
 * The case in the Management Portal, in one place, on the audit trail: its message trace, its workflow and each agent
 * run's message. The header's IRIS row carries the guide's marks (`case-iris`, `open-trace`).
 */
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
              quiet={!!c.links?.visualTrace && !traceScreenshot(c)}
            >
              Workflow trace
            </PortalLink>
          </List.Item>
        ) : null}
        {withMessage.map((r, i) => (
          <List.Item key={String(r.id ?? r.ensMessageId)}>
            <PortalLink
              href={runMessageLink(r, portalBase)}
              what={`message ${r.ensMessageId}, the agent's request and answer`}
              quiet={i > 0 || !!c.links?.workflowTrace || (!!c.links?.visualTrace && !traceScreenshot(c))}
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
