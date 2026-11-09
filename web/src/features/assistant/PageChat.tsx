import {
  Alert,
  Anchor,
  Badge,
  Box,
  Button,
  Group,
  List,
  Loader,
  Stack,
  Text,
  Textarea,
  Title,
} from '@mantine/core';
import { IconEye, IconLock } from '@tabler/icons-react';
import { useState } from 'react';
import { Link } from 'react-router';
import { isAnswering, useAskPageQuestion, useMe, usePageQuestion, useSettings } from '@/api/hooks';
import type { PageQuestion } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { LiveUnavailableNotice } from '@/components/LiveUnavailableNotice';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { TRIAL } from '@/env/mode';
import { isApiError } from '@/lib/errors';
import { parseTime } from '@/lib/format';
import { liveRefusal, liveRefusalInText, liveUnavailable } from '@/lib/liveAgents';
import { MAIN_ID } from '@/features/shell/SkipLink';
import { AnswerText, focusSoon } from '@/features/cases/ask/AskPanel';
import { guideFor } from './guides';
import { PAGE_ANSWERS_RECORDED } from './recorded';
import { summariseScreen } from './screen';
import { useAssistant, type PageAsked } from './store';

/** The label of a trial answer that is not a recording (features/assistant/recorded.ts). */
export const PAGE_SAMPLE_LABEL = 'Example (sample data)';

/** What the trial says of a question it has no sample answer for. */
export const PAGE_TRIAL_NO_ANSWER =
  'The trial answers its suggested questions only. On a system with a model, any question about the page goes to the Explain agent.';

/** Why a page question cannot be asked live, as the server refuses it (403 live_agents_only). */
export const PAGE_JUDGES_ONLY =
  "Questions about a page are answered live only, and that needs the judges' account. The guide below says what this page is and what to try.";

const turnId = (qid: string) => `ask-page-${qid}`;

/** A page with nothing asked yet: one array, so the store's selector returns the same value each time. */
const NO_ASKED: PageAsked[] = [];

// In UTC, the zone the API carries times in, so a recording reads as made on the same day wherever it is read
const day = new Intl.DateTimeFormat('en-GB', {
  day: 'numeric',
  month: 'long',
  year: 'numeric',
  timeZone: 'UTC',
});

/**
 * Where a page answer came from, in a sentence: sample data in the trial until its answers are recordings; the API mimic
 * (model `mock`, a test fixture that calls no model); otherwise the live run and its model. In the trial the word "live"
 * is kept for the live system alone.
 */
export function pageProvenance(
  q: Pick<PageQuestion, 'mode' | 'model' | 'answeredAt' | 'recordedAt'>,
): string {
  if (TRIAL) {
    if (!PAGE_ANSWERS_RECORDED) return PAGE_SAMPLE_LABEL;
    const at = parseTime(q.recordedAt ?? q.answeredAt);
    return at
      ? `Recorded from a real run on ${day.format(at)}${q.model ? ` with ${q.model}` : ''}`
      : 'Recorded answer';
  }
  if (q.model === 'mock') return 'Answered by the API mimic: no model was called';
  return q.model ? `Answered live with ${q.model}` : 'Answered live';
}

/** A cited id as a link into the app: a case, an incident, a review or a scenario; `page` is this page itself. */
function citeTarget(id: string): { label: string; to: string } | null {
  if (/^C-\d{6}$/.test(id)) return { label: `Case ${id}`, to: `/cases/${id}` };
  if (/^I-\d{6}$/.test(id)) return { label: `Incident ${id}`, to: `/incidents/${id}` };
  if (/^PR-\d{6}$/.test(id)) return { label: `Review ${id}`, to: `/reviews/${id}` };
  if (/^S\d{1,2}[a-z]?$/.test(id)) return { label: id, to: '/scenarios' };
  return null;
}

function Cites({ cites }: { cites: string[] }) {
  const linked = cites.filter((c) => c !== 'page');
  if (!linked.length) return null;
  return (
    <Group gap={8} wrap="wrap" align="center" className="ask-cites">
      <Text size="xs" c="dimmed">
        Cites
      </Text>
      {linked.map((c) => {
        const target = citeTarget(c);
        return target ? (
          <Badge
            key={c}
            size="sm"
            variant="outline"
            color="gray"
            component={Link}
            to={target.to}
            className="ask-cite"
            style={{ textTransform: 'none' }}
          >
            {target.label}
          </Badge>
        ) : (
          <Badge
            key={c}
            size="sm"
            variant="outline"
            color="gray"
            className="ask-cite"
            style={{ textTransform: 'none' }}
          >
            {c}
          </Badge>
        );
      })}
    </Group>
  );
}

