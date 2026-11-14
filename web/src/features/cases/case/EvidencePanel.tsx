import { Box, Group, Stack, Text, Title, UnstyledButton, VisuallyHidden } from '@mantine/core';
import { IconCheck, IconClock, IconQuestionMark, IconX } from '@tabler/icons-react';
import { useEffect, useRef, useState } from 'react';
import { usePlan, useRuns, useSnapshot } from '@/api/hooks';
import type { AgentRun, Plan, ReceiverKind, Snapshot, SnapshotItem } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { CodeChip } from '@/components/CodeChip';
import { Digest } from '@/components/Digest';
import { ErrorAlert } from '@/components/ErrorAlert';
import { JsonBlock } from '@/components/JsonBlock';
import { MemberAvatar } from '@/components/MemberAvatar';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { Timestamp } from '@/components/Timestamp';
import {
  EVIDENCE_REFS,
  catalogueEntriesOf,
  citationWords,
  citationsOf,
  evidenceSection,
  isEvidenceRef,
  type Citation,
} from '@/lib/evidenceRefs';
import { SPECIALISTS } from '@/lib/hues';
import { asArray, asObject } from '@/lib/json';
import { displayZone, formatUtcTime, formatZoned, humanize, keyLabel, parseTime, plural } from '@/lib/format';
import { useNow } from '@/lib/useNow';
import { useTechnical } from '@/stores/appearance';
import { describeEntry, describeItem, kindLabel, quotedVersion, receiverKind } from './derive';
import { EncounterTimeline } from './EncounterTimeline';
import { FindingsLines } from './FindingsLines';
import { investigationRuns } from './runClock';
import { NotYet, Section } from './Section';
import { encounterTimeline } from './timeline';

const str = (v: unknown) => (v === undefined || v === null ? '' : String(v));

/**
 * A section of the tab lands under the header and the sticky tab bar when a citation scrolls to it, and when focus
 * moves to its heading: the shared rule's margin (`.case-tab-panel` in styles.css, the bar's 36 px and its gap). It is
 * set here as well because that rule reaches only a panel the case page marks, and not a heading or the catalogue line.
 */
const SCROLL_MARGIN = 'calc(var(--shutter-header-h) + 3.5rem)';

/**
 * The receiver's guarantees as the evidence recorded them from its capability profile: what the gate's capability
 * check reads. When the profile couldn't be read, every guarantee is unknown, never assumed.
 */
export function CapabilityPassport({ data }: { data: Record<string, unknown> }) {
  const status = data.capabilities_http_status;
  const unreadable = status !== undefined && Number(status) !== 200;
  const caps: [string, string, string][] = [
    [
      'conditional_writes',
      'Conditional writes',
      'A write can name the receiver version it expects, and is refused if it changed',
    ],
    ['receipts', 'Receipts', 'Every committed operation can be looked up by its key'],
    // A snapshot from before the gate asked about history says nothing about it, which is no statement about the receiver
    ...(data.history === undefined
      ? []
      : ([['history', 'History', 'Every move of the encounter can be read, whoever made it']] as [
          string,
          string,
          string,
        ][])),
    ['dry_run', 'Dry runs', 'An operation can be rehearsed and rolled back'],
  ];
  return (
    <Stack gap={4}>
      <Group gap={6}>
        {caps.map(([key, label, hint]) => {
          const has = data[key] === true;
          const state = unreadable ? 'unknown' : has ? 'guaranteed' : 'not guaranteed';
          return (
            <StatusBadge
              key={key}
              tone={unreadable ? 'blocking' : has ? 'positive' : 'blocking'}
              label={unreadable ? `${label}: unknown` : has ? label : `${label}: not guaranteed`}
              hint={`${hint}: ${state}`}
              icon={unreadable ? IconQuestionMark : has ? IconCheck : IconX}
            />
          );
        })}
      </Group>
      {unreadable ? (
        <Text size="sm" c="var(--mantine-color-yellow-text)">
          The receiver's capability profile could not be read (HTTP {String(status || 'none')}): nothing is
          assumed about it.
        </Text>
      ) : data.epoch !== undefined && data.epoch !== '' ? (
        <Text size="sm" c="dimmed">
          Read from the receiver's own profile; its epoch is {String(data.epoch)}.
        </Text>
      ) : null}
    </Stack>
  );
}

