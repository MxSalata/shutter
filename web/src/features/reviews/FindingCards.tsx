import { Anchor, Button, Card, Group, List, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import { IconMessageCircle } from '@tabler/icons-react';
import { Link } from 'react-router';
import type { ReviewFinding } from '@/api/types';
import { PortalLink } from '@/components/PortalLink';
import { StatusNotice } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { formatInt } from '@/lib/format';
import { ConfidenceText, FindingStatusBadge, SeverityBadge } from './badges';
import { foundList, headerLink, SOURCE_LABELS, subjectOf } from './review';

const present = (v: number | string | undefined) => v !== undefined && v !== null && v !== '';
/** Whether the evidence names a log row (an event log or rule log entry, which have no message page). */
const logIds = (f: ReviewFinding) => present(f.evidence.latestLogId) || present(f.evidence.latestRuleLogId);

/** A small label over a part of the finding. */
function Label({ children }: { children: React.ReactNode }) {
  return (
    <Text size="xs" fw={700} c="dimmed" tt="uppercase">
      {children}
    </Text>
  );
}

function FindingCard({
  f,
  position,
  namespace,
  canAnnotate,
  recorded,
  onMark,
  onUnmark,
}: {
  f: ReviewFinding;
  position: number;
  namespace: string;
  /** The signed-in user may annotate (the configure resource): the buttons are not offered otherwise. */
  canAnnotate: boolean;
  recorded: boolean;
  onMark: (f: ReviewFinding) => void;
  onUnmark: (f: ReviewFinding) => void;
}) {
  const found = foundList(f);
  const titleId = `finding-${f.id}-title`;
  return (
    <Card component="article" aria-labelledby={titleId} padding="md" withBorder>
      <Stack gap="sm">
        <Group justify="space-between" align="flex-start" gap="xs" wrap="wrap">
          <Stack gap={4} style={{ minWidth: 0, flex: '1 1 260px' }}>
            <Group gap={6} wrap="wrap" align="center">
              <Text size="sm" fw={700} className="tabular">
                {position}
              </Text>
              <Text size="xs" c="dimmed">
                {f.id}
              </Text>
              <SeverityBadge severity={f.severity} />
              <ConfidenceText confidence={f.confidence} />
              <FindingStatusBadge status={f.status} />
            </Group>
            <Title order={3} fz="sm" id={titleId} style={{ overflowWrap: 'anywhere' }}>
              <Text span ff="monospace" fw={700} size="sm">
                {f.code}
              </Text>{' '}
              <Text span fw={500} size="sm">
                {subjectOf(f)}
              </Text>
            </Title>
          </Stack>
          {f.annotationId || canAnnotate ? (
            <Stack gap={4} align="flex-start">
              {f.annotationId ? (
                <Text size="xs" c="dimmed">
                  Annotation {f.annotationId}
                </Text>
              ) : null}
              {canAnnotate ? (
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
          ) : null}
        </Group>
        <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
          <Stack gap="sm" style={{ minWidth: 0 }}>
            <div>
              <Label>Found</Label>
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
              {found.length > 1 ? (
                <List size="sm" spacing={2}>
                  {found.map((x) => (
                    <List.Item key={x}>{x}</List.Item>
                  ))}
                </List>
              ) : (
                <Text size="sm" style={{ overflowWrap: 'anywhere' }}>
                  {f.found}
                </Text>
              )}
              <Text size="xs" c="dimmed">
                Source: {SOURCE_LABELS[f.source] ?? f.source}
              </Text>
            </div>
            <div>
              <Label>Cases</Label>
              {f.cases.count ? (
                <Stack gap={2}>
                  <Text size="sm">
                    {formatInt(f.cases.count)} {f.cases.count === 1 ? 'case' : 'cases'},{' '}
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
              <Label>Evidence</Label>
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
          <Stack gap="sm" style={{ minWidth: 0 }}>
            {/* The agent's own words beside the finding, when it explained this one; the deterministic text follows */}
            {f.explanation ? (
              <StatusNotice
                tone="info"
                role="note"
                icon={IconMessageCircle}
                title={`The agent's explanation${f.rank !== null ? `, rank ${f.rank}` : ''}${recorded ? ' (recorded)' : ''}`}
              >
                <Text size="sm">{f.explanation}</Text>
              </StatusNotice>
            ) : null}
            <div>
              <Label>Why it matters</Label>
              <Text size="sm">{f.why}</Text>
            </div>
            <div>
              <Label>Suggested</Label>
              <Text size="sm">{f.suggested}</Text>
            </div>
            <div>
              <Label>In the Management Portal</Label>
              <Text size="sm">{f.action}</Text>
            </div>
          </Stack>
        </SimpleGrid>
      </Stack>
    </Card>
  );
}

/**
 * The findings, one card each, in the order given (most severe first): the place, severity, confidence and status, the
 * check and its subject; what was found, where the value came from, the cases and the evidence; then the agent's
 * explanation when it gave one, why it matters, the safer value and what a person does in the Management Portal. On a
 * phone the two halves of a card stack, what was found first and what to do under it.
 */
export function FindingCards({
  findings,
  namespace,
  canAnnotate,
  recorded = false,
  onMark,
  onUnmark,
}: {
  findings: ReviewFinding[];
  namespace: string;
  /** The signed-in user may annotate (the configure resource): the buttons are not offered otherwise. */
  canAnnotate: boolean;
  /** The explanations were replayed from a recorded run. */
  recorded?: boolean;
  onMark: (f: ReviewFinding) => void;
  onUnmark: (f: ReviewFinding) => void;
}) {
  return (
    <Stack gap="sm">
      {findings.map((f, i) => (
        <FindingCard
          key={f.id}
          f={f}
          position={i + 1}
          namespace={namespace}
          canAnnotate={canAnnotate}
          recorded={recorded}
          onMark={onMark}
          onUnmark={onUnmark}
        />
      ))}
    </Stack>
  );
}
