import {
  Alert,
  Badge,
  Box,
  Button,
  Group,
  List,
  Loader,
  Stack,
  Tabs,
  Text,
  Textarea,
  Title,
  VisuallyHidden,
} from '@mantine/core';
import { IconCheck, IconEye, IconLock, IconMessageQuestion } from '@tabler/icons-react';
import { useEffect, useRef, useState } from 'react';
import {
  isAnswering,
  useAskQuestion,
  useCaseQuestions,
  useMe,
  useSettings,
  useSuggestedQuestions,
} from '@/api/hooks';
import type { BoardAnswer, CaseQuestion, QuestionTier, SuggestedTurn } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { LiveUnavailableNotice } from '@/components/LiveUnavailableNotice';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { TRIAL } from '@/env/mode';
import { isApiError } from '@/lib/errors';
import { keyLabel } from '@/lib/format';
import { liveRefusal, liveRefusalInText, liveUnavailable } from '@/lib/liveAgents';
import { showEvidence } from '../case/evidenceLinks';
import {
  MEMBER_NAMES,
  TIERS,
  TRIAL_NO_ANSWER,
  answerParts,
  answersBadge,
  provenanceText,
  tierLabel,
} from './labels';
import { WHATIF_ID, WhatIfCard } from './WhatIfCard';

/** A turn's heading id, which takes focus when its answer is asked for or shown. */
const turnId = (q: { conversation: string; turn: number }) => `ask-turn-${q.conversation}-${q.turn}`;

function focusSoon(id: string) {
  window.setTimeout(() => {
    const el = document.getElementById(id);
    el?.scrollIntoView?.({ block: 'nearest' });
    el?.focus({ preventScroll: true });
  }, 50);
}

const isBoard = (a: CaseQuestion['answer']): a is BoardAnswer =>
  !!a && Array.isArray((a as BoardAnswer).perspectives);

/**
 * An answer's opening, and the rest of it one click away: the rest of its text and, for the board, each agent's own
 * view, which stays in the page for a text search.
 */
function AnswerText({ text, views }: { text: string; views?: BoardAnswer['perspectives'] }) {
  const { lead, rest } = answerParts(text);
  return (
    <Stack gap={4}>
      <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>
        {lead}
      </Text>
      {rest || views?.length ? (
        <TechDetail kind="explain" label="Show the whole answer">
          <Stack gap={6}>
            {rest ? (
              <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>
                {rest}
              </Text>
            ) : null}
            {views?.length ? (
              <List size="sm" spacing={4} aria-label="Each agent's view">
                {views.map((p) => (
                  <List.Item key={p.member}>
                    <Text span fw={600} size="sm">
                      {MEMBER_NAMES[p.member] ?? keyLabel(p.member)}:
                    </Text>{' '}
                    {p.view}
                  </List.Item>
                ))}
              </List>
            ) : null}
          </Stack>
        </TechDetail>
      ) : null}
    </Stack>
  );
}

/** An answer's citations: evidence ids open the Evidence tab on that kind, W<n> moves to the What-if card. */
function Cites({ cites }: { cites: string[] }) {
  if (!cites.length) return null;
  return (
    <Group gap={8} wrap="wrap" align="center" className="ask-cites">
      <Text size="xs" c="dimmed">
        Cites
      </Text>
      {cites.map((c) => (
        <Badge
          key={c}
          size="sm"
          variant="outline"
          color="gray"
          component="button"
          type="button"
          className="ask-cite"
          onClick={() => (/^W\d+$/.test(c) ? focusSoon(`${WHATIF_ID}-title`) : showEvidence(c))}
          style={{ textTransform: 'none', cursor: 'pointer' }}
        >
          {/^W\d+$/.test(c)
            ? `What-if ${c}`
            : c.startsWith('catalogue:')
              ? `Catalogue ${c.slice(10)}`
              : keyLabel(c)}
        </Badge>
      ))}
    </Group>
  );
}

