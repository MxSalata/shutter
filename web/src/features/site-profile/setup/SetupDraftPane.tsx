import { Anchor, Button, Group, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';
import { Link } from 'react-router';
import { StatusBadge } from '@/components/StatusBadge';
import { STATUS_WORDS, statusLabel } from './cards';
import { approvalText, effectsOf } from './effects';
import { QUESTIONS, answerText, consequence, type QuestionId, type SetupQuestion } from './fields';
import { receiverOf, statusOf, useSetup, type AnswerStatus } from './setupStore';

/** The questions of each group of the draft pane. */
const DESCRIBES: QuestionId[] = ['name', 'system', 'category', 'tier'];
const TAKES: QuestionId[] = ['applies', 'resend_timestamp', 'takes'];

const TAKES_HEADING = 'What it can take (declared by the site; Shutter has not checked these)';

const FEATURE_WORDS: [string, string][] = [
  ['conditional_writes', 'conditional writes'],
  ['receipts', 'receipts'],
  ['history', 'a readable history'],
  ['dry_run', 'dry runs'],
];

/** What the entry declares about the receiver's API, in a line: set on the Site profile page, shown here as stored. */
function declaredLine(r: { api?: unknown; features?: Record<string, boolean>; fhir?: unknown }): string {
  if (r.fhir) return 'A FHIR R4 server: what it can do is read from the server itself.';
  if (!r.features)
    return r.api
      ? 'Its features are read from its capabilities endpoint.'
      : "No features declared: it is read on the downstream system's defaults.";
  const yes = FEATURE_WORDS.filter(([k]) => r.features?.[k] === true).map(([, w]) => w);
  return yes.length
    ? `Declared: ${yes.join(', ')}${r.api ? '' : '; no API paths'}.`
    : 'Nothing declared yet: no conditional writes, receipts, history or dry runs, and no API paths.';
}

function Row({
  q,
  value,
  status,
  version,
  note,
  extra,
  onEdit,
  onWhy,
}: {
  q: SetupQuestion;
  value: string;
  status: AnswerStatus;
  version: number;
  note: string;
  /** What a later build adds under a drafted row: the person's quoted words, and Undo. */
  extra?: ReactNode;
  onEdit: () => void;
  onWhy: () => void;
}) {
  return (
    <Stack gap={4} component="li" className="setup-row" data-row={q.id} data-status={status}>
      <Group gap="xs" wrap="wrap" justify="space-between">
        <Text size="sm" fw={600}>
          {q.short}
        </Text>
        <StatusBadge tone={STATUS_WORDS[status].tone} label={statusLabel(status, version)} />
      </Group>
      <Text size="md" style={{ overflowWrap: 'anywhere' }}>
        {value || 'Not answered'}
      </Text>
      <Text size="sm" c="dimmed">
        {note}
      </Text>
      {extra}
      <Group gap="xs">
        <Button size="compact-sm" variant="default" aria-label={`Edit: ${q.short}`} onClick={onEdit}>
          Edit
        </Button>
        <Button size="compact-sm" variant="subtle" aria-label={`Why: ${q.short}`} onClick={onWhy}>
          Why?
        </Button>
      </Group>
    </Stack>
  );
}

/**
 * The draft pane: the receiver as the profile will hold it, in three groups. What describes the system, what it can
 * take as the site declares it, and "What Shutter will do here", which is computed from the draft and never typed. Each
 * answer has whose it is (in force, the person's, drafted, from onboarding, or not answered) and what it does in the
 * page's own words. Edit and Why? go to the question's card, where its control and its explanation are.
 */
export function SetupDraftPane({
  rid,
  onEdit,
  rowExtra,
}: {
  rid: string;
  onEdit: (q: QuestionId, why: boolean) => void;
  rowExtra?: (q: SetupQuestion) => ReactNode;
}) {
  const s = useSetup();
  const r = receiverOf(s, rid);
  if (!r || !s.draft || !s.base) return null;
  const draft = s.draft;
  const version = s.base.version;
  const rows = (ids: QuestionId[]) =>
    QUESTIONS.filter((q) => ids.includes(q.id)).map((q) => (
      <Row
        key={q.id}
        q={q}
        value={answerText(q, r)}
        status={statusOf(s, rid, q)}
        version={version}
        note={consequence(q, r, draft)}
        extra={rowExtra?.(q)}
        onEdit={() => onEdit(q.id, false)}
        onWhy={() => onEdit(q.id, true)}
      />
    ));
  const lines = effectsOf(draft, r);
  const line = (id: string) => lines.find((l) => l.id === id)!;
  return (
    <Stack gap="lg">
      <Stack gap="xs" component="section" aria-labelledby="setup-draft-describes">
        <Title order={3} size="h4" id="setup-draft-describes">
          Describes the system
        </Title>
        <Stack gap="sm" component="ul" className="setup-rows">
          {rows(DESCRIBES)}
        </Stack>
      </Stack>
      <Stack gap="xs" component="section" aria-labelledby="setup-draft-takes">
        <Title order={3} size="h4" id="setup-draft-takes">
          {TAKES_HEADING}
        </Title>
        <Stack gap="sm" component="ul" className="setup-rows">
          {rows(TAKES)}
        </Stack>
        <Text size="sm" data-testid="setup-declared">
          {declaredLine(r)} Its API paths, features and outage answers are set on the{' '}
          <Anchor component={Link} to="/site-profile" inherit underline="always">
            Site profile page
          </Anchor>
          .
        </Text>
      </Stack>
      <Stack gap="xs" component="section" aria-labelledby="setup-draft-effects">
        <Title order={3} size="h4" id="setup-draft-effects">
          What Shutter will do here
        </Title>
        <Text size="sm" c="dimmed">
          Worked out from the draft by the page. Nobody types these lines, and no model writes them.
        </Text>
        <Stack gap={6} component="ul" className="setup-rows" aria-label="What Shutter will do here">
          <Text component="li" size="sm" data-effect="overtaken">
            {line('overtaken').text}
          </Text>
          <Text component="li" size="sm" data-effect="approval">
            Who approves a resend: {approvalText(draft, r)}
          </Text>
          <Text component="li" size="sm" data-effect="case_write">
            {line('case_write').label}: {line('case_write').text}
          </Text>
          <Text component="li" size="sm" data-effect="engine_resend">
            {line('engine_resend').label}: {line('engine_resend').text}
          </Text>
          <Text component="li" size="sm" data-effect="mode">
            {line('mode').label}: {line('mode').text}
          </Text>
        </Stack>
      </Stack>
    </Stack>
  );
}