/** One question and its answer, read every 2 s until it is answered or refused. */
function Turn({ questionId, question }: { questionId: string; question: string }) {
  const q = usePageQuestion(questionId);
  const settings = useSettings().data;
  const a = q.data;
  const refused = a?.state === 'failed' ? liveRefusalInText(a.error, settings) : null;
  return (
    <Box component="article" aria-labelledby={turnId(questionId)} className="ask-turn">
      <Stack gap="xs">
        <Title order={4} id={turnId(questionId)} tabIndex={-1}>
          {question}
        </Title>
        {q.isError ? (
          <ErrorAlert error={q.error} title="The answer could not be read" onRetry={() => void q.refetch()} />
        ) : !a || isAnswering(a.state) ? (
          <Group gap="xs">
            <Loader size="xs" aria-hidden />
            <Text size="sm">The agent is answering…</Text>
          </Group>
        ) : a.state === 'answered' && a.answer ? (
          <Stack gap="xs">
            <AnswerText text={a.answer.answer} />
            <Cites cites={a.answer.cites ?? []} />
            <Text size="xs" c="dimmed">
              {pageProvenance(a)}.
            </Text>
          </Stack>
        ) : refused ? (
          <LiveUnavailableNotice state={refused} variant="inline" />
        ) : (
          <Text size="sm" c="var(--mantine-color-red-text)">
            {a.state === 'schema_failed'
              ? `The answer was refused: ${a.error || 'it did not keep to the answer schema'}.`
              : `No answer: ${a.error || 'the run failed'}.`}
          </Text>
        )}
      </Stack>
    </Box>
  );
}

/**
 * Why a question was not asked: the live agents cannot run (409 live_unavailable or budget_exhausted), the caller may not
 * spend the budget (403 live_agents_only), no model answers here (409 no_model), or the trial has no sample answer
 * (503 no_service, worded in the trial's own words).
 */
function AskError({ error }: { error: unknown }) {
  const settings = useSettings().data;
  const refused = liveRefusal(error, settings);
  if (refused) return <LiveUnavailableNotice state={refused} role="status" />;
  if (isApiError(error) && error.code === 'live_agents_only')
    return (
      <Alert color="blue" title="Judges only">
        {PAGE_JUDGES_ONLY}
      </Alert>
    );
  if (isApiError(error) && error.code === 'no_model')
    return (
      <Alert color="blue" title="No model answers here">
        {error.detail}
      </Alert>
    );
  if (TRIAL && isApiError(error) && (error.code === 'no_service' || error.code === 'not_in_trial'))
    return (
      <Alert color="blue" title="Not in the trial">
        {PAGE_TRIAL_NO_ANSWER}
      </Alert>
    );
  return <ErrorAlert error={error} title="The question was not asked" />;
}

/** Whether the person may ask about the page, and if not, why. */
interface PageAccess {
  /** A question goes to the server (live, or the trial's mock for its suggested questions). */
  open: boolean;
  /** The free text box takes a question of one's own. */
  free: boolean;
  why: string;
  badge?: string;
  trial?: boolean;
}

/**
 * Who may ask: in the trial, the suggested questions (the mock answers them) and no question of one's own; elsewhere the
 * operator role and the live agents' resource (the server answers 403 to anyone else, so the panel says so first) and a
 * model to answer (a configured provider, or the API mimic on a test instance).
 */
function usePageAccess(): PageAccess {
  const me = useMe().data;
  const s = useSettings().data;
  // The trial's demo role is the live demo's public user, who has no live agents: as on the live demo, where a page has no
  // recorded answers and the server answers 403, its suggested questions are not offered
  if (TRIAL && me?.can?.liveAgents === false)
    return { open: false, free: false, why: PAGE_JUDGES_ONLY, badge: 'Judges only' };
  if (TRIAL) return { open: true, free: false, trial: true, why: 'Needs a real model: not in the trial.' };
  if (!me?.operator) return { open: false, free: false, why: 'Asking needs the operator role.' };
  if (me.can?.liveAgents === false)
    return { open: false, free: false, why: PAGE_JUDGES_ONLY, badge: 'Judges only' };
  if (s && !s.providerConfigured && !s.mock)
    return {
      open: false,
      free: false,
      why: 'Live answers need a model key, and none is configured here. The guide below says what this page is and what to try.',
    };
  return { open: true, free: true, why: '' };
}

/** The written guide to the page: what it is and what to try next, with links. */
export function PageGuideText({ page }: { page: string }) {
  const g = guideFor(page);
  return (
    <Stack gap="xs" data-testid="page-guide">
      <Text size="sm">{g.what}</Text>
      <Text size="sm" fw={600}>
        What to try next
      </Text>
      <List size="sm" spacing={4}>
        {g.next.map((n) => (
          <List.Item key={n.to + n.label}>
            <Anchor component={Link} to={n.to} size="sm" underline="always">
              {n.label}
            </Anchor>
          </List.Item>
        ))}
      </List>
    </Stack>
  );
}

