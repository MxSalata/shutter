import { Alert, Button, Group, Loader, Stack, Text, Textarea } from '@mantine/core';
import { useState } from 'react';
import { useSettings } from '@/api/hooks';
import { useSendSetupTurn } from '@/api/setupHooks';
import type { SiteReceiver } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { LiveUnavailableNotice } from '@/components/LiveUnavailableNotice';
import { PortalLink } from '@/components/PortalLink';
import { TRIAL } from '@/env/mode';
import { isApiError } from '@/lib/errors';
import { liveRefusal } from '@/lib/liveAgents';
import { withHeaderClass } from '@/lib/messageLink';
import { DRAFTING_OFF, TYPED_NOTE, type Drafting } from './drafting';
import { QUESTIONS, type SetupQuestion } from './fields';
import { MAX_TEXT, cleanText, nameProblem } from './proposals';
import { useSetup, type TurnEntry } from './setupStore';

/** How many typed answers may draft nothing for one question before the card asks for its control instead. */
const MAX_MISSES = 2;

/** Why a typed answer was not sent, as the route refuses it (CONTRACTS 14.7). */
function SendError({ error }: { error: unknown }) {
  const settings = useSettings().data;
  const refused = liveRefusal(error, settings);
  if (refused) return <LiveUnavailableNotice state={refused} role="status" />;
  const code = isApiError(error) ? error.code : '';
  if (code === 'setup_drafting_off')
    return (
      <Alert color="blue" title="Switched off for this site">
        {DRAFTING_OFF} Choose with the control above.
      </Alert>
    );
  if (code === 'live_agents_only')
    return (
      <Alert color="blue" title="Judges only">
        Typed answers are read live only, and that needs the judges&apos; account. Choose with the control
        above.
      </Alert>
    );
  if (code === 'no_model')
    return (
      <Alert color="blue" title="No model answers here">
        Reading typed answers needs a model key, and none is configured here. Choose with the control above.
      </Alert>
    );
  if (code === 'turn_pending')
    return (
      <Alert color="blue" title="One answer at a time">
        Ask Shutter is still reading an earlier answer of this conversation.
      </Alert>
    );
  if (code === 'conversation_full')
    return (
      <Alert color="blue" title="This conversation is full">
        A conversation takes 24 typed answers. Go on with the controls, or discard the draft to start another.
      </Alert>
    );
  if (code === 'stale_version')
    return (
      <Alert color="yellow" title="The stored profile has changed">
        Another version was saved while this draft was being made, so nothing was sent.
      </Alert>
    );
  return <ErrorAlert error={error} title="The answer was not sent" />;
}

/** The agent that reads a typed answer, as an exchange names it. */
const SETUP_AGENT = 'the Set-up guide agent on IRIS AI Hub';

/**
 * Who read a typed answer, in a sentence, with the run's message in the Management Portal: the agent's request and its
 * answer, linked as a page question's run is (the server's `messageLink`, under the portal path of the namespace the
 * agent ran in), or named unlinked when no link came. Under the API mimic no model was called, and the line says so.
 */
function ReadBy({ turn }: { turn: TurnEntry }) {
  if (turn.state === 'reading' || turn.state === 'cancelled' || (!turn.model && !turn.run)) return null;
  return (
    <Text size="xs" c="dimmed">
      {turn.model === 'mock'
        ? 'Read by the API mimic: no model was called.'
        : turn.model
          ? `Read live by ${SETUP_AGENT}, with ${turn.model}.`
          : `Read live by ${SETUP_AGENT}.`}
      {!TRIAL && turn.run ? (
        turn.link ? (
          <>
            {' Its run is '}
            <PortalLink
              href={withHeaderClass(turn.link)}
              what={`message ${turn.run}, the agent's request and answer`}
              size="xs"
            >
              message {turn.run}
            </PortalLink>
            {' in the Management Portal.'}
          </>
        ) : (
          ` Its run is message ${turn.run} in the Management Portal.`
        )
      ) : null}
    </Text>
  );
}

