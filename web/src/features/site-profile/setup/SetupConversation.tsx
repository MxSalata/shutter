import { Button, Group, List, Loader, Paper, Stack, Text, Title, VisuallyHidden } from '@mantine/core';
import { lazy, Suspense, useState, type ReactNode } from 'react';
import { FoldToggle } from '../controls';
import { AnswerCard } from './AnswerCard';
import { ASK_HERE_ID, SUMMARY_TITLE_ID, cardTitleId, focusLater } from './cards';
import { effectsOf } from './effects';
import { QUESTIONS, SETUP_PAGE, answerText, holdsAnswer, type QuestionId } from './fields';
import {
  inForce,
  nextQuestion,
  receiverOf,
  statusOf,
  unansweredOf,
  useSetup,
  type ReviewStop,
} from './setupStore';

// Ask Shutter about the page itself: the suggested questions and a question of one's own, loaded when first opened
const PageChat = lazy(() => import('@/features/assistant/PageChat').then((m) => ({ default: m.PageChat })));

/**
 * The conversation pane for one receiver: the checklist's questions as cards, the one being answered open with the
 * page's own control, the ones answered closed with their answer in a line; then the summary, once every question is
 * answered or left; then Ask Shutter about the page. A receiver being added shows its questions one at a time; a
 * receiver in force shows them all, each with the answer in force. The page owns the list, its order and what counts as
 * answered: nothing here takes a value from a model.
 */
export function SetupConversation({
  rid,
  openId,
  setOpenId,
  stop,
  onReview,
  onAnother,
  onDiscard,
  foot,
}: {
  rid: string;
  /** The card a person opened, or null for the next unanswered question. */
  openId: QuestionId | null;
  setOpenId: (q: QuestionId | null) => void;
  /** What the last review refused about this receiver, shown on its question's control. */
  stop: ReviewStop | null;
  onReview: () => void;
  onAnother: () => void;
  onDiscard: () => void;
  /** What follows the cards: Ask Shutter about the page. */
  foot?: ReactNode;
}) {
  const s = useSetup();
  // The one card whose "Why does this matter?" is open
  const [why, setWhy] = useState<QuestionId | null>(null);
  const toggleWhy = (q: QuestionId) => setWhy((w) => (w === q ? null : q));
  const [said, setSaid] = useState('');
  const r = receiverOf(s, rid);
  if (!r || !s.draft || !s.base) return null;
  const draft = s.draft;
  const existing = inForce(s, rid);
  const next = nextQuestion(s, rid);
  const current = openId ?? next?.id ?? null;
  const shown = QUESTIONS.filter((q) => existing || q.id === current || statusOf(s, rid, q) !== 'unanswered');
  const toGo = QUESTIONS.length - shown.length;
  const name = r.name.trim() || 'the receiver being added';

  /** On from a card: the next unanswered question, or the summary when none is left. */
  const moveOn = (from: QuestionId) => {
    setOpenId(null);
    const after = nextQuestion(useSetup.getState(), rid);
    if (after && after.id !== from) {
      setSaid(`Next: ${after.text}`);
      focusLater(cardTitleId(after.id));
    } else {
      setSaid('Every question is answered or left. The summary follows.');
      focusLater(SUMMARY_TITLE_ID);
    }
  };

  return (
    <Stack gap="md">
      <VisuallyHidden aria-live="polite">{said}</VisuallyHidden>
      {shown.map((q) => {
        const status = statusOf(s, rid, q);
        const answered = holdsAnswer(q, r);
        return (
          <AnswerCard
            key={q.id}
            q={q}
            r={r}
            profile={draft}
            status={status}
            version={s.base!.version}
            open={q.id === current}
            fixedName={existing}
            error={stop?.rid === rid && stop.question === q.id ? stop.message : undefined}
            whyOpen={why === q.id}
            set={(key, value) => {
              setOpenId(q.id);
              s.setKey(rid, key, value);
            }}
            onOpen={() => {
              setOpenId(q.id);
              focusLater(cardTitleId(q.id));
            }}
            nextLabel={
              !answered
                ? undefined
                : QUESTIONS.some((x) => x.id !== q.id && statusOf(s, rid, x) === 'unanswered')
                  ? 'Next question'
                  : 'Done'
            }
            onNext={() => moveOn(q.id)}
            onLeave={
              answered || existing
                ? undefined
                : () => {
                    s.leave(rid, q.id);
                    moveOn(q.id);
                  }
            }
            onWhy={() => toggleWhy(q.id)}
          />
        );
      })}
      {toGo > 0 ? (
        <Text size="sm" c="dimmed">
          {toGo === 1 ? '1 more question follows.' : `${toGo} more questions follow.`}
        </Text>
      ) : null}
      {!next ? (
        <Paper
          component="section"
          aria-labelledby={SUMMARY_TITLE_ID}
          withBorder
          p="md"
          className="setup-card"
        >
          <Stack gap="sm">
            <Title order={3} size="h4" id={SUMMARY_TITLE_ID} tabIndex={-1}>
              Summary: {name}
            </Title>
            <List size="sm" spacing={2} aria-label="The receiver as drafted">
              {QUESTIONS.filter((q) => holdsAnswer(q, r)).map((q) => (
                <List.Item key={q.id}>
                  {q.short}: {answerText(q, r)}
                </List.Item>
              ))}
            </List>
            <Text size="sm" fw={600}>
              What Shutter will do here
            </Text>
            <List size="sm" spacing={2} aria-label="What Shutter will do here, in short">
              {effectsOf(draft, r)
                .filter((l) => l.id === 'overtaken' || l.id === 'case_write' || l.id === 'mode')
                .map((l) => (
                  <List.Item key={l.id}>
                    {l.label}: {l.text}
                  </List.Item>
                ))}
            </List>
            {unansweredOf(s, rid).length ? (
              <>
                <Text size="sm" fw={600}>
                  Not answered
                </Text>
                <List size="sm" spacing={2} aria-label="Not answered">
                  {unansweredOf(s, rid).map((q) => (
                    <List.Item key={q.id}>
                      {q.short}. {q.unanswered}
                    </List.Item>
                  ))}
                </List>
              </>
            ) : null}
            <Group gap="sm" wrap="wrap">
              <Button onClick={onReview}>Review and save…</Button>
              <Button variant="default" onClick={onAnother}>
                Set up another receiver
              </Button>
              <Button variant="default" onClick={onDiscard}>
                Discard the draft
              </Button>
            </Group>
          </Stack>
        </Paper>
      ) : null}
      {foot}
    </Stack>
  );
}

/**
 * Ask Shutter about the page itself, in the page: the suggested questions and, where a live answer can be given, a
 * question of one's own, through the page question route. The header's Ask Shutter button opens it here, so the page
 * never has a panel beside its two panes. Marked so the summary of the screen leaves its own words out.
 */
export function AskHere({ open, setOpen }: { open: boolean; setOpen: (open: boolean) => void }) {
  return (
    <div data-ask-inline="">
      <FoldToggle open={open} onToggle={() => setOpen(!open)} controls={ASK_HERE_ID}>
        Ask Shutter about this page
      </FoldToggle>
      {open ? (
        <Paper
          component="section"
          id={ASK_HERE_ID}
          withBorder
          p="md"
          mt="xs"
          tabIndex={-1}
          aria-label="Ask Shutter about this page"
        >
          <Suspense fallback={<Loader size="sm" aria-label="Opening Ask Shutter" />}>
            <PageChat page={SETUP_PAGE} />
          </Suspense>
        </Paper>
      ) : (
        <div id={ASK_HERE_ID} hidden />
      )}
    </div>
  );
}