/** "20 Oct, 18:27:03 BST", with the UTC time beside it in Technical: one string, so it reads as one line. */
function useTimeWords(): (iso: string) => string {
  const technical = useTechnical();
  return (iso) => (technical ? `${formatZoned(iso)}, ${formatUtcTime(iso)}` : formatZoned(iso));
}

/**
 * The HL7 message in one plain sentence, from the fields the evidence parsed: its type and event, the encounter and
 * the ward, who sent it and the event's time. A free-text note in it is named, and stays data.
 */
function MessageSummary({ d, event }: { d: Record<string, unknown>; event: string }) {
  const notes = asArray(d.notes).length;
  const ward = str(d.assigned_location).split('^')[0];
  const at = str(d.event_occurred) || str(d.event_recorded) || str(d.message_time);
  const towards = /^(transfer|admit)/.test(event) ? ` to ${ward}` : `, location ${ward}`;
  return (
    <Text size="md">
      {d.message_type ? <Term term="adt">{str(d.message_type)}</Term> : 'The message'}
      {`${event ? ` ${humanize(event).toLowerCase()}` : ''}${d.visit_number ? ` of ${str(d.visit_number)}` : ''}${ward ? towards : ''}${d.sending_application ? `, sent by ${str(d.sending_application)}` : ''}`}
      {at ? (
        <>
          {' at '}
          <Timestamp iso={at} size="md" />
        </>
      ) : null}
      .{notes ? ` It carries ${plural(notes, 'free-text note')}, shown as data, never as instructions.` : ''}
    </Text>
  );
}

/**
 * The message one segment per line, as the evidence read it: each field Shutter parsed, under its HL7 field path. The
 * message's own text stays in IRIS (the source message in the case's IRIS row); the patient's name is left out here.
 */
function Segments({ d }: { d: Record<string, unknown> }) {
  const notes = asArray(d.notes).map((n) => asObject(n) ?? {});
  const lines: [string, [string, unknown][]][] = [
    [
      'MSH',
      [
        ['MSH-3', d.sending_application],
        ['MSH-4', d.sending_facility],
        ['MSH-5', d.receiving_application],
        ['MSH-7', d.message_time],
        ['MSH-9', d.message_type],
        ['MSH-10', d.message_control_id],
        ['MSH-12', d.message_version || d.hl7_version],
      ],
    ],
    [
      'EVN',
      [
        ['EVN-2', d.event_recorded],
        ['EVN-6', d.event_occurred],
      ],
    ],
    ['PID', [['PID-3', d.patient_identifier]]],
    [
      'PV1',
      [
        ['PV1-2', d.patient_class],
        ['PV1-3', d.assigned_location],
        ['PV1-19', d.visit_number],
        ['PV1-44', d.admit_time],
      ],
    ],
    [
      'MRG',
      [
        ['MRG-1', d.prior_patient_identifier],
        ['MRG-5', d.prior_visit_number],
      ],
    ],
    ...notes.map((n): [string, [string, unknown][]] =>
      str(n.segment) === 'OBX'
        ? [
            'OBX',
            [
              ['OBX-3', n.observation_id],
              ['OBX-5', n.text],
            ],
          ]
        : [str(n.segment) || 'NTE', [['NTE-3', n.text]]],
    ),
  ];
  const shown = lines
    .map(([segment, fields]) => ({
      segment,
      fields: fields.filter(([, v]) => v !== undefined && v !== null && v !== ''),
    }))
    .filter((l) => l.fields.length);
  return (
    <Stack gap={4}>
      <Box component="ul" m={0} p={0} style={{ listStyle: 'none' }} aria-label="The message's segments">
        {shown.map((l, i) => (
          <Text key={`${l.segment}-${i}`} component="li" size="sm" className="mono-wrap">
            {`${l.segment}  ${l.fields.map(([path, v]) => `${path} ${str(v)}`).join(' | ')}`}
          </Text>
        ))}
      </Box>
      <Text size="sm" c="dimmed" maw="68ch">
        {`The fields Shutter read from it, by segment${d.segment_count ? `; the message has ${plural(Number(d.segment_count), 'segment')}` : ''}. The message's own text stays in IRIS.`}
      </Text>
    </Stack>
  );
}

