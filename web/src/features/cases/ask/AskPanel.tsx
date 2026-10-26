import {
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
import { IconCheck, IconLock, IconMessageQuestion } from '@tabler/icons-react';
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
import { StatusBadge } from '@/components/StatusBadge';
import { DEMO } from '@/demo';
import { keyLabel } from '@/lib/format';
import { showEvidence } from '../case/evidenceLinks';
import { MEMBER_NAMES, TIERS, answersBadge, provenanceText, tierLabel } from './labels';
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

/** An answer's citations: evidence ids open the Evidence tab on that kind, W<n> moves to the What-if card. */
function Cites({ cites }: { cites: string[] }) {
  if (!cites.length) return null;
  return (
    <Group gap={4} wrap="wrap">
      <Text size="xs" c="dimmed">
        Cites
      </Text>
      {cites.map((c) => (
        <Badge
          key={c}
          size="xs"
          variant="outline"
          color="gray"
          component="button"
          type="button"
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
  return (
    <Box component="article" aria-labelledby={turnId(q)} className="ask-turn">
      <Stack gap={6}>
        <Group gap="xs" wrap="nowrap" align="flex-start" justify="space-between">
          <Title order={4} fz="sm" id={turnId(q)} tabIndex={-1}>
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
          <Stack gap={6}>
            <Text size="sm" style={{ whiteSpace: 'pre-wrap' }}>
              {a.answer}
            </Text>
            {isBoard(a) && a.perspectives.length ? (
              <List size="sm" spacing={4}>
                {a.perspectives.map((p) => (
                  <List.Item key={p.member}>
                    <Text span fw={600} size="sm">
                      {MEMBER_NAMES[p.member] ?? keyLabel(p.member)}:
                    </Text>{' '}
                    {p.view}
                  </List.Item>
                ))}
              </List>
            ) : null}
            {isBoard(a) && a.suggested_change ? (
              <Text size="sm">
                The board suggests a profile change ({a.suggested_change.why}){' '}
                <Button variant="subtle" size="compact-sm" onClick={() => focusSoon(`${WHATIF_ID}-title`)}>
                  See it in What if
                </Button>
              </Text>
            ) : null}
            <Cites cites={a.cites} />
          </Stack>
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

/** Whether the person may ask in their own words: a model key on a real instance, and the operator role. */
function useFreeText() {
  const me = useMe().data;
  const settings = useSettings();
  if (!me?.operator) return { open: false, why: 'Asking needs the operator role.' };
  if (DEMO)
    return {
      open: false,
      why: 'Free text needs a model key. In this demo, pick a suggested question above.',
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
  access: { open: boolean; why: string };
  tier: QuestionTier;
  conversation?: string;
  onAsked: (conversation: string, turn: number) => void;
}) {
  const ask = useAskQuestion(caseId);
  const [text, setText] = useState('');
  if (!access.open)
    return (
      <Group className="ask-locked" justify="space-between" wrap="wrap" gap="xs" p="sm">
        <Text size="sm" c="dimmed" id="ask-free-locked" style={{ flex: '1 1 220px' }}>
          {access.why}
        </Text>
        <StatusBadge tone="neutral" label="Locked: no key" icon={IconLock} />
      </Group>
    );
  const cost = tier === 'board' ? 'about 0.40 USD' : 'about 0.05 to 0.10 USD';
  return (
    <Stack gap="xs">
      <Textarea
        label="Your own question"
        description={`Runs live with ${tierLabel(tier)}, ${cost} a question.${conversation ? ' It continues the conversation shown above.' : ''}`}
        autosize
        minRows={2}
        maxLength={500}
        value={text}
        onChange={(e) => setText(e.currentTarget.value)}
      />
      {ask.isError ? <ErrorAlert error={ask.error} title="The question was not asked" /> : null}
      <Group>
        <Button
          disabled={!text.trim()}
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
  const thread = asked.filter((q) => q.conversation === shown).sort((a, b) => a.turn - b.turn);
  const askedTurn = (conversation: string, turn: number) =>
    asked.find((q) => q.conversation === conversation && q.turn === turn);

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
    if (askedTurn(conversation, t.turn)) {
      focusSoon(turnId({ conversation, turn: t.turn }));
      return;
    }
    ask.mutate(
      {
        ask: {
          tier: t.tier,
          suggested: { conversation, turn: t.turn },
          ...(t.turn > 1 ? { conversation } : {}),
        },
      },
      { onSuccess: (r) => onAsked(r.conversation, r.turn) },
    );
  };

  // A follow-up turn is offered once the turn before it has been asked here
  const chips = (forTier: QuestionTier) =>
    conversations.flatMap((c) =>
      c.turns
        .filter((t) => t.tier === forTier && (t.turn === 1 || !!askedTurn(c.id, t.turn - 1)))
        .map((t) => ({ conversation: c.id, t })),
    );

  const thisTurnAsked = (conversation: string, turn: number) => !!askedTurn(conversation, turn);
  const example = shown === conversations[0]?.id && thread.length > 0;
  const head = thread[0];
  const badge = answersBadge(asked);

  return (
    <Stack gap="md">
      <Text size="sm" className="ask-readonly" p="sm">
        <Text span fw={700}>
          Read-only.
        </Text>{' '}
        Answers explain this case. They never write to the receiver, change the case or save a setting.
      </Text>
      <Tabs value={tier} onChange={(v) => v && setTier(v as QuestionTier)}>
        <Tabs.List grow aria-label="How deep to ask" style={{ gap: 'var(--mantine-spacing-xs)' }}>
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
          <Tabs.Panel key={t.value} value={t.value} pt="sm">
            <Stack gap="xs">
              <Group gap="xs">
                <Text size="xs" c="dimmed" id={`ask-chips-${t.value}`}>
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
                <Group gap="xs" role="group" aria-labelledby={`ask-chips-${t.value}`}>
                  {chips(t.value).map(({ conversation, t: turn }) => {
                    const done = thisTurnAsked(conversation, turn.turn);
                    const current = done && conversation === shown;
                    return (
                      <Button
                        key={`${conversation}.${turn.turn}`}
                        size="xs"
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
                        className="wrap-button"
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
      {ask.isError ? <ErrorAlert error={ask.error} title="The question was not asked" /> : null}
      <div aria-live="polite">
        {questions.isError ? (
          <ErrorAlert
            error={questions.error}
            title="The answers could not be read"
            onRetry={() => void questions.refetch()}
          />
        ) : thread.length ? (
          <Stack
            gap="sm"
            component="section"
            aria-labelledby="ask-thread-title"
            className="ask-thread"
            p="sm"
          >
            <Stack gap={2}>
              <Group gap="xs">
                <IconMessageQuestion size={16} aria-hidden />
                <Title order={3} fz="sm" id="ask-thread-title">
                  {example ? 'Example conversation' : 'Conversation'}
                </Title>
              </Group>
              {head ? (
                <Text size="xs" c="dimmed">
                  {provenanceText(head)}.
                  {!access.open ? ' With an API key you can ask your own questions.' : ''}
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