/** One exchange under a question's card: what the person typed, then what came of it. */
function Exchange({ turn, onCancel }: { turn: TurnEntry; onCancel: () => void }) {
  const undo = useSetup((s) => s.undo);
  const drafted = (turn.drafted ?? [])
    .map((d) => QUESTIONS.find((q) => (q.keys as string[]).includes(d.key))?.short ?? d.key)
    .join(', ');
  return (
    <Stack gap={4} component="li" className="setup-exchange" data-turn={turn.id} data-state={turn.state}>
      <Text size="sm" style={{ overflowWrap: 'anywhere' }}>
        <Text span fw={600} inherit>
          You:
        </Text>{' '}
        {turn.text}
      </Text>
      {turn.state === 'reading' ? (
        <Group gap="xs" wrap="wrap">
          <Loader size="xs" aria-hidden />
          <Text size="sm">Ask Shutter is reading your answer…</Text>
          <Button size="compact-sm" variant="default" onClick={onCancel}>
            Cancel
          </Button>
        </Group>
      ) : null}
      {turn.say ? (
        <Text size="sm" style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
          <Text span fw={600} inherit>
            Ask Shutter:
          </Text>{' '}
          {turn.say}
        </Text>
      ) : null}
      {turn.state === 'used' ? (
        <Group gap="xs" wrap="wrap">
          <Text size="sm">
            {turn.undone
              ? `Undone: ${drafted}.`
              : `Drafted: ${drafted}. It is in the draft, marked as drafted.`}
          </Text>
          {turn.undone ? null : (
            <Button
              size="compact-sm"
              variant="default"
              aria-label={`Undo what Ask Shutter drafted: ${drafted}`}
              onClick={() => undo(turn.id)}
            >
              Undo
            </Button>
          )}
        </Group>
      ) : null}
      {turn.state === 'nothing' ? <Text size="sm">Nothing was drafted.</Text> : null}
      {turn.state === 'unused' || turn.state === 'cancelled' ? <Text size="sm">{turn.note}</Text> : null}
      {turn.state === 'failed' ? (
        <Text size="sm">
          Ask Shutter&apos;s reading was not used: {turn.note}. Choose here instead, with the control above.
        </Text>
      ) : null}
      <ReadBy turn={turn} />
    </Stack>
  );
}

/**
 * "Or answer in your own words", on the card of a question Ask Shutter may draft (CONTRACTS 14.7): a box for what the
 * person wants to say about the receiver, and under it each exchange of this card. The text is checked here before it
 * is sent (a link, an address, a long number or the shape of a credential is refused, and nothing leaves the page); it
 * goes with the draft to the turn route, which stores no profile. What comes back enters the draft only through the
 * store's own re-check (`settle`), marked as drafted, with Undo. Where a typed answer cannot be sent the box is absent,
 * and the card's control answers as it always does.
 */
export function OwnWords({
  q,
  r,
  rid,
  drafting,
}: {
  q: SetupQuestion;
  r: SiteReceiver;
  rid: string;
  drafting: Drafting;
}) {
  const s = useSetup();
  const send = useSendSetupTurn();
  // What is typed lives in the draft's store, so it outlives the page's two layouts; nothing of it is sent until Send
  const text = s.typed[`${rid}/${q.id}`] ?? '';
  const setText = (value: string) => s.type(rid, q.id, value);
  const [problem, setProblem] = useState('');
  const misses = s.misses[`${rid}/${q.id}`] ?? 0;
  const busy = !!s.pending || send.isPending;
  const submit = () => {
    const state = useSetup.getState();
    const clean = cleanText(text);
    if (clean.problem) return setProblem(clean.problem);
    // The agent drafts for the receiver by its name: a name that fails the same rule is not sent either
    const named = nameProblem(r.name);
    if (named) return setProblem(named);
    if (!state.draft || !state.base) return;
    setProblem('');
    // The draft this is sent from: an answer that comes back after a discard or a sign-out is not taken into another
    const epoch = state.epoch;
    send.mutate(
      {
        turn: {
          ...(state.conversation ? { conversation: state.conversation } : {}),
          receiver: r.name,
          text: clean.text,
          draft: state.draft,
          baseVersion: state.base.version,
          draftRevision: state.revision,
        },
      },
      {
        onSuccess: (asked) => {
          useSetup.getState().type(rid, q.id, '');
          useSetup.getState().sent(rid, q.id, clean.text, asked, epoch);
        },
      },
    );
  };
  if (!drafting.can && !send.isError) return null;
  return (
    <Stack gap="xs" data-own-words={q.id}>
      {!drafting.can ? null : misses >= MAX_MISSES ? (
        <Text size="sm">
          Choose here instead, with the control above: Ask Shutter could not read an answer to this question
          from what you typed.
        </Text>
      ) : (
        <>
          <Textarea
            label="Or answer in your own words"
            description={TYPED_NOTE}
            autosize
            minRows={2}
            maxLength={MAX_TEXT}
            value={text}
            disabled={busy}
            onChange={(e) => {
              setText(e.currentTarget.value);
              setProblem('');
            }}
            error={problem || undefined}
          />
          <Group gap="sm">
            <Button
              size="sm"
              variant="light"
              disabled={!text.trim() || busy}
              loading={send.isPending}
              onClick={submit}
            >
              Send to Ask Shutter
            </Button>
          </Group>
        </>
      )}
      {send.isError ? <SendError error={send.error} /> : null}
    </Stack>
  );
}

/**
 * What was typed on a question's card and what came of each answer, oldest first: shown on the card whether it is open
 * or closed, so what Ask Shutter said and drafted stays in view after the page moves on to the next question.
 */
export function Exchanges({ q, rid }: { q: SetupQuestion; rid: string }) {
  const turns = useSetup((s) => s.turns);
  const cancel = useSetup((s) => s.cancelPending);
  const mine = turns.filter((t) => t.rid === rid && t.question === q.id);
  if (!mine.length) return null;
  return (
    <Stack
      gap="sm"
      component="ul"
      className="setup-rows"
      aria-label={`Your answers in your own words: ${q.short}`}
    >
      {mine.map((t) => (
        <Exchange key={t.id} turn={t} onCancel={cancel} />
      ))}
    </Stack>
  );
}