function Turn({ q }: { q: CaseQuestion }) {
  const a = q.answer;
  const settings = useSettings().data;
  // A question the live agents could not run (the budget, the provider refusing the key) says so in plain words
  const refused = q.state === 'failed' ? liveRefusalInText(q.error, settings) : null;
  return (
    <Box component="article" aria-labelledby={turnId(q)} className="ask-turn">
      <Stack gap="xs">
        <Group gap="xs" wrap="nowrap" align="flex-start" justify="space-between">
          <Title order={4} id={turnId(q)} tabIndex={-1}>
            {q.question}
          </Title>
          <Badge
            size="sm"
            variant="light"
            color={q.tier === 'board' ? 'blue' : 'gray'}
            style={{ textTransform: 'none', flexShrink: 0 }}
          >
            {tierLabel(q.tier)}
          </Badge>
        </Group>
        {isAnswering(q.state) ? (
          <Group gap="xs">
            <Loader size="xs" aria-hidden />
            <Text size="sm">
              {q.tier === 'board' ? 'The board is answering…' : 'The agent is answering…'}
            </Text>
          </Group>
        ) : q.state === 'answered' && a ? (
          <Stack gap="xs">
            <AnswerText text={a.answer} views={isBoard(a) ? a.perspectives : undefined} />
            {isBoard(a) && a.suggested_change ? (
              <Text size="sm">
                The board suggests a profile change
                {a.suggested_change.why ? ` (${a.suggested_change.why})` : ''}{' '}
                <Button variant="subtle" size="compact-sm" onClick={() => focusSoon(`${WHATIF_ID}-title`)}>
                  See it in What if
                </Button>
              </Text>
            ) : null}
            <Cites cites={a.cites} />
          </Stack>
        ) : refused ? (
          <LiveUnavailableNotice state={refused} variant="inline" />
        ) : (
          <Text size="sm" c="var(--mantine-color-red-text)">
            {q.state === 'schema_failed'
              ? `The answer was refused: ${q.error || 'it did not keep to the answer schema'}.`
              : `No answer: ${q.error || 'the run failed'}.`}
          </Text>
        )}
        <Text size="xs" c="dimmed">
          {tierLabel(q.tier)} tier. {provenanceText(q)}.
        </Text>
      </Stack>
    </Box>
  );
}

/**
 * Why a question was not asked. A suggested turn with no recording, asked by someone who may not spend the model budget,
 * is 409 no_recorded_answer: not a fault, so it reads as a note naming who can ask it live. In the trial nobody can,
 * so it steers to the suggested questions instead. A question refused because the live agents cannot run (409
 * live_unavailable or budget_exhausted) reads as the notice that says until when, and how to run them oneself.
 */
function AskError({ error }: { error: unknown }) {
  const settings = useSettings().data;
  const refused = liveRefusal(error, settings);
  if (refused) return <LiveUnavailableNotice state={refused} role="status" />;
  if (isApiError(error) && error.code === 'no_recorded_answer')
    return (
      <Alert color="blue" title="No recorded answer">
        {TRIAL
          ? TRIAL_NO_ANSWER
          : error.detail || 'This question has no recorded answer; a judge can ask it live.'}
      </Alert>
    );
  return <ErrorAlert error={error} title="The question was not asked" />;
}

/** Whether the person may ask in their own words, and if not, why; `trial` when the trial is the reason. */
interface FreeTextAccess {
  open: boolean;
  why: string;
  badge?: string;
  trial?: boolean;
}

/**
 * Whether the person may ask in their own words: a model key on a real instance, the operator role, and the right to
 * spend the day's model budget (the public demo's own user has it not, a judge has). The trial has no model, so there
 * the box shows, disabled, with its reason, and points to the suggested questions.
 */
function useFreeText(): FreeTextAccess {
  const me = useMe().data;
  const settings = useSettings();
  if (TRIAL) return { open: false, trial: true, why: 'Needs a real model: not in the trial.' };
  if (!me?.operator) return { open: false, why: 'Asking needs the operator role.' };
  if (me.can?.liveAgents === false)
    return {
      open: false,
      why: 'On the public demo, a question of your own is for a judge to ask live. Pick a suggested question above: its answers were recorded live.',
      badge: 'Judges only',
    };
  const s = settings.data;
  if (!s?.providerConfigured || s.mock)
    return {
      open: false,
      why: 'Free text needs a model key, and none is configured here. Pick a suggested question above.',
    };
  return { open: true, why: '' };
}

function FreeText({
  caseId,
  access,
  tier,
  conversation,
  onAsked,
}: {
  caseId: string;
  access: FreeTextAccess;
  tier: QuestionTier;
  conversation?: string;
  onAsked: (conversation: string, turn: number) => void;
}) {
  const ask = useAskQuestion(caseId);
  const [text, setText] = useState('');
  const unavailable = liveUnavailable(useSettings().data);
  // In the trial the box stays in sight, disabled, so the capability is seen and the reason is given
  if (access.trial)
    return (
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
    );
  if (!access.open)
    return (
      <Group className="ask-locked" justify="space-between" wrap="wrap" gap="xs" p="sm">
        <Text size="sm" c="dimmed" id="ask-free-locked" style={{ flex: '1 1 220px' }}>
          {access.why}
        </Text>
        <StatusBadge tone="neutral" label={access.badge ?? 'Locked: no key'} icon={IconLock} />
      </Group>
    );
  const cost = tier === 'board' ? 'about 0.40 USD' : 'about 0.05 to 0.10 USD';
  return (
    <Stack gap="xs">
      {/* While the live agents cannot run, a question of one's own would only be refused: the notice says why and until when */}
      {unavailable ? <LiveUnavailableNotice state={unavailable} /> : null}
      <Textarea
        label="Your own question"
        description={`Runs live with ${tierLabel(tier)}, ${cost} a question.${conversation ? ' It continues the conversation shown above.' : ''}`}
        autosize
        minRows={2}
        maxLength={2000}
        value={text}
        onChange={(e) => setText(e.currentTarget.value)}
      />
      {ask.isError ? <AskError error={ask.error} /> : null}
      <Group>
        <Button
          disabled={!text.trim() || !!unavailable}
          loading={ask.isPending}
          onClick={() =>
            ask.mutate(
              { ask: { tier, question: text.trim(), ...(conversation ? { conversation } : {}) } },
              {
                onSuccess: (r) => {
                  setText('');
                  onAsked(r.conversation, r.turn);
                },
              },
            )
          }
        >
          Ask
        </Button>
      </Group>
    </Stack>
  );
}

