import {
  Alert,
  Button,
  Card,
  Chip,
  Code,
  Group,
  List,
  NativeSelect,
  NumberInput,
  Stack,
  Text,
  TextInput,
  Textarea,
  Title,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useEffect, useId, useMemo, useRef, useState } from 'react';
import { saveLocked } from '@/api/saveLocked';
import { useCan, useMe, useSiteEntries, useSiteProfile } from '@/api/hooks';
import type { SiteEntryContent, SiteEntryDetail, SiteEntryPreview, SiteEntryProofResult } from '@/api/types';
import { LockedNote, LockedSaveButton } from '@/components/LockedSave';
import { TechDetail } from '@/components/TechDetail';
import { byEnv } from '@/env/copy';
import { describeError, isApiError } from '@/lib/errors';
import { useTechnical } from '@/stores/appearance';
import {
  inForce,
  preview,
  useProve,
  useSaveDraft,
  useSiteEntry,
  versionOf,
  type Action,
  type EntryBody,
} from './api';
import { ApprovalDialog, SendDialog, SuspendDialog } from './Dialogs';
import { ProofTable } from './ProofTable';
import { SCOPE_KEYS, SCOPE_LABELS, chipLabel, entryYaml, impactLine } from './words';

/**
 * The workbench of one of the site's own scenarios (CONTRACTS 6.8), opened under the list on the Site profile page: a
 * new one started from a closed case, a stored one, or the demo's example. It writes what a person chose (the
 * conditions ticked, the scope, the words, the cases it is proved on) and shows what the core answered: the preview's
 * count of cases it would catch, the proof's table, the waiting proposal. It sends no field that decides, and computes
 * neither what leads nor what a case would do.
 */

type Form = EntryBody;

const EMPTY: Form = {
  title: '',
  priority: 100,
  scope: {},
  pattern: {},
  why: '',
  team: '',
  instructions: '',
  prose: '',
  fixtures: [],
};

const asList = (v: unknown): string[] =>
  Array.isArray(v) ? v.map(String) : v === undefined || v === null || v === '' ? [] : [String(v)];

/** The form from a stored or previewed content: the fixtures as a person names them. */
function formOf(content: Partial<SiteEntryContent> | undefined): Form {
  if (!content) return EMPTY;
  return {
    title: content.title ?? '',
    priority: content.priority ?? 100,
    scope: Object.fromEntries(Object.entries(content.scope ?? {}).map(([k, v]) => [k, asList(v)])),
    pattern: Object.fromEntries(Object.entries(content.pattern ?? {}).map(([k, v]) => [k, asList(v)])),
    why: content.why ?? '',
    team: content.team ?? '',
    instructions: content.instructions ?? '',
    prose: content.prose ?? '',
    fixtures: (content.fixtures ?? []).map((f) => ({ case: f.case, expect: f.expect })),
  };
}

/**
 * Every condition the content's cases showed, for the chips: the frozen conditions of each fixture it must catch, and
 * the pattern's own conditions with their values. A chip unticked leaves its condition out of the pattern: the entry
 * then matches more cases, never fewer.
 */
function observedOf(
  content: Partial<SiteEntryContent> | undefined,
  reserved: string[],
): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  for (const f of content?.fixtures ?? []) {
    if (f.expect !== 'match') continue;
    for (const [k, v] of Object.entries(f.conditions ?? {})) {
      if (reserved.includes(k)) continue;
      out[k] = [...new Set([...(out[k] ?? []), ...asList(v)])];
    }
  }
  for (const [k, v] of Object.entries(content?.pattern ?? {}))
    out[k] = [...new Set([...(out[k] ?? []), ...asList(v)])];
  return out;
}

/** The scope facts the content's cases showed, for the pickers. */
function factsOf(content: Partial<SiteEntryContent> | undefined): Record<string, string[]> {
  const out: Record<string, string[]> = {};
  const add = (k: string, v: unknown) => {
    out[k] = [...new Set([...(out[k] ?? []), ...asList(v).filter(Boolean)])];
  };
  for (const f of content?.fixtures ?? [])
    if (f.expect === 'match') for (const [k, v] of Object.entries(f.scope ?? {})) add(k, v);
  for (const [k, v] of Object.entries(content?.scope ?? {})) add(k, v);
  return out;
}

