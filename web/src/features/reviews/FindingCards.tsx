import { Accordion, Anchor, Box, Button, Chip, Group, List, SimpleGrid, Stack, Text } from '@mantine/core';
import { IconMessageCircle } from '@tabler/icons-react';
import { useEffect, useId, useState } from 'react';
import { Link } from 'react-router';
import type { ReviewFinding } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { KeyValueList } from '@/components/KeyValueList';
import { PortalLink } from '@/components/PortalLink';
import { StatusNotice } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { formatInt } from '@/lib/format';
import { SEVERITY_STATUS } from '@/lib/status';
import { useDetail } from '@/stores/appearance';
import { ConfidenceText, FindingStatusBadge, SeverityBadge } from './badges';
import {
  findingCases,
  findingChip,
  findingSubject,
  findingSummary,
  findingTitle,
  foundList,
  groupBySeverity,
  headerLink,
  inFilter,
  SEVERITIES,
  SOURCE_LABELS,
  type FindingFilter,
} from './review';
import './reviews.css';

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

/** The finding as the machine holds it: the check's code, the class and the setting, the keys, the evidence rows. */
function FindingKeys({ f }: { f: ReviewFinding }) {
  const chip = (v: number | string | undefined) => (present(v) ? <CodeChip>{String(v)}</CodeChip> : '');
  return (
    <TechDetail label="Keys and values" kind="data">
      <KeyValueList
        labelWidth={170}
        rows={[
          ['Check', <CodeChip key="c">{f.code}</CodeChip>],
          ['Item class', chip(f.itemClass)],
          ['Setting', chip(f.setting)],
          ['Source', <CodeChip key="s">{f.source}</CodeChip>],
          ['Confidence', <CodeChip key="f">{f.confidence}</CodeChip>],
          ['Latest header', chip(f.evidence.latestHeaderId)],
          ['Latest event log row', chip(f.evidence.latestLogId)],
          ['Latest rule log row', chip(f.evidence.latestRuleLogId)],
        ]}
      />
    </TechDetail>
  );
}

/** What is inside an open finding: the two halves (what was found, then what it means and what to do). */
function FindingBody({ f, namespace, recorded }: { f: ReviewFinding; namespace: string; recorded: boolean }) {
  const found = foundList(f);
  return (
    <Stack gap="sm">
      <Group gap={6} wrap="wrap" align="center">
        <Text size="xs" c="dimmed">
          {f.id}
        </Text>
        <ConfidenceText confidence={f.confidence} />
        {f.status === 'new' ? <FindingStatusBadge status="new" /> : null}
        {f.annotationId ? (
          <Text size="xs" c="dimmed">
            Annotation {f.annotationId}
          </Text>
        ) : null}
      </Group>
      <SimpleGrid cols={{ base: 1, md: 2 }} spacing="md">
        <Stack gap="sm" style={{ minWidth: 0 }}>
          <div>
            <Label>Found</Label>
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
              <Text size="sm" className="finding-wrap">
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
                <Text size="sm">{findingCases(f)}</Text>
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
                  <Text
                    size="xs"
                    c="dimmed"
                    lineClamp={3}
                    title={f.evidence.example}
                    className="finding-wrap"
                  >
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
              tone="neutral"
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
      <FindingKeys f={f} />
    </Stack>
  );
}

/**
 * One finding as a row of the accordion, closed until it is opened: its severity, a plain title, a chip that names
 * what an engineer looks up, the item, one line built from the finding's own fields and the case count. The
 * annotation state and the Annotate button stand beside the control, not in it, so they work while it is closed.
 * In Technical the check's code sits beside the title.
 */
function FindingRow({
  f,
  namespace,
  canAnnotate,
  recorded,
  onMark,
  onUnmark,
}: {
  f: ReviewFinding;
  namespace: string;
  canAnnotate: boolean;
  recorded: boolean;
  onMark: (f: ReviewFinding) => void;
  onUnmark: (f: ReviewFinding) => void;
}) {
  const technical = useDetail() === 'technical';
  const summaryId = useId();
  const title = findingTitle(f);
  const chip = findingChip(f);
  const subject = findingSubject(f);
  const cases = findingCases(f);
  const marked = f.status !== 'new';
  return (
    <Accordion.Item
      value={f.id}
      className="finding-item"
      data-tone={SEVERITY_STATUS[f.severity]?.tone ?? 'neutral'}
      data-finding={f.id}
    >
      <Box className="finding-head">
        <Accordion.Control
          className="finding-control"
          aria-label={`${title}, ${f.code}`}
          aria-describedby={summaryId}
        >
          <Stack gap={2}>
            <Group gap={6} wrap="wrap" align="center">
              <SeverityBadge severity={f.severity} />
              <Text component="span" fw={600}>
                {title}
              </Text>
              {technical ? <CodeChip>{f.code}</CodeChip> : null}
              {chip ? <CodeChip>{chip}</CodeChip> : null}
              {subject ? (
                <Text component="span" size="sm" c="dimmed">
                  {subject}
                </Text>
              ) : null}
            </Group>
            <Group gap="xs" justify="space-between" wrap="wrap" id={summaryId}>
              <Text component="span" size="sm">
                {findingSummary(f)}
              </Text>
              {cases ? (
                <Text component="span" size="sm" c="dimmed">
                  {cases}
                </Text>
              ) : null}
            </Group>
          </Stack>
        </Accordion.Control>
        {marked || canAnnotate ? (
          <Group gap="xs" wrap="nowrap" className="finding-actions">
            {marked ? <FindingStatusBadge status={f.status} /> : null}
            {canAnnotate ? (
              f.annotationId ? (
                <Button
                  size="compact-sm"
                  variant="subtle"
                  color="red"
                  onClick={() => onUnmark(f)}
                  aria-label={`Remove the annotation of ${f.id}`}
                >
                  Remove annotation
                </Button>
              ) : (
                <Button
                  size="compact-sm"
                  variant="light"
                  onClick={() => onMark(f)}
                  aria-label={`Annotate ${f.id}, ${f.code}`}
                >
                  Annotate…
                </Button>
              )
            ) : null}
          </Group>
        ) : null}
      </Box>
      <Accordion.Panel>
        <FindingBody f={f} namespace={namespace} recorded={recorded} />
      </Accordion.Panel>
    </Accordion.Item>
  );
}