/** The schema validation as a verdict and its codes: valid, not valid, or not checked for want of the schema. */
function ValidationLine({ d }: { d: Record<string, unknown> }) {
  const version =
    d.version_agrees === false && d.version_note ? <Text span>{` ${str(d.version_note)}`}</Text> : null;
  if (d.schema_known === false)
    return (
      <Group gap="xs" wrap="wrap" align="center">
        <StatusBadge tone="attention" label="Not checked" icon={IconQuestionMark} />
        <Text size="md">
          The <CodeChip>{str(d.schema_category) || 'none'}</CodeChip> schema is not loaded here, so the
          message could not be checked.
        </Text>
      </Group>
    );
  if (d.parsed)
    return (
      <Group gap="xs" wrap="wrap" align="center">
        <StatusBadge tone="positive" label="Valid" icon={IconCheck} />
        <Text size="md">
          Parses as <CodeChip>{str(d.doc_type)}</CodeChip>
          {d.schema_category ? (
            <>
              {' '}
              against the <CodeChip>{str(d.schema_category)}</CodeChip> schema
            </>
          ) : null}
          .{version}
        </Text>
      </Group>
    );
  return (
    <Group gap="xs" wrap="wrap" align="center">
      <StatusBadge tone="blocking" label="Not valid" icon={IconX} />
      <Text size="md">
        {d.error ? `Does not parse: ${str(d.error)}` : 'Does not parse.'}
        {version}
      </Text>
    </Group>
  );
}

/** One observation's finding in plain words, every time with its date; the kinds with no time read as the case's story names them. */
function PlainLine({
  item,
  receiver,
  event,
  kind,
}: {
  item: SnapshotItem;
  receiver?: string;
  event: string;
  /** The case's route.kind: a FHIR case's receipt is a marked version in the history, not a receipt store's row. */
  kind?: ReceiverKind;
}) {
  const d = asObject(item.data) ?? {};
  switch (item.kind) {
    case 'message':
      return <MessageSummary d={d} event={event} />;
    case 'validation':
      return <ValidationLine d={d} />;
    case 'findings':
      return <FindingsLines d={d} />;
    case 'operation':
      return (
        <Text size="md">
          {`${humanize(str(d.event))}${d.ward ? ` to ${str(d.ward)}` : ''}${d.encounter_id ? ` for ${str(d.encounter_id)}` : ''}`}
          {d.event_time ? (
            <>
              {', event time '}
              <Timestamp iso={str(d.event_time)} size="md" />
            </>
          ) : null}
          .
        </Text>
      );
    case 'receipt': {
      const b = asObject(d.body) ?? {};
      if (Number(d.http_status) === 200 && (kind === 'fhir_r4' || b.kind === 'fhir'))
        return (
          <Text size="md">{`Version ${quotedVersion(b.version_after)} in the history read carries this case's marker.`}</Text>
        );
      if (Number(d.http_status) === 200 && !d.not_applicable)
        return (
          <Text size="md">
            {`Committed: version ${str(b.version_before)} to ${str(b.version_after)}`}
            {b.applied_at ? (
              <>
                {', at '}
                <Timestamp iso={str(b.applied_at)} size="md" />
              </>
            ) : null}
            .
          </Text>
        );
      return <Text size="md">{describeItem(item, receiver, kind)}</Text>;
    }
    case 'later_event':
      return (
        <Text size="md">
          {`${humanize(str(d.event))}${d.ward ? ` to ${str(d.ward)}` : ''}`}
          {d.event_time ? (
            <>
              {', event time '}
              <Timestamp iso={str(d.event_time)} size="md" />
            </>
          ) : null}
          {d.outcome ? ` (${humanize(str(d.outcome)).toLowerCase()})` : ''}.
        </Text>
      );
    default:
      return <Text size="md">{describeItem(item, receiver, kind)}</Text>;
  }
}