const same = (a: unknown, b: unknown) => JSON.stringify(a) === JSON.stringify(b);

/** A chip that wraps its words at a phone's width rather than running off the screen. */
const CHIP_STYLES = {
  label: {
    whiteSpace: 'normal' as const,
    height: 'auto',
    minHeight: 'var(--chip-size)',
    lineHeight: 1.35,
    paddingTop: 4,
    paddingBottom: 4,
  },
};

export interface WorkbenchProps {
  /** A stored entry. */
  entryId?: string;
  /** A new one, started from this closed case. */
  fromCase?: string;
  /** The demo's example: read and tried, never saved. */
  example?: { title: string; body: EntryBody };
  /** Open the approval's review at once (the list's "Review" on a waiting proposal). */
  review?: boolean;
  onClose: () => void;
  /** A new draft was saved: the workbench goes on with the stored entry. */
  onSaved: (id: string) => void;
}

export default function Workbench(props: WorkbenchProps) {
  const detail = useSiteEntry(props.entryId);
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => {
    heading.current?.focus();
    heading.current?.scrollIntoView?.({ block: 'start' });
  }, [props.entryId, props.fromCase]);
  const title = props.entryId
    ? `${props.entryId}${detail.data?.title ? `: ${detail.data.title}` : ''}`
    : props.example
      ? props.example.title
      : 'A new one of our scenarios';
  return (
    <Card withBorder padding="md" data-testid="own-workbench">
      <Stack gap="md">
        <Group justify="space-between" align="flex-start" wrap="wrap" gap="xs">
          <Title order={3} size="h4" ref={heading} tabIndex={-1} style={{ outline: 'none', minWidth: 0 }}>
            {title}
          </Title>
          <Button variant="default" size="xs" onClick={props.onClose}>
            Close
          </Button>
        </Group>
        {props.entryId ? (
          detail.isPending ? (
            <Text size="sm">Reading the entry…</Text>
          ) : detail.isError ? (
            <Alert color="red" variant="light" title="The entry could not be read">
              {describeError(detail.error)}
            </Alert>
          ) : (
            <Stored key={`${detail.data.id}-${detail.data.revision}`} entry={detail.data} {...props} />
          )
        ) : props.example ? (
          <Editor start={props.example.body} example onSaved={props.onSaved} onClose={props.onClose} />
        ) : (
          <NewFromCase {...props} />
        )}
      </Stack>
    </Card>
  );
}

/** A new entry: the case to start from, then the editor filled from what the preview read of it. */
function NewFromCase(props: WorkbenchProps) {
  const [caseId, setCaseId] = useState(props.fromCase ?? '');
  const [asked, setAsked] = useState(props.fromCase ?? '');
  // The answer for the case asked about; an answer for another case is not shown
  const [answer, setAnswer] = useState<{ asked: string; read?: SiteEntryPreview; problem?: string } | null>(
    null,
  );
  useEffect(() => {
    if (!asked) return;
    const ctl = new AbortController();
    preview({ fromCase: asked }, ctl.signal)
      .then((r) => {
        const why = r.problems.find((p) => p.field === 'fromCase');
        setAnswer(why ? { asked, problem: why.text } : { asked, read: r });
      })
      .catch((e: unknown) => {
        if (!ctl.signal.aborted) setAnswer({ asked, problem: describeError(e) });
      });
    return () => ctl.abort();
  }, [asked]);
  const current = answer?.asked === asked ? answer : null;
  const read = current?.read;
  const problem = current?.problem ?? '';
  if (read)
    return (
      <Editor
        start={formOf(read.content)}
        startContent={read.content}
        onSaved={props.onSaved}
        onClose={props.onClose}
      />
    );
  return (
    <Stack gap="xs">
      <Text size="sm">
        Start from a closed case of this site&apos;s: every condition it showed becomes a ticked chip, and the
        case is the first one the scenario must catch.
      </Text>
      <Group gap="xs" align="flex-end" wrap="wrap">
        <TextInput
          label="Case"
          placeholder="C-000123"
          value={caseId}
          onChange={(e) => setCaseId(e.currentTarget.value.trim())}
          onKeyDown={(e) => {
            if (e.key === 'Enter' && caseId) setAsked(caseId);
          }}
          style={{ flex: '1 1 160px', maxWidth: 240 }}
        />
        <Button variant="default" disabled={!caseId} onClick={() => setAsked(caseId)}>
          Read its conditions
        </Button>
      </Group>
      {asked && !problem ? <Text size="sm">Reading {asked}…</Text> : null}
      {problem ? (
        <Alert color="red" variant="light" role="alert" title={`Case ${asked} cannot start one`}>
          {problem}
        </Alert>
      ) : null}
    </Stack>
  );
}