/**
 * Ask about this case: the read-only panel beside the case. Two tiers as tabs, each with the scenario's suggested
 * questions; the conversation shown (the recorded example first); the box for a question in one's own words, locked
 * without a key and saying so; and the What-if card. Nothing here writes to the case, the receiver or the profile.
 */
export function AskPanel({ caseId }: { caseId: string }) {
  const access = useFreeText();
  const suggested = useSuggestedQuestions(caseId);
  const questions = useCaseQuestions(caseId);
  const ask = useAskQuestion(caseId);
  const canAsk = !!useMe().data?.operator;
  const [tier, setTier] = useState<QuestionTier>('explain');
  const conversations = suggested.data?.conversations ?? [];
  const asked = questions.data?.items ?? [];
  const [chosen, setChosen] = useState<string>();
  // The example conversation is shown first: the scenario's first one, else the first asked here
  const shown = chosen ?? conversations[0]?.id ?? asked[0]?.conversation;
  const askedTurn = (conversation: string, turn: number) =>
    asked.filter((q) => q.conversation === conversation && q.turn === turn).at(-1);
  // A chip is linked to its stored question by the suggested route's `asked`; a refused or failed one can be asked again
  const chipAsked = (conversation: string, t: SuggestedTurn) =>
    t.asked && t.asked.state !== 'failed' && t.asked.state !== 'schema_failed'
      ? (asked.find((q) => q.questionId === t.asked?.questionId) ?? askedTurn(conversation, t.turn))
      : undefined;

  // Each turn shows its newest question: asking a refused or failed turn again replaces it
  const thread = asked
    .filter((q) => q.conversation === shown && askedTurn(q.conversation, q.turn)?.questionId === q.questionId)
    .sort((a, b) => a.turn - b.turn);

  // After asking, focus moves to the new turn's heading once the list has it and the conversation is shown
  const pending = useRef<string | undefined>(undefined);
  const [asks, setAsks] = useState(0);
  useEffect(() => {
    if (pending.current && document.getElementById(pending.current)) {
      focusSoon(pending.current);
      pending.current = undefined;
    }
  }, [questions.data, asks]);

  const onAsked = (conversation: string, turn: number) => {
    pending.current = turnId({ conversation, turn });
    setChosen(conversation);
    setAsks((n) => n + 1);
  };

  const choose = (conversation: string, t: SuggestedTurn) => {
    setChosen(conversation);
    if (chipAsked(conversation, t)) {
      focusSoon(turnId({ conversation, turn: t.turn }));
      return;
    }
    ask.mutate(
      { ask: { tier: t.tier, suggested: { conversation, turn: t.turn } } },
      { onSuccess: (r) => onAsked(r.conversation, r.turn) },
    );
  };

  // A follow-up turn is offered once the turn before it has been asked here
  const chips = (forTier: QuestionTier) =>
    conversations.flatMap((c) =>
      c.turns
        .filter(
          (t) =>
            t.tier === forTier &&
            (t.turn === 1 || c.turns.some((p) => p.turn === t.turn - 1 && !!chipAsked(c.id, p))),
        )
        .map((t) => ({ conversation: c.id, t })),
    );

  const example = shown === conversations[0]?.id && thread.length > 0;
  const head = thread[0];
  const badge = answersBadge(asked);

  return (
    <Stack gap="lg">
      {/* The read-only note, quietly: a line under the heading, not a box */}
      <Group gap="xs" wrap="nowrap" align="flex-start" className="ask-note">
        <IconEye size={16} aria-hidden className="ask-note-icon" />
        <Text size="sm" c="dimmed">
          <Text span fw={600} inherit>
            Read-only.
          </Text>{' '}
          Answers explain this case. They never write to the receiver, change the case or save a setting.
        </Text>
      </Group>
      <Tabs value={tier} onChange={(v) => v && setTier(v as QuestionTier)}>
        <Text size="sm" fw={600} id="ask-tiers-label" mb="xs">
          How deep to ask
        </Text>
        <Tabs.List grow aria-labelledby="ask-tiers-label" style={{ gap: 'var(--mantine-spacing-sm)' }}>
          {TIERS.map((t) => (
            <Tabs.Tab key={t.value} value={t.value} className="ask-tier">
              <Stack gap={0} align="flex-start">
                <Text fw={600} size="sm">
                  {t.label}
                </Text>
                <Text size="xs">{t.hint}</Text>
              </Stack>
            </Tabs.Tab>
          ))}
        </Tabs.List>
        {TIERS.map((t) => (
          <Tabs.Panel key={t.value} value={t.value} pt="lg">
            <Stack gap="sm">
              <Group gap="xs">
                <Text size="sm" fw={600} id={`ask-chips-${t.value}`}>
                  Suggested questions
                </Text>
                {conversations.length && badge ? (
                  <Badge size="sm" variant="light" color="gray" style={{ textTransform: 'none' }}>
                    {badge}
                  </Badge>
                ) : null}
              </Group>
              {suggested.isError ? (
                <ErrorAlert
                  error={suggested.error}
                  title="The suggested questions could not be read"
                  onRetry={() => void suggested.refetch()}
                />
              ) : suggested.isPending ? (
                <Loader size="xs" aria-label="Loading the suggested questions" />
              ) : chips(t.value).length ? (
                <Group gap="sm" role="group" aria-labelledby={`ask-chips-${t.value}`}>
                  {chips(t.value).map(({ conversation, t: turn }) => {
                    const done = !!chipAsked(conversation, turn);
                    const current = done && conversation === shown;
                    return (
                      <Button
                        key={`${conversation}.${turn.turn}`}
                        size="sm"
                        radius="xl"
                        variant={current ? 'filled' : 'default'}
                        disabled={!canAsk && !done}
                        loading={
                          ask.isPending &&
                          ask.variables?.ask.suggested?.conversation === conversation &&
                          ask.variables.ask.suggested.turn === turn.turn
                        }
                        leftSection={done ? <IconCheck size={14} aria-hidden /> : undefined}
                        onClick={() => choose(conversation, turn)}
                        className="wrap-button ask-chip"
                      >
                        {turn.text}
                        {done ? (
                          <VisuallyHidden>
                            {current ? ' (answered, shown below)' : ' (answered)'}
                          </VisuallyHidden>
                        ) : null}
                      </Button>
                    );
                  })}
                </Group>
              ) : (
                <Text size="sm" c="dimmed">
                  {conversations.length
                    ? `No more suggested questions for ${t.label}.`
                    : "This case's scenario has no suggested questions yet."}
                </Text>
              )}
              {!canAsk ? (
                <Text size="xs" c="dimmed">
                  Asking needs the operator role; the answers already given are shown.
                </Text>
              ) : null}
            </Stack>
          </Tabs.Panel>
        ))}
      </Tabs>
      {ask.isError ? <AskError error={ask.error} /> : null}
      <div aria-live="polite">
        {questions.isError ? (
          <ErrorAlert
            error={questions.error}
            title="The answers could not be read"
            onRetry={() => void questions.refetch()}
          />
        ) : thread.length ? (
          <Stack
            gap="md"
            component="section"
            aria-labelledby="ask-thread-title"
            className="ask-thread"
            p="md"
          >
            <Stack gap={4}>
              <Group gap="xs">
                <IconMessageQuestion size={16} aria-hidden />
                <Title order={3} id="ask-thread-title">
                  {example ? 'Example conversation' : 'Conversation'}
                </Title>
              </Group>
              {head ? (
                <Text size="xs" c="dimmed">
                  {provenanceText(head)}.
                  {!access.open && !access.trial ? ' With an API key you can ask your own questions.' : ''}
                </Text>
              ) : null}
            </Stack>
            {thread.map((q) => (
              <Turn key={q.questionId} q={q} />
            ))}
          </Stack>
        ) : null}
      </div>
      <FreeText
        caseId={caseId}
        access={access}
        tier={tier}
        conversation={shown && thread.length ? shown : undefined}
        onAsked={onAsked}
      />
      <WhatIfCard caseId={caseId} named={namedFact(thread)} />
    </Stack>
  );
}

/** The fact the latest board answer of the conversation names as its suggested change. */
function namedFact(thread: CaseQuestion[]): string | undefined {
  for (let i = thread.length - 1; i >= 0; i--) {
    const a = thread[i].answer;
    if (isBoard(a) && a.suggested_change) return a.suggested_change.fact;
  }
  return undefined;
}