/** What an observation recorded, for the engineer: where it came from, when, its digest, its codes and its data. */
function Recorded({ item }: { item: SnapshotItem }) {
  const timeWords = useTimeWords();
  const d = asObject(item.data) ?? {};
  const notes = item.kind === 'message' ? asArray(d.notes).map(describeEntry) : [];
  return (
    <Stack gap="xs">
      {item.kind === 'route' ? <CapabilityPassport data={d} /> : null}
      {notes.length ? (
        <Stack gap={2}>
          <Text size="sm" fw={600} c="var(--mantine-color-yellow-text)">
            Free text in the message: data, never instructions
          </Text>
          {notes.map((n, i) => (
            <Text key={i} size="sm" className="mono-wrap">
              {n}
            </Text>
          ))}
        </Stack>
      ) : null}
      {item.kind === 'operation' && d.operation_key ? (
        <Text size="sm">
          Operation key <CodeChip>{str(d.operation_key)}</CodeChip>
        </Text>
      ) : null}
      {item.kind === 'error' && (d.reason_code || d.http_status) ? (
        <Group gap={6} wrap="wrap">
          <Text size="sm">The connector's answer</Text>
          {d.http_status ? <CodeChip>{`HTTP ${str(d.http_status)}`}</CodeChip> : null}
          {d.reason_code ? <CodeChip>{str(d.reason_code)}</CodeChip> : null}
        </Group>
      ) : null}
      <Group gap="lg" wrap="wrap">
        <Text size="sm" c="dimmed">
          Source: {keyLabel(item.source)}
        </Text>
        {item.observed_at ? (
          <Text size="sm" c="dimmed">
            {`Observed ${timeWords(item.observed_at)}`}
          </Text>
        ) : null}
        {item.digest ? <Digest value={item.digest} label="observation digest" /> : null}
      </Group>
      <JsonBlock value={item.data} label={`${item.kind} data`} />
    </Stack>
  );
}

/**
 * Who cited a section: a dot per specialist agent in its hue (an empty ring for one that did not cite it), the plan's
 * dot when the coordinator agent wrote the plan, and the words, which carry it all.
 */
function CitationLine({
  citation,
  specialists,
  planMark,
}: {
  citation: Citation;
  specialists: string[];
  planMark: boolean;
}) {
  return (
    <Group gap={6} wrap="nowrap" className="evidence-citation">
      <Group gap={3} wrap="nowrap" aria-hidden>
        {specialists.map((m) => (
          <MemberAvatar key={m} member={m} size={16} hollow={!citation.members.includes(m)} />
        ))}
        {planMark ? <MemberAvatar member="coordinator" size={16} hollow={!citation.plan} /> : null}
      </Group>
      <Text size="sm" c="dimmed">
        {citationWords(citation, specialists)}
      </Text>
    </Group>
  );
}

/** A catalogue entry as the plan names it: its code, its version from the plan's catalogue, and the plan's reason. */
function entryOf(entry: string, plan?: Plan | null): { code: string; version?: string; why?: string } {
  const code = entry.split('@')[0];
  const versions = str((plan as { catalogueVersion?: unknown } | null | undefined)?.catalogueVersion);
  const version =
    entry.split('@')[1] ??
    versions
      .split(',')
      .find((v) => v.split('@')[0] === code)
      ?.split('@')[1];
  return { code, version, why: plan?.catalogueEntry === code ? plan.why : undefined };
}

/**
 * The catalogue entries the plan cites, each a chip that opens the plan's own words about it under the line (in the
 * page, not a floating box, so it reads the same on a phone and stays in a text search).
 */