/** A stored entry: where it stands, what waits for whom, and the editor when its draft can be changed. */
function Stored({ entry, review, onSaved, onClose }: WorkbenchProps & { entry: SiteEntryDetail }) {
  const can = useCan();
  const me = useMe().data;
  const technical = useTechnical();
  // A draft is open for writing: a never-active entry's, or one begun beside the active version
  const [editing, setEditing] = useState(!entry.proposal && (entry.state === 'draft' || !!entry.draft));
  const [send, setSend] = useState<Action | null>(null);
  const [reviewing, setReviewing] = useState(!!review && !!entry.proposal);
  const [suspending, setSuspending] = useState(false);
  const live = entry.state === 'active' || entry.state === 'suspended';
  // A draft beside the active version is the one written; an entry never active shows its draft as its content
  const draftContent =
    entry.draft?.content ??
    (entry.state === 'draft' || entry.state === 'proposed' ? entry.content : undefined);
  const shown = draftContent ?? entry.content;
  const lockedId = useId();
  const locked = saveLocked(can);
  // Try it on the entry as it stands: the same table a proof gives, with nothing kept (the demo's way to read one)
  const [tried, setTried] = useState<SiteEntryPreview | null>(null);
  const [trying, setTrying] = useState(false);
  const [tryProblem, setTryProblem] = useState('');
  const onTry = () => {
    setTrying(true);
    setTryProblem('');
    // An active entry is tried as the matcher holds it: with what a recheck dropped left out
    preview({ ...formOf(draftContent ? shown : inForce(entry, 'retire', shown)), id: entry.id })
      .then((r) => setTried(r))
      .catch((e: unknown) => setTryProblem(describeError(e)))
      .finally(() => setTrying(false));
  };
  return (
    <Stack gap="sm">
      <Text size="sm">
        {entry.sentence
          ? `${entry.sentence}.`
          : `${entry.unreadable ?? "This entry's content cannot be read"}.`}
      </Text>
      {entry.draft && live ? (
        <Text size="sm">{`Draft version ${entry.draft.version} is written beside version ${entry.activeVersion}: it changes nothing until a second person approves it.`}</Text>
      ) : null}
      {entry.proposal ? (
        <Alert color="yellow" variant="light" title="Waiting for a second person" data-testid="own-proposal">
          <Stack gap="xs">
            <Text size="sm">
              {`${entry.proposal.by} proposed to ${entry.proposal.action === 'activate' ? `make version ${entry.proposal.version} active` : entry.proposal.action === 'retire' ? 'retire it' : 'resume it'}`}
              {'. Until it is approved, nothing changes.'}
            </Text>
            <Group>
              <Button size="xs" onClick={() => setReviewing(true)}>
                Review the proposal…
              </Button>
            </Group>
          </Stack>
        </Alert>
      ) : null}
      {technical && entry.digest ? (
        <Text size="xs" c="dimmed" ff="monospace" style={{ overflowWrap: 'anywhere' }}>
          {`version ${entry.version ?? ''} digest ${entry.digest} revision ${entry.revision}`}
        </Text>
      ) : null}
      {entry.state !== 'retired' &&
      (!entry.proposal || (entry.state === 'active' && can.approve && can.configure)) ? (
        <Group gap="xs" wrap="wrap" data-testid="own-entry-actions">
          {live && !editing && !entry.proposal ? (
            <Button size="xs" variant="default" onClick={() => setEditing(true)}>
              {entry.draft ? 'Edit the draft' : 'Change it'}
            </Button>
          ) : null}
          {live && !entry.proposal ? (
            <Button size="xs" variant="default" onClick={() => setSend('retire')}>
              Propose retiring it…
            </Button>
          ) : null}
          {entry.state === 'suspended' && !entry.proposal ? (
            <Button size="xs" variant="default" onClick={() => setSend('resume')}>
              Propose resuming it…
            </Button>
          ) : null}
          {/* R12: one approver switches an active entry off at once, whatever proposal waits on it */}
          {entry.state === 'active' && can.approve && can.configure ? (
            <Button size="xs" variant="light" color="red" onClick={() => setSuspending(true)}>
              Suspend it…
            </Button>
          ) : null}
        </Group>
      ) : null}
      {editing && !entry.proposal ? (
        <Editor
          start={formOf(shown)}
          startContent={shown}
          entry={entry}
          onSend={() => setSend('activate')}
          onSaved={onSaved}
          onClose={onClose}
        />
      ) : (
        <TechDetail label="The entry as it is stored" kind="data">
          <Code block data-testid="own-yaml" style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
            {entryYaml({ ...shown, id: entry.id })}
          </Code>
        </TechDetail>
      )}
      {entry.state === 'retired' ? (
        <Text size="sm" c="dimmed">
          Retired: its history is kept, and its id is never used again.
        </Text>
      ) : null}
      {!editing && shown ? (
        <Stack gap="xs">
          <Group>
            <Button size="xs" variant="default" loading={trying} onClick={onTry} data-testid="own-try">
              Try it
            </Button>
          </Group>
          {tryProblem ? (
            <Text size="sm" c="red">
              {tryProblem}
            </Text>
          ) : null}
          {tried?.proof ? <ProofTable proof={tried.proof} preview testId="own-tried" /> : null}
        </Stack>
      ) : null}
      {locked && !editing ? <LockedNote id={lockedId}>{locked}</LockedNote> : null}
      {send ? <SendDialog entry={entry} action={send} onClose={() => setSend(null)} /> : null}
      {reviewing && entry.proposal ? (
        <ApprovalDialog entry={entry} me={me?.username ?? ''} onClose={() => setReviewing(false)} />
      ) : null}
      {suspending ? <SuspendDialog entry={entry} onClose={() => setSuspending(false)} /> : null}
    </Stack>
  );
}

