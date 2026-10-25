import { Anchor, Button, Group, List, Stack, Table, Text } from '@mantine/core';
import { Link } from 'react-router';
import type { ReviewFinding } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { Timestamp } from '@/components/Timestamp';
import { formatInt } from '@/lib/format';
import { ConfidenceText, FindingStatusBadge, SeverityBadge } from './badges';
import { foundList, headerLink, SOURCE_LABELS, subjectOf } from './review';

const present = (v: number | string | undefined) => v !== undefined && v !== null && v !== '';
/** Whether the evidence names a log row (an event log or rule log entry, which have no message page). */
const logIds = (f: ReviewFinding) => present(f.evidence.latestLogId) || present(f.evidence.latestRuleLogId);

function FindingRow({
  f,
  position,
  namespace,
  approver,
  onMark,
  onUnmark,
}: {
  f: ReviewFinding;
  position: number;
  namespace: string;
  approver: boolean;
  onMark: (f: ReviewFinding) => void;
  onUnmark: (f: ReviewFinding) => void;
}) {
  const found = foundList(f);
  return (
    <Table.Tr>
      <Table.Td style={{ verticalAlign: 'top' }} miw={150} maw={170}>
        <Stack gap={6} align="flex-start">
          <Group gap={6} align="baseline">
            <Text size="sm" fw={600}>
              {position}
            </Text>
            <Text size="xs" c="dimmed">
              {f.id}
            </Text>
          </Group>
          <Stack gap={4} align="flex-start">
            <SeverityBadge severity={f.severity} />
            <ConfidenceText confidence={f.confidence} />
          </Stack>
          <Stack gap={4} align="flex-start">
            <FindingStatusBadge status={f.status} />
            {f.annotationId ? (
              <Text size="xs" c="dimmed">
                Annotation {f.annotationId}
              </Text>
            ) : null}
            {approver ? (
              f.annotationId ? (
                <Button
                  size="compact-xs"
                  variant="subtle"
                  color="red"
                  onClick={() => onUnmark(f)}
                  aria-label={`Remove the annotation of ${f.id}`}
                >
                  Remove annotation
                </Button>
              ) : (
                <Button
                  size="compact-xs"
                  variant="light"
                  onClick={() => onMark(f)}
                  aria-label={`Annotate ${f.id}, ${f.code}`}
                >
                  Annotate…
                </Button>
              )
            ) : null}
          </Stack>
        </Stack>
      </Table.Td>
      <Table.Td
        data-label="Check, item and what was found"
        style={{ verticalAlign: 'top' }}
        miw={230}
        maw={280}
      >
        <Stack gap={6}>
          <div>
            <Text size="sm" ff="monospace" fw={600} style={{ overflowWrap: 'break-word' }}>
              {f.code}
            </Text>
            <Text size="sm">{subjectOf(f)}</Text>
            {f.itemClass ? (
              <Text size="xs" c="dimmed" className="mono-wrap">
                {f.itemClass}
              </Text>
            ) : null}
            {f.setting ? (
              <Text size="xs">
                Setting <span className="mono-wrap">{f.setting}</span>
              </Text>
            ) : null}
          </div>
          <div>
            <Text size="xs" fw={600} c="dimmed">
              Found
            </Text>
            {found.length > 1 ? (
              <List size="sm" spacing={2}>
                {found.map((x) => (
                  <List.Item key={x}>{x}</List.Item>
                ))}
              </List>
            ) : (
              <Text size="sm" style={{ overflowWrap: 'break-word' }}>
                {f.found}
              </Text>
            )}
            <Text size="xs" c="dimmed">
              Source: {SOURCE_LABELS[f.source] ?? f.source}
            </Text>
          </div>
        </Stack>
      </Table.Td>
      <Table.Td data-label="Why, and what to do" style={{ verticalAlign: 'top' }} miw={300}>
        <Stack gap={4}>
          {f.explanation ? (
            <Text size="sm" fw={500}>
              {f.rank !== null ? `Agent, rank ${f.rank}: ` : 'Agent: '}
              {f.explanation}
            </Text>
          ) : null}
          <Text size="sm">{f.why}</Text>
          <Text size="sm">
            <Text span fw={600} size="sm">
              Suggested:{' '}
            </Text>
            {f.suggested}
          </Text>
          <Text size="sm">
            <Text span fw={600} size="sm">
              In the Management Portal:{' '}
            </Text>
            {f.action}
          </Text>
        </Stack>
      </Table.Td>
      <Table.Td data-label="Cases and evidence" style={{ verticalAlign: 'top' }} miw={180} maw={220}>
        <Stack gap={8}>
          <div>
            {f.cases.count ? (
              <Stack gap={2}>
                <Text size="sm">
                  {formatInt(f.cases.count)} {f.cases.count === 1 ? 'case' : 'cases'}
                </Text>
                <Text size="xs" c="dimmed">
                  {formatInt(f.cases.unique)} unique
                </Text>
                <Group gap={6} wrap="wrap">
                  {f.cases.latest.map((id) => (
                    <Anchor
                      key={id}
                      component={Link}
                      to={`/cases/${encodeURIComponent(id)}`}
                      size="xs"
                      style={{ whiteSpace: 'nowrap' }}
                    >
                      {id}
                    </Anchor>
                  ))}
                </Group>
              </Stack>
            ) : (
              <Text size="sm" c="dimmed">
                None
              </Text>
            )}
          </div>
          <div>
            {f.evidence.count || f.evidence.latestHeaderId !== '' || f.evidence.latestAt || logIds(f) ? (
              <Stack gap={2}>
                <Text size="sm">{formatInt(f.evidence.count)} seen</Text>
                {present(f.evidence.latestLogId) ? (
                  <Text size="xs">Event log entry {f.evidence.latestLogId}</Text>
                ) : null}
                {present(f.evidence.latestRuleLogId) ? (
                  <Text size="xs">Rule log entry {f.evidence.latestRuleLogId}</Text>
                ) : null}
                {f.evidence.latestHeaderId !== '' ? (
                  <PortalLink
                    href={headerLink(namespace, f.evidence.latestHeaderId)}
                    what={`message header ${f.evidence.latestHeaderId} in ${namespace}`}
                    size="xs"
                  >
                    Latest header {f.evidence.latestHeaderId}
                  </PortalLink>
                ) : null}
                <Timestamp iso={f.evidence.latestAt} size="xs" />
                {f.evidence.example ? (
                  <Text size="xs" c="dimmed" lineClamp={3} title={f.evidence.example}>
                    {f.evidence.example}
                  </Text>
                ) : null}
              </Stack>
            ) : (
              <Text size="sm" c="dimmed">
                From the configuration
              </Text>
            )}
          </div>
        </Stack>
      </Table.Td>
    </Table.Tr>
  );
}