/** The filter chips on offer: everything, each tier that has findings, and new against marked once some are marked. */
function filterOptions(findings: ReviewFinding[]): { value: FindingFilter; label: string }[] {
  const options: { value: FindingFilter; label: string }[] = [
    { value: 'all', label: `All ${formatInt(findings.length)}` },
  ];
  const tiers = SEVERITIES.filter((s) => findings.some((f) => f.severity === s));
  if (tiers.length > 1)
    for (const s of tiers)
      options.push({
        value: s,
        label: `${SEVERITY_STATUS[s].label} ${formatInt(findings.filter((f) => f.severity === s).length)}`,
      });
  const marked = findings.filter((f) => f.status !== 'new').length;
  if (marked > 0 && marked < findings.length)
    options.push({ value: 'new', label: 'New' }, { value: 'marked', label: 'Marked' });
  return options;
}

/**
 * The findings, in the order given, grouped under their severity and each closed until opened. A filter (all, a tier,
 * new, marked) narrows the list. `initialOpen` opens findings at the start (the address's `?finding=`), and the first
 * is scrolled into view.
 */
export function FindingCards({
  findings,
  namespace,
  canAnnotate,
  recorded = false,
  onMark,
  onUnmark,
  initialOpen = [],
}: {
  findings: ReviewFinding[];
  namespace: string;
  /** The signed-in user may annotate (the configure resource): the buttons are not offered otherwise. */
  canAnnotate: boolean;
  /** The explanations were replayed from a recorded run. */
  recorded?: boolean;
  onMark: (f: ReviewFinding) => void;
  onUnmark: (f: ReviewFinding) => void;
  initialOpen?: string[];
}) {
  const [filter, setFilter] = useState<FindingFilter>('all');
  const [open, setOpen] = useState<string[]>(initialOpen);
  const groupId = useId();
  const options = filterOptions(findings);
  const active = options.some((o) => o.value === filter) ? filter : 'all';
  const groups = groupBySeverity(findings.filter((f) => inFilter(f, active)));

  const first = initialOpen[0];
  useEffect(() => {
    if (!first) return;
    const row = Array.from(document.querySelectorAll<HTMLElement>('[data-finding]')).find(
      (el) => el.dataset.finding === first,
    );
    row?.scrollIntoView?.({ block: 'start' });
  }, [first]);

  return (
    <Stack gap="md">
      {options.length > 1 ? (
        <Chip.Group value={active} onChange={(v) => setFilter(v as FindingFilter)}>
          <Group gap="xs" role="radiogroup" aria-label="Show findings">
            {options.map((o) => (
              <Chip key={o.value} value={o.value} size="sm">
                {o.label}
              </Chip>
            ))}
          </Group>
        </Chip.Group>
      ) : null}
      <Accordion
        multiple
        order={4}
        variant="separated"
        chevronPosition="right"
        value={open}
        onChange={setOpen}
        styles={{ item: { marginTop: 0 } }}
      >
        <Stack gap="md">
          {groups.map((g) => (
            <div
              key={g.severity}
              role="group"
              className="finding-group"
              aria-labelledby={`${groupId}-${g.severity}`}
            >
              <Box component="h3" className="overline" id={`${groupId}-${g.severity}`}>
                {SEVERITY_STATUS[g.severity].label}
              </Box>
              <Stack gap="xs">
                {g.findings.map((f) => (
                  <FindingRow
                    key={f.id}
                    f={f}
                    namespace={namespace}
                    canAnnotate={canAnnotate}
                    recorded={recorded}
                    onMark={onMark}
                    onUnmark={onUnmark}
                  />
                ))}
              </Stack>
            </div>
          ))}
        </Stack>
      </Accordion>
    </Stack>
  );
}