const RESERVED = ['death_recorded'];

/**
 * The editor: the chips of the conditions the cases showed, the line that says at once what the pattern would catch,
 * the scope, the words, the cases it is proved on, and the buttons. On the demo, and for a reader who may not change
 * the site, Save is locked with the site profile's own explanation and Try it still runs.
 */
function Editor({
  start,
  startContent,
  entry,
  example = false,
  onSend,
  onSaved,
}: {
  start: Form;
  startContent?: Partial<SiteEntryContent>;
  entry?: SiteEntryDetail;
  example?: boolean;
  onSend?: () => void;
  onSaved: (id: string) => void;
  onClose: () => void;
}) {
  const can = useCan();
  const technical = useTechnical();
  const profile = useSiteProfile().data?.profile;
  const list = useSiteEntries().data;
  const locked = saveLocked(can);
  const lockedId = useId();
  const [form, setForm] = useState<Form>(start);
  const [saved, setSaved] = useState<Form>(start);
  const observed = useMemo(
    () => observedOf(startContent ?? { pattern: start.pattern }, RESERVED),
    [startContent, start],
  );
  const facts = useMemo(() => factsOf(startContent ?? { scope: start.scope }), [startContent, start]);
  // The preview's answer for the shape it was asked about; while the shape differs, it is being counted
  const [answered, setAnswered] = useState<{ shape: string; result: SiteEntryPreview | null } | null>(null);
  const [tried, setTried] = useState<SiteEntryPreview | null>(null);
  const [trying, setTrying] = useState(false);
  const [proof, setProof] = useState<SiteEntryProofResult | null>(null);
  const [problem, setProblem] = useState('');
  const [near, setNear] = useState('');
  const save = useSaveDraft();
  const prove = useProve(entry?.id ?? '');
  const dirty = !same(form, saved);
  const set = (fn: (f: Form) => Form) => {
    setProblem('');
    setForm((f) => fn(structuredClone(f)));
  };
  // What the preview reads: the pattern, the scope and the cases; the words do not change a count
  const shape = JSON.stringify([form.pattern, form.scope, form.fixtures, form.priority]);
  useEffect(() => {
    const ctl = new AbortController();
    const t = setTimeout(() => {
      preview({ ...form, id: entry?.id }, ctl.signal)
        .then((r) => setAnswered({ shape, result: r }))
        .catch(() => {
          if (!ctl.signal.aborted) setAnswered({ shape, result: null });
        });
    }, 400);
    return () => {
      clearTimeout(t);
      ctl.abort();
    };
    // The words are left out on purpose: a title does not change what the pattern catches
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [shape, entry?.id]);
  const counting = answered?.shape !== shape;
  const live = answered?.result ?? null;

  const toggle = (condition: string) =>
    set((f) => {
      if (f.pattern[condition]) delete f.pattern[condition];
      else f.pattern[condition] = observed[condition] ?? [];
      return f;
    });
  const toggleScope = (fact: string, value: string) =>
    set((f) => {
      const now = f.scope[fact] ?? [];
      const next = now.includes(value) ? now.filter((v) => v !== value) : [...now, value];
      if (next.length) f.scope[fact] = next;
      else delete f.scope[fact];
      return f;
    });
  const addFixture = (expect: 'match' | 'no_match') =>
    set((f) => {
      const id = near.trim();
      if (id && !f.fixtures.some((x) => x.case === id)) f.fixtures.push({ case: id, expect });
      return f;
    });
  const hasNear = form.fixtures.some((f) => f.expect === 'no_match');
  const hasMatch = form.fixtures.some((f) => f.expect === 'match');
  const receivers = (profile?.receivers ?? []).map((r) => r.name).filter(Boolean);
  const teams = profile?.teams ?? [];
  const scopeOptions = (fact: string): string[] => {
    const own = form.scope[fact] ?? [];
    const offered = fact === 'receiver' ? receivers : (facts[fact] ?? []);
    return [...new Set([...offered, ...own])];
  };
  const problems = live?.problems ?? [];
  const warnings = live?.warnings ?? [];
  const draftDigest = entry?.draft?.digest ?? (entry && !entry.activeVersion ? entry.digest : undefined);
  // The proof a proposal would stand on: the newest a person ran, never an approval's own run
  const lastProof = entry?.proofs.find(
    (p) => p.action === 'activate' && p.digest === draftDigest && p.origin === 'api',
  );
  const provedNow =
    proof?.passed && proof.digest === draftDigest ? proof : lastProof?.passed ? lastProof.result : null;

  const onSave = () => {
    setProblem('');
    save.mutate(
      { id: entry?.id, revision: entry?.revision, body: form },
      {
        onSuccess: (e) => {
          setSaved(form);
          notifications.show({
            color: 'teal',
            message: byEnv({
              live: `Draft ${e.id} saved: it changes nothing until it is proved and a second person approves it.`,
              trial: `Draft ${e.id} saved in this browser's copy, until you reload or leave.`,
            }),
          });
          if (!entry) onSaved(e.id);
        },
        onError: (e) =>
          setProblem(
            isApiError(e) && e.code === 'stale_version'
              ? 'Someone else changed this entry while you were editing. Your changes are kept here: close and open it again to see theirs.'
              : describeError(e),
          ),
      },
    );
  };
  const onTry = () => {
    setTrying(true);
    setProblem('');
    preview({ ...form, id: entry?.id })
      .then((r) => setTried(r))
      .catch((e: unknown) => setProblem(describeError(e)))
      .finally(() => setTrying(false));
  };
  const onProve = () =>
    prove.mutate('activate', {
      onSuccess: (r) => setProof(r),
      onError: (e) => setProblem(describeError(e)),
    });

  return (
    <Stack gap="md" data-testid="own-editor">
      {example ? (
        <Text size="sm" c="dimmed" data-testid="own-example-note">
          An example to try, not one of this site&apos;s: it is not stored, and it changes nothing.
        </Text>
      ) : null}
      <Stack gap={6}>
        <Text size="sm" fw={600} id="own-conditions-label">
          {technical ? 'Pattern: the conditions it needs' : 'It applies when'}
        </Text>
        <Text size="sm" c="dimmed">
          Untick a condition to catch more cases: the scenario then needs it no longer.
        </Text>
        <Group
          gap={6}
          wrap="wrap"
          role="group"
          aria-labelledby="own-conditions-label"
          data-testid="own-chips"
        >
          {Object.entries(observed).map(([condition, values]) => (
            <Chip
              key={condition}
              size="sm"
              checked={!!form.pattern[condition]}
              onChange={() => toggle(condition)}
              styles={CHIP_STYLES}
              data-condition={condition}
            >
              {chipLabel(condition, form.pattern[condition] ?? values, technical)}
            </Chip>
          ))}
        </Group>
        <Text size="sm" aria-live="polite" data-testid="own-live-impact">
          {/* An answer for an earlier pattern is never shown as this one's */}
          {counting
            ? 'Counting what it would catch…'
            : live?.proof?.impact
              ? impactLine(live.proof.impact)
              : Object.keys(form.pattern).length
                ? 'What it would catch could not be counted.'
                : 'Tick at least one condition.'}
        </Text>
      </Stack>
      <Stack gap={6}>
        <Text size="sm" fw={600}>
          {technical ? 'Scope: facts of the case' : 'And only'}
        </Text>
        {SCOPE_KEYS.map((fact) =>
          scopeOptions(fact).length ? (
            <Stack gap={4} key={fact}>
              <Text size="sm" id={`own-scope-${fact}`}>
                {technical ? fact : SCOPE_LABELS[fact]}
              </Text>
              <Group gap={6} wrap="wrap" role="group" aria-labelledby={`own-scope-${fact}`}>
                {scopeOptions(fact).map((v) => (
                  <Chip
                    key={v}
                    size="sm"
                    checked={(form.scope[fact] ?? []).includes(v)}
                    onChange={() => toggleScope(fact, v)}
                    styles={CHIP_STYLES}
                  >
                    {v}
                  </Chip>
                ))}
              </Group>
            </Stack>
          ) : null,
        )}
        <Text size="sm" c="dimmed">
          Nothing ticked under a fact: any value holds.
        </Text>
      </Stack>
      <TextInput
        label="Title"
        required
        value={form.title}
        maxLength={200}
        onChange={(e) => {
          const v = e.currentTarget.value;
          set((f) => ({ ...f, title: v }));
        }}
      />
      <Textarea
        label="Why a person must decide"
        required
        autosize
        minRows={2}
        maxLength={500}
        value={form.why}
        onChange={(e) => {
          const v = e.currentTarget.value;
          set((f) => ({ ...f, why: v }));
        }}
      />
      <NativeSelect
        label="Who to tell"
        value={form.team}
        data={[
          { value: '', label: 'No team named' },
          ...teams.map((t) => ({ value: t.id, label: t.name || t.id })),
          ...(form.team && !teams.some((t) => t.id === form.team)
            ? [{ value: form.team, label: form.team }]
            : []),
        ]}
        onChange={(e) => {
          const v = e.currentTarget.value;
          set((f) => ({ ...f, team: v }));
        }}
      />
      <Textarea
        label="What the person should do"
        autosize
        minRows={2}
        maxLength={2000}
        value={form.instructions}
        onChange={(e) => {
          const v = e.currentTarget.value;
          set((f) => ({ ...f, instructions: v }));
        }}
      />
      {technical ? (
        <NumberInput
          label="Priority"
          description="Among our scenarios that match the same case, the lowest number leads"
          min={1}
          max={999}
          value={form.priority}
          onChange={(v) => set((f) => ({ ...f, priority: typeof v === 'number' ? v : 100 }))}
          maw={220}
        />
      ) : null}
      <Stack gap={6} data-testid="own-fixtures">
        <Text size="sm" fw={600}>
          The cases it is proved on
        </Text>
        {form.fixtures.length ? (
          <List size="sm" spacing={4}>
            {form.fixtures.map((f) => (
              <List.Item key={f.case}>
                <Group gap={6} wrap="wrap">
                  <Text span size="sm">
                    {`${f.case}: ${f.expect === 'match' ? 'it must catch this case' : 'it must leave this case alone'}`}
                  </Text>
                  <Button
                    size="compact-xs"
                    variant="subtle"
                    aria-label={`Remove ${f.case}`}
                    onClick={() =>
                      set((x) => ({ ...x, fixtures: x.fixtures.filter((y) => y.case !== f.case) }))
                    }
                  >
                    Remove
                  </Button>
                </Group>
              </List.Item>
            ))}
          </List>
        ) : null}
        {!hasNear ? (
          <Alert color="yellow" variant="light" data-testid="own-near-miss-ask" title="Name a near miss">
            A closed case like these that the scenario must leave alone. Without one the proof cannot pass:
            nothing would show the pattern is no wider than you meant.
          </Alert>
        ) : null}
        <Group gap="xs" align="flex-end" wrap="wrap">
          <TextInput
            label="Another closed case"
            placeholder="C-000101"
            value={near}
            onChange={(e) => setNear(e.currentTarget.value)}
            style={{ flex: '1 1 160px', maxWidth: 240 }}
          />
          <Button variant="default" disabled={!near.trim()} onClick={() => addFixture('no_match')}>
            Add as a near miss
          </Button>
          <Button variant="subtle" disabled={!near.trim()} onClick={() => addFixture('match')}>
            Add as one to catch
          </Button>
        </Group>
        {!hasMatch ? <Text size="sm">It also needs at least one case it must catch.</Text> : null}
      </Stack>
      {problems.length || warnings.length ? (
        <Stack gap={2} data-testid="own-problems">
          {problems.length ? (
            <Text size="sm" fw={600}>
              Before it can be saved:
            </Text>
          ) : null}
          <List size="sm" spacing={2}>
            {problems.map((p) => (
              <List.Item key={`${p.field}-${p.text}`}>{p.text}</List.Item>
            ))}
            {warnings.map((p) => (
              <List.Item key={`w-${p.field}-${p.text}`}>{`Check: ${p.text}`}</List.Item>
            ))}
          </List>
        </Stack>
      ) : null}
      <TechDetail label="The entry as YAML" kind="data">
        <Code block data-testid="own-yaml" style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
          {entryYaml({ ...form, id: entry?.id ?? live?.id })}
        </Code>
      </TechDetail>
      {problem ? (
        <Alert color="red" variant="light" role="alert" title="Nothing was saved">
          {problem}
        </Alert>
      ) : null}
      <Group gap="sm" wrap="wrap">
        <Button variant="default" loading={trying} onClick={onTry} data-testid="own-try">
          Try it
        </Button>
        {locked ? (
          <LockedSaveButton label="Save the draft" noteId={lockedId} />
        ) : example ? null : (
          <Button onClick={onSave} loading={save.isPending} disabled={!dirty && !!entry}>
            Save the draft
          </Button>
        )}
        {entry && !locked ? (
          <Button
            variant="default"
            onClick={onProve}
            loading={prove.isPending}
            disabled={dirty}
            aria-describedby={dirty ? `${lockedId}-dirty` : undefined}
          >
            Prove it
          </Button>
        ) : null}
        {entry && !locked && provedNow && !dirty ? (
          <Button variant="light" onClick={onSend}>
            Send for approval…
          </Button>
        ) : null}
      </Group>
      {locked ? <LockedNote id={lockedId}>{locked}</LockedNote> : null}
      {entry && dirty && !locked ? (
        <Text size="sm" c="dimmed" id={`${lockedId}-dirty`}>
          Save the draft first: a proof is kept against what is saved.
        </Text>
      ) : null}
      {tried?.proof ? <ProofTable proof={tried.proof} preview testId="own-tried" /> : null}
      {tried && !tried.proof ? <Text size="sm">Tick at least one condition to try it.</Text> : null}
      {proof ? (
        <ProofTable proof={proof} />
      ) : !tried && lastProof && !dirty ? (
        <ProofTable proof={lastProof.result} />
      ) : null}
      {entry ? (
        <Text size="xs" c="dimmed">
          {versionLine(entry, list?.status.limit)}
        </Text>
      ) : null}
    </Stack>
  );
}

/** Which version the editor writes. */
function versionLine(entry: SiteEntryDetail, limit?: number): string {
  const v = versionOf(entry, 'activate');
  const words = v ? `You are writing version ${v.version}.` : '';
  return `${words}${limit ? ` A site has at most ${limit} of its own scenarios active.` : ''}`.trim();
}