/**
 * Ask Shutter about the page on the screen: the suggested questions as chips, the thread of what was asked here, the box
 * for a question of one's own, and the written guide to the page, open when no live answer can be given. The question
 * goes with a summary of what is in view (screen.ts), ids and labels only, as data; nothing here writes anything.
 */
export function PageChat({ page }: { page: string }) {
  const access = usePageAccess();
  const guide = guideFor(page);
  const ask = useAskPageQuestion();
  const asked = useAssistant((s) => s.threads[page]) ?? NO_ASKED;
  const addAsked = useAssistant((s) => s.addAsked);
  const [text, setText] = useState('');
  const settings = useSettings().data;
  const unavailable = access.free ? liveUnavailable(settings) : null;
  const send = (question: string) => {
    const root = document.getElementById(MAIN_ID) ?? document.body;
    ask.mutate(
      { ask: { page, question, context: summariseScreen(root, page) } },
      {
        onSuccess: (r) => {
          setText('');
          addAsked(page, { questionId: r.questionId, question });
          focusSoon(turnId(r.questionId));
        },
      },
    );
  };
  const askedBefore = (question: string) => asked.find((a) => a.question === question);
  return (
    <Stack gap="lg">
      <Group gap="xs" wrap="nowrap" align="flex-start" className="ask-note">
        <IconEye size={16} aria-hidden className="ask-note-icon" />
        <Text size="sm" c="dimmed">
          <Text span fw={600} inherit>
            Read-only.
          </Text>{' '}
          Answers explain what is on this page. They never change a case, a setting or a receiver.
        </Text>
      </Group>
      <Stack gap="sm">
        <Text size="sm" fw={600} id="ask-page-chips">
          Suggested questions about {guide.title}
        </Text>
        <Group gap="sm" role="group" aria-labelledby="ask-page-chips">
          {guide.questions.map((question) => {
            const done = askedBefore(question);
            return (
              <Button
                key={question}
                size="sm"
                radius="xl"
                variant={done ? 'filled' : 'default'}
                disabled={!access.open || (!!unavailable && !done)}
                loading={ask.isPending && ask.variables?.ask.question === question}
                onClick={() => (done ? focusSoon(turnId(done.questionId)) : send(question))}
                className="wrap-button ask-chip"
              >
                {question}
              </Button>
            );
          })}
        </Group>
        {!access.open ? (
          <Group className="ask-locked" justify="space-between" wrap="wrap" gap="xs" p="sm">
            <Text size="sm" c="dimmed" style={{ flex: '1 1 220px' }}>
              {access.why}
            </Text>
            <StatusBadge tone="neutral" label={access.badge ?? 'Locked: no key'} icon={IconLock} />
          </Group>
        ) : null}
      </Stack>
      {ask.isError ? <AskError error={ask.error} /> : null}
      <div aria-live="polite">
        {asked.length ? (
          <Stack gap="md" component="section" aria-labelledby="ask-page-thread" className="ask-thread" p="md">
            <Title order={3} id="ask-page-thread">
              Conversation
            </Title>
            {asked.map((a) => (
              <Turn key={a.questionId} questionId={a.questionId} question={a.question} />
            ))}
          </Stack>
        ) : null}
      </div>
      {access.trial ? (
        <Stack gap="xs">
          <Textarea
            label="Your own question"
            description={access.why}
            placeholder="In the trial, pick a suggested question"
            autosize
            minRows={2}
            disabled
          />
          <Group>
            <Button disabled>Ask</Button>
          </Group>
        </Stack>
      ) : access.free ? (
        <Stack gap="xs">
          {unavailable ? <LiveUnavailableNotice state={unavailable} /> : null}
          <Textarea
            label="Your own question"
            description="Runs live with the Explain agent, about what is on this page."
            autosize
            minRows={2}
            maxLength={500}
            value={text}
            onChange={(e) => setText(e.currentTarget.value)}
          />
          <Group>
            <Button
              disabled={!text.trim() || !!unavailable}
              loading={ask.isPending}
              onClick={() => send(text.trim())}
            >
              Ask
            </Button>
          </Group>
        </Stack>
      ) : null}
      {access.open && !access.trial ? (
        <TechDetail kind="explain" label={`About this page: ${guide.title}`}>
          <PageGuideText page={page} />
        </TechDetail>
      ) : (
        <Stack gap="xs" component="section" aria-labelledby="ask-page-guide">
          <Title order={3} id="ask-page-guide">
            About this page: {guide.title}
          </Title>
          <PageGuideText page={page} />
        </Stack>
      )}
    </Stack>
  );
}