/**
 * The findings, one row each, in the order given: the finding's place, severity and status; the check, its item, what
 * it found and where the value came from; why it matters, the safer value and what a person does in the Management
 * Portal; the cases and the evidence. Below 1200 px each finding stacks, every part under its name.
 */
export function FindingsTable({
  findings,
  namespace,
  approver,
  onMark,
  onUnmark,
}: {
  findings: ReviewFinding[];
  namespace: string;
  approver: boolean;
  onMark: (f: ReviewFinding) => void;
  onUnmark: (f: ReviewFinding) => void;
}) {
  return (
    // Four columns fit a laptop; below 1200 px each finding stacks, every part under its name
    <Table.ScrollContainer minWidth={880} className="stack-scroll-wide">
      <Table className="stack-table-wide">
        <Table.Thead>
          <Table.Tr>
            <Table.Th>Finding</Table.Th>
            <Table.Th>Check, item and what was found</Table.Th>
            <Table.Th>Why, and what to do</Table.Th>
            <Table.Th>Cases and evidence</Table.Th>
          </Table.Tr>
        </Table.Thead>
        <Table.Tbody>
          {findings.map((f, i) => (
            <FindingRow
              key={f.id}
              f={f}
              position={i + 1}
              namespace={namespace}
              approver={approver}
              onMark={onMark}
              onUnmark={onUnmark}
            />
          ))}
        </Table.Tbody>
      </Table>
    </Table.ScrollContainer>
  );
}