function CatalogueLine({ entries, plan }: { entries: string[]; plan?: Plan | null }) {
  const [shown, setShown] = useState<string | null>(null);
  const open = shown ? entryOf(shown, plan) : null;
  return (
    <Stack gap={4} id="evidence-catalogue" tabIndex={-1} style={{ scrollMarginTop: SCROLL_MARGIN }}>
      <Text size="md">
        {'The plan also cites '}
        <Term term="catalogue-entry">
          {entries.length > 1 ? 'catalogue entries' : 'catalogue entry'}
        </Term>{' '}
        {entries.map((e, i) => {
          const { code } = entryOf(e, plan);
          return (
            <span key={e}>
              {i ? ', ' : ''}
              <UnstyledButton
                aria-label={`Catalogue entry ${code}: why the plan follows it`}
                aria-expanded={shown === e}
                aria-controls="evidence-catalogue-entry"
                onClick={() => setShown(shown === e ? null : e)}
                style={{ verticalAlign: 'baseline' }}
              >
                <CodeChip>{code}</CodeChip>
              </UnstyledButton>
            </span>
          );
        })}
        .
      </Text>
      <Box id="evidence-catalogue-entry" hidden={!open} className="ask-readonly" p="sm" maw="68ch">
        {open ? (
          <Stack gap={4}>
            <Text size="sm" fw={600}>
              {`Catalogue entry ${open.code}${open.version ? `, version ${open.version}` : ''}`}
            </Text>
            <Text size="sm">
              {open.why ||
                "The plan cites this entry of the site's scenario catalogue; it gives no reason of its own."}
            </Text>
          </Stack>
        ) : null}
      </Box>
    </Stack>
  );
}

/** The members whose runs made the plan, specialists first in the board's order, the single investigator after. */
function specialistsOf(runs: AgentRun[], plan?: Plan | null): string[] {
  const snapshot = (plan as { snapshotId?: unknown } | null | undefined)?.snapshotId;
  const ofPlan = (r: AgentRun) => String((r as { snapshotId?: unknown }).snapshotId) === String(snapshot);
  const used = snapshot !== undefined && runs.some(ofPlan) ? runs.filter(ofPlan) : runs;
  const codes = new Set(used.map((r) => r.memberCode || r.member?.code || r.role));
  codes.delete('coordinator');
  return [
    ...SPECIALISTS.filter((m) => codes.has(m)),
    ...[...codes].filter((m) => !(SPECIALISTS as readonly string[]).includes(m)),
  ];
}

/** One section of the tab: the observations of one kind, under the name the board's citations use. */
interface Group_ {
  key: string;
  title: string;
  items: SnapshotItem[];
}

/**
 * The tab's sections in their order: the evidence refs the agents cite (the message, its validation, what the
 * connector reported, the operation, the route, the receiver's encounter and receipt, the operation timeline, later
 * events), each shown when the snapshot holds it or a citation names it, then any other kind the snapshot holds.
 */
function groupsOf(
  s: Snapshot,
  receiver: string | undefined,
  cited: Set<string>,
  timeline: boolean,
): Group_[] {
  const byKind = new Map<string, SnapshotItem[]>();
  for (const item of s.items) byKind.set(item.kind, [...(byKind.get(item.kind) ?? []), item]);
  const groups: Group_[] = [];
  for (const ref of EVIDENCE_REFS) {
    const items = byKind.get(ref) ?? [];
    const shown = ref === 'timeline' ? timeline || cited.has(ref) : items.length > 0 || cited.has(ref);
    if (shown) groups.push({ key: ref, title: evidenceSection(ref, receiver)!.title, items });
  }
  for (const [kind, items] of byKind)
    if (!isEvidenceRef(kind))
      groups.push({ key: kind, title: kindLabel(kind, receiver) ?? keyLabel(kind), items });
  return groups;
}

/**
 * The section a citation lands on: its own; the catalogue line for an entry; what the connector reported for the
 * failure, and the receiver's encounter for an item of its history (`history[1]`), as Ask's answers name them; else
 * the tab's top, when no section holds it.
 */
function sectionOf(kind: string): string {
  if (kind.startsWith('catalogue')) return 'catalogue';
  if (kind === 'failure') return 'error';
  if (/^history(\[\d+\])?$/.test(kind)) return 'ward_state';
  return kind;
}

