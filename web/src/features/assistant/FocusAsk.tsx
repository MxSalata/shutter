import { Box, Button, Group, Loader, Stack, Text, Title } from '@mantine/core';
import { IconLock } from '@tabler/icons-react';
import { useEffect, useRef } from 'react';
import { isAnswering, useAskPageQuestion, usePageQuestion, useSettings } from '@/api/hooks';
import { LiveUnavailableNotice } from '@/components/LiveUnavailableNotice';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { liveUnavailable } from '@/lib/liveAgents';
import { MAIN_ID } from '@/features/shell/SkipLink';
import { focusSoon } from '@/features/cases/ask/AskPanel';
import { NO_ASKED, usePageAccess } from './access';
import { AskError, Turn } from './PageChat';
import { summariseScreen, withFocus } from './screen';
import { useAssistant, type PageFocus } from './store';

/** What asking does, where a live answer can be given: the person chooses, nothing reaches the profile, the run is kept. */
export const FOCUS_NOTE_LIVE =
  "You choose this answer; Ask Shutter explains it. Asking changes nothing in the profile. Live questions and the agent's trace are logged.";

/** The same where no live answer is given: nothing is sent, so nothing is logged. */
export const FOCUS_NOTE = 'You choose this answer. Nothing here changes the profile.';

/** The written explanation's name, open where no live answer is given and one click away under a live one. */
export const WRITTEN_LABEL = 'Written explanation';

/** The element the region beside a question is marked with, which the summary of the screen leaves out (screen.ts). */
export const ASK_INLINE_ATTR = 'data-ask-inline';

/**
 * One of a page's questions, asked about from its "Ask Shutter about this": in the panel beside the page (`inline` false),
 * or under the question itself below the wide breakpoint, where the panel would cover the form. It shows the answer on the
 * page and what it does there in the page's own words (the panel only: inline they sit just below), says the person
 * chooses and nothing is saved, and asks the question once for the reader where a live answer can be given, through the
 * page question route (CONTRACTS 14.6) with the question in the summary (`withFocus`). The answer is the panel's own turn,
 * attributed to the agent that gave it. Where no live answer is given (the trial, a role without the live agents, no
 * model key, the budget or share spent, a refusal) the written explanation stands open instead; under a live answer it is
 * one click away. Nothing here writes to the page's draft.
 */
export function FocusAsk({ focus, inline = false }: { focus: PageFocus; inline?: boolean }) {
  const access = usePageAccess();
  const settings = useSettings().data;
  const unavailable = access.free ? liveUnavailable(settings) : null;
  const live = access.ready && access.open && access.free && !unavailable;
  const asked = useAssistant((s) => s.threads[focus.page]) ?? NO_ASKED;
  const addAsked = useAssistant((s) => s.addAsked);
  const ask = useAskPageQuestion();
  const mine = asked.find((a) => a.question === focus.question);
  const answer = usePageQuestion(mine?.questionId);
  const state = answer.data?.state;
  // A refusal of the last question sent from here shows while that is still the question on the page: a changed answer
  // is a new question, offered with its own button
  const sentThis = ask.variables?.ask.question === focus.question;
  const askFailed = ask.isError && sentThis;
  const failed = askFailed || answer.isError || (!!state && !isAnswering(state) && state !== 'answered');
  const headingId = `ask-focus-${focus.id}${inline ? '-inline' : ''}`;

  const send = () => {
    const root = document.getElementById(MAIN_ID) ?? document.body;
    const question = focus.question;
    ask.mutate(
      { ask: { page: focus.page, question, context: withFocus(summariseScreen(root, focus.page), focus) } },
      { onSuccess: (r) => addAsked(focus.page, { questionId: r.questionId, question }) },
    );
  };

  // Asked for the reader once, as the button was pressed, when a live answer can be given and it was not asked before in
  // this tab; an answer changed afterwards is asked about only with the button below
  const autoAsked = useRef(false);
  useEffect(() => {
    if (autoAsked.current || !access.ready) return;
    autoAsked.current = true;
    if (live && !mine) queueMicrotask(send);
  });

  // In the panel the question's heading takes focus, so a reader there hears which question it is about
  useEffect(() => {
    if (!inline) focusSoon(headingId);
  }, [inline, headingId]);

  const written = <Text size="sm">{focus.written}</Text>;
  return (
    <Box
      component="section"
      aria-labelledby={headingId}
      className="ask-focus"
      p="md"
      {...(inline ? { [ASK_INLINE_ATTR]: '' } : {})}
    >
      <Stack gap="sm">
        {inline ? (
          <Text fw={600} size="sm" id={headingId}>
            Ask Shutter: {focus.title}
          </Text>
        ) : (
          <Title order={3} id={headingId} tabIndex={-1}>
            {focus.title}
          </Title>
        )}
        {inline ? null : (
          <Stack gap={2}>
            <Text size="sm">
              <Text span fw={600} inherit>
                On the page:
              </Text>{' '}
              {focus.answer}
            </Text>
            <Text size="sm">
              <Text span fw={600} inherit>
                What it does:
              </Text>{' '}
              {focus.consequence}
            </Text>
          </Stack>
        )}
        <Text size="sm" c="dimmed">
          {live ? FOCUS_NOTE_LIVE : FOCUS_NOTE}
        </Text>
        {!access.ready ? (
          <Loader size="xs" aria-label="Reading whether a live answer can be given" />
        ) : live ? (
          <div aria-live="polite">
            {mine ? (
              <Turn questionId={mine.questionId} question={mine.question} order={inline ? 3 : 4} />
            ) : ask.isPending ? (
              <Group gap="xs">
                <Loader size="xs" aria-hidden />
                <Text size="sm">Asking the agent…</Text>
              </Group>
            ) : askFailed ? (
              <AskError error={ask.error} />
            ) : (
              <Group>
                <Button size="sm" variant="light" onClick={send}>
                  Ask about this answer
                </Button>
              </Group>
            )}
          </div>
        ) : unavailable ? (
          <LiveUnavailableNotice state={unavailable} variant="inline" />
        ) : (
          <Group className="ask-locked" justify="space-between" wrap="wrap" gap="xs" p="sm">
            <Text size="sm" c="dimmed" style={{ flex: '1 1 200px' }}>
              {access.short}
            </Text>
            <StatusBadge tone="neutral" label={access.badge ?? 'No live answer'} icon={IconLock} />
          </Group>
        )}
        {live && !failed ? (
          <TechDetail kind="explain" label={WRITTEN_LABEL}>
            {written}
          </TechDetail>
        ) : (
          <Stack gap={4}>
            <Text size="sm" fw={600}>
              {WRITTEN_LABEL}
            </Text>
            {written}
          </Stack>
        )}
      </Stack>
    </Box>
  );
}