/**
 * The Evidence tab: what Shutter read before anyone proposed anything, one snapshot of observations, in the sections
 * the board's citations name. Each section says who cited it (the specialist agents, by their marks and names, and
 * the plan), then what it found in plain words; what was recorded (source, time, digest, the data) is one click
 * away, open in Technical. A citation elsewhere on the page (a board card's chip, a "Cites" badge in Ask) switches to
 * this tab with the kind it names: the section scrolls to the top under the tab bar, its recorded detail opens, and
 * focus moves to its heading.
 */
export function EvidencePanel({
  caseId,
  open,
  focus,
  onFocused,
  receiver,
  notYet = false,
}: {
  caseId: string;
  /** The case's receiver (its production item), named in its own observations' labels. */
  receiver?: string;
  open: boolean;
  /** The case is too young to have a snapshot or a plan, so neither is asked for. */
  notYet?: boolean;
  /** Evidence a citation asked to see: its kind, and when it was asked, so a second click on it acts again. */
  focus?: { kind: string; at: number };
  /** Called once the request is acted on, so a later visit to the tab does not act on it again. */
  onFocused?: () => void;
}) {
  const snap = useSnapshot(caseId, open, notYet);
  const plan = usePlan(caseId, open, notYet).data?.plan;
  // The investigation's runs alone: a question's runs (Ask about this case) sit on the case too
  const runs = investigationRuns(useRuns(caseId, open).data);
  const s = snap.data;
  const now = useNow();
  const expired = s && parseTime(s.freshUntil) ? parseTime(s.freshUntil)!.getTime() < now : false;

  // A citation opens its section's recorded detail; the count makes a second citation of it open it again, even after
  // the reader closed it. Each request is acted on once, when the snapshot is read, then the effect scrolls to it.
  const [requests, setRequests] = useState<Record<string, number>>({});
  const [acted, setActed] = useState(0);
  if (focus && s && acted !== focus.at) {
    setActed(focus.at);
    const key = sectionOf(focus.kind);
    setRequests((r) => ({ ...r, [key]: (r[key] ?? 0) + 1 }));
  }
  const scrolled = useRef(0);
  const timer = useRef<number | undefined>(undefined);
  useEffect(() => () => window.clearTimeout(timer.current), []);
  useEffect(() => {
    if (!focus || !acted || scrolled.current === acted) return;
    scrolled.current = acted;
    const kind = focus.kind;
    // A moment after the tab opens: a drawer the citation came from (Ask, below 1440 px) closes first and hands focus
    // back to its button, and the section must win it
    window.clearTimeout(timer.current);
    timer.current = window.setTimeout(() => {
      const section = document.getElementById(`evidence-${sectionOf(kind)}`);
      const target = section ?? document.getElementById('evidence');
      target?.scrollIntoView?.({ block: 'start' });
      // Focus follows: to the section's heading, or the catalogue line itself
      (document.getElementById(`${target?.id}-title`) ?? target)?.focus({ preventScroll: true });
    }, 150);
    onFocused?.();
  }, [focus, acted, onFocused]);

  const citations = plan || runs.length ? citationsOf(runs, plan) : [];
  const citedBy = new Map(citations.map((c) => [c.ref as string, c]));
  const cited = new Set(citations.filter((c) => c.plan || c.members.length).map((c) => c.ref as string));
  const specialists = specialistsOf(runs, plan);
  const planMark = runs.some((r) => (r.memberCode || r.role) === 'coordinator');
  const entries = catalogueEntriesOf(plan?.evidenceRefs);
  const summary = asObject(s?.summary);
  const timeline = s ? encounterTimeline(s.summary, displayZone()).length > 0 : false;
  const groups = s ? groupsOf(s, receiver, cited, timeline) : [];
  const event = str(asObject(s?.items.find((i) => i.kind === 'operation')?.data)?.event);

  return (
    <Section
      id="evidence"
      title="Evidence"
      note="What Shutter read before anyone proposed anything."
      aside={
        s ? (
          <StatusBadge
            tone={expired ? 'neutral' : 'info'}
            label={
              expired ? `Expired ${formatZoned(s.freshUntil)}` : `Fresh until ${formatZoned(s.freshUntil)}`
            }
            hint={
              expired
                ? `Observations counted as fresh until ${formatZoned(s.freshUntil)}. Freshness is checked when a write is decided: the gate's table shows how it stood then`
                : `Observations count as fresh until ${formatZoned(s.freshUntil)}; a write needs fresh evidence`
            }
            icon={IconClock}
          />
        ) : null
      }
    >
      {snap.isError ? <ErrorAlert error={snap.error} title="The evidence could not be read" /> : null}
      {snap.isSuccess && !s ? <NotYet>No snapshot yet: the evidence is being collected.</NotYet> : null}
      {s ? (
        <Stack gap="lg">
          <Stack gap={4}>
            <Text size="md">
              {`Snapshot ${s.seq}, taken `}
              <Timestamp iso={s.takenAt} size="md" />
              {`, with ${plural(s.items.length, 'observation')}. The agents read only this; the gate checks the plan against it.`}
            </Text>
            {entries.length ? <CatalogueLine entries={entries} plan={plan} /> : null}
            <TechDetail kind="data" label="The snapshot's digests">
              <Stack gap={4}>
                <Group gap={6} wrap="wrap">
                  <Text size="sm" c="dimmed">
                    Digest
                  </Text>
                  <Digest value={s.digest} label="snapshot digest" />
                </Group>
                {s.materialDigest ? (
                  <Group gap={6} wrap="wrap">
                    <Text size="sm" c="dimmed">
                      What a decision rests on, without the observation times
                    </Text>
                    <Digest value={s.materialDigest} label="material digest" />
                  </Group>
                ) : null}
              </Stack>
            </TechDetail>
          </Stack>
          {groups.map((g) => {
            const id = `evidence-${g.key}`;
            const citation = citedBy.get(g.key);
            const request = requests[g.key] ?? 0;
            return (
              <Box
                key={g.key}
                component="section"
                id={id}
                aria-labelledby={`${id}-title`}
                style={{ scrollMarginTop: SCROLL_MARGIN }}
              >
                <Stack gap="xs">
                  <Group justify="space-between" align="center" wrap="wrap" gap="xs">
                    <Title
                      order={3}
                      id={`${id}-title`}
                      tabIndex={-1}
                      style={{ scrollMarginTop: SCROLL_MARGIN }}
                    >
                      {g.title}
                    </Title>
                    {citation && citations.length ? (
                      <CitationLine citation={citation} specialists={specialists} planMark={planMark} />
                    ) : null}
                  </Group>
                  {g.key === 'timeline' ? (
                    timeline ? (
                      <EncounterTimeline summary={s.summary} />
                    ) : (
                      <Text size="md">No operations are recorded for the encounter.</Text>
                    )
                  ) : g.items.length === 0 ? (
                    <Text size="md">
                      {g.key === 'later_event' && summary && Number(summary.later_events) === 0
                        ? 'None: the snapshot found no later event for the encounter.'
                        : 'Not in this snapshot.'}
                    </Text>
                  ) : (
                    g.items.map((item, n) => (
                      <Stack key={item.seq} gap={6}>
                        <PlainLine item={item} receiver={receiver} event={event} kind={receiverKind(s)} />
                        {item.kind === 'message' ? (
                          <TechDetail
                            key={`segments-${request}`}
                            kind="data"
                            label="The message, one segment per line"
                            defaultOpen={request ? true : undefined}
                          >
                            <Segments d={asObject(item.data) ?? {}} />
                          </TechDetail>
                        ) : null}
                        <TechDetail
                          key={`recorded-${request}`}
                          kind="data"
                          defaultOpen={request ? true : undefined}
                          label={
                            <>
                              {/* Named for its section too, so a list of the page's buttons tells them apart */}
                              <VisuallyHidden>
                                {`${g.title}${g.items.length > 1 ? `, ${n + 1} of ${g.items.length}` : ''}: `}
                              </VisuallyHidden>
                              What was recorded
                            </>
                          }
                        >
                          <Recorded item={item} />
                        </TechDetail>
                      </Stack>
                    ))
                  )}
                </Stack>
              </Box>
            );
          })}
          <ApiSource endpoint={`GET /api/shutter/cases/${caseId}/snapshot`} data={s} />
        </Stack>
      ) : null}
    </Section>
  );
}
