import { Anchor, Button, Group, Paper, Stack, Text, Title } from '@mantine/core';
import type { ReactNode } from 'react';
import { Link } from 'react-router';
import type { SiteProfile, SiteReceiver } from '@/api/types';
import { AskAboutRegion } from '@/features/assistant/AskAboutRegion';
import { StatusBadge } from '@/components/StatusBadge';
import { CATEGORIES, CATEGORY_TEXT } from '@/lib/categories';
import { Radio, Switch, TextInput } from '../controls';
import { Effect } from '../Question';
import { TIERS, TIER_HINTS, TIER_LABELS } from '../profile';
import { STATUS_WORDS, cardId, cardTitleId, controlId, statusLabel, whyFocus } from './cards';
import { answerText, consequence, type SetupQuestion } from './fields';
import type { AnswerStatus } from './setupStore';

function Choice({
  id,
  label,
  value,
  options,
  onChange,
  error,
  disabled = false,
}: {
  id: string;
  label: string;
  value: string;
  options: [value: string, label: string, description?: string][];
  onChange: (v: string) => void;
  error?: string;
  disabled?: boolean;
}) {
  const known = !value || options.some(([v]) => v === value);
  return (
    <Radio.Group id={id} label={label} value={value} onChange={onChange} error={error}>
      <Stack gap={6} mt={4}>
        {options.map(([v, l, d]) => (
          <Radio key={v} value={v} label={l} description={d} disabled={disabled} />
        ))}
        {!known ? <Radio value={value} label={`Kept as stored: ${value}`} disabled /> : null}
      </Stack>
    </Radio.Group>
  );
}

/**
 * The page's own control for one question, the same as the Site profile form's: a person's answer goes straight into the
 * draft (`set`), and nothing else does in this version.
 */
export function AnswerControl({
  q,
  r,
  fixedName,
  set,
  error,
  disabled = false,
}: {
  q: SetupQuestion;
  r: SiteReceiver;
  /** The receiver is in force: its name is changed on the Site profile page, where a rename is a remove and an add. */
  fixedName: boolean;
  set: (key: string, value: unknown) => void;
  error?: string;
  /** Ask Shutter is reading a typed answer about this receiver: the answers it may draft wait for it. */
  disabled?: boolean;
}) {
  const name = r.name.trim() || 'this receiver';
  switch (q.id) {
    case 'name':
      return fixedName ? (
        <Text size="sm">
          {r.name}. A receiver in force is renamed or removed on the{' '}
          <Anchor component={Link} to="/site-profile" inherit underline="always">
            Site profile page
          </Anchor>
          .
        </Text>
      ) : (
        <TextInput
          id={controlId('name')}
          label="Production item"
          description="The business operation's name in the production, exactly"
          value={r.name}
          onChange={(e) => set('name', e.currentTarget.value)}
          error={error}
        />
      );
    case 'system':
      return (
        <TextInput
          id={controlId('system')}
          label="What it does in the hospital's workflow"
          description="A few words, such as the ward whiteboard"
          maxLength={120}
          disabled={disabled}
          value={r.system ?? ''}
          onChange={(e) => set('system', e.currentTarget.value === '' ? undefined : e.currentTarget.value)}
          error={error}
        />
      );
    case 'category':
      return (
        <Choice
          id={controlId('category')}
          label={`Kind of ${name}`}
          value={r.category ? String(r.category) : ''}
          options={CATEGORIES.map((c) => [
            c,
            CATEGORY_TEXT[c].label,
            `${CATEGORY_TEXT[c].gist}. ${CATEGORY_TEXT[c].examples}.`,
          ])}
          onChange={(v) => set('category', v)}
          error={error}
          disabled={disabled}
        />
      );
    case 'tier':
      return (
        <Choice
          id={controlId('tier')}
          label={`Tier of ${name}`}
          value={r.tier === undefined || r.tier === null ? '' : String(r.tier)}
          options={TIERS.map((t) => [t, TIER_LABELS[t], TIER_HINTS[t]])}
          onChange={(v) => set('tier', Number(v))}
          error={error}
          disabled={disabled}
        />
      );
    case 'applies':
      return (
        <Choice
          id={controlId('applies')}
          label={`${r.name.trim() || 'This receiver'} applies messages`}
          value={r.applies ?? ''}
          options={[
            ['arrival_order', 'In arrival order', 'A late message moves the record backwards'],
            ['event_time', 'By event time', 'The receiver orders by the time the event happened'],
          ]}
          onChange={(v) => set('applies', v)}
          error={error}
        />
      );
    case 'resend_timestamp':
      return (
        <Choice
          id={controlId('resend_timestamp')}
          label={`A resend to ${name} carries`}
          value={r.resend_timestamp ?? ''}
          options={[
            ['original', 'Its original MSH-7'],
            ['fresh', 'A fresh MSH-7'],
          ]}
          onChange={(v) => set('resend_timestamp', v)}
          error={error}
        />
      );
    case 'takes':
      return (
        <Stack gap="xs">
          <Switch
            id={controlId('cancels')}
            label={`${r.name.trim() || 'This receiver'} accepts cancels`}
            description="Off: Shutter never sends it a cancel; the case goes to a person"
            checked={r.cancels === true}
            onChange={(e) => set('cancels', e.currentTarget.checked)}
            error={error}
          />
          <Switch
            id={controlId('merges')}
            label={`${r.name.trim() || 'This receiver'} takes merges`}
            description="A merge also needs the site to allow merges; otherwise it goes to the PAS team"
            checked={r.merges === true}
            onChange={(e) => set('merges', e.currentTarget.checked)}
          />
          {r.cancels === undefined && r.merges === undefined ? (
            <Group>
              <Button
                size="xs"
                variant="default"
                onClick={() => {
                  set('cancels', false);
                  set('merges', false);
                }}
              >
                It accepts neither
              </Button>
            </Group>
          ) : null}
        </Stack>
      );
  }
}

/** The line a closed card says its answer in: whose it is, then the answer. */
function answerLine(q: SetupQuestion, r: SiteReceiver, status: AnswerStatus, version: number): string {
  const value = answerText(q, r);
  switch (status) {
    case 'you':
      return `You: ${value}`;
    case 'ask':
      return `Drafted by Ask Shutter: ${value}`;
    case 'in_force':
      return `In force, version ${version}: ${value || 'not answered'}`;
    case 'onboarding':
      return `From onboarding, to confirm: ${value || 'not answered'}`;
    case 'left':
      return `Left for now. ${q.unanswered}`;
    default:
      return q.unanswered;
  }
}

/**
 * One question of the checklist as a card of the conversation. Open, it holds the page's control, what the answer does
 * in the page's own words, "Why does this matter?" (Ask Shutter's explanation through the page question route, or the
 * written one where no live answer is given), and the ways on: the next question, or leaving this one for now. Closed,
 * it says the answer and whose it is in one line, with Change.
 */
export function AnswerCard({
  q,
  r,
  profile,
  status,
  version,
  open,
  fixedName,
  error,
  whyOpen,
  set,
  onOpen,
  nextLabel,
  onNext,
  onLeave,
  onWhy,
  extra,
  log,
  disabled = false,
  personOnly,
}: {
  q: SetupQuestion;
  r: SiteReceiver;
  /** The draft, which the answer's consequence is read from. */
  profile: SiteProfile;
  status: AnswerStatus;
  version: number;
  open: boolean;
  fixedName: boolean;
  error?: string;
  whyOpen: boolean;
  set: (key: string, value: unknown) => void;
  onOpen: () => void;
  /** The way on from an answered card: "Next question", or "Done" when no question is left. Absent while unanswered. */
  nextLabel?: string;
  onNext: () => void;
  /** Absent where the question holds an answer: there is nothing to leave. */
  onLeave?: () => void;
  onWhy: () => void;
  /** Under the control of an open card: an answer in the person's own words, where Ask Shutter may draft it. */
  extra?: ReactNode;
  /** What was typed on this card and what came of it: shown open or closed. */
  log?: ReactNode;
  /** Ask Shutter is reading a typed answer: this card's control waits for it. */
  disabled?: boolean;
  /** Said where Ask Shutter reads typed answers on the page, of a question it never drafts. */
  personOnly?: string;
}) {
  const whyId = `${cardId(q.id)}-why`;
  const words = STATUS_WORDS[status];
  return (
    <Paper
      component="section"
      id={cardId(q.id)}
      aria-labelledby={cardTitleId(q.id)}
      withBorder
      p="md"
      className="setup-card"
      data-status={status}
      data-open={open || undefined}
    >
      <Stack gap="sm">
        <Group gap="sm" wrap="nowrap" align="flex-start">
          <span aria-hidden className="identity-mark setup-card-n">
            {q.n}
          </span>
          <Title order={3} size="h4" id={cardTitleId(q.id)} tabIndex={-1} style={{ flex: 1, minWidth: 0 }}>
            {q.text}
          </Title>
          <Effect acts={q.acts} />
        </Group>
        <Group gap="xs" wrap="wrap">
          <StatusBadge tone={words.tone} label={statusLabel(status, version)} />
          {q.required ? (
            <Text size="sm" c="dimmed">
              Needed before review
            </Text>
          ) : null}
        </Group>
        {open ? (
          <>
            {personOnly ? (
              <Text size="sm" c="dimmed">
                {personOnly}
              </Text>
            ) : null}
            <AnswerControl q={q} r={r} fixedName={fixedName} set={set} error={error} disabled={disabled} />
            {extra}
            <Text size="sm" data-testid={`setup-consequence-${q.id}`}>
              {consequence(q, r, profile)}
            </Text>
            <Group gap="sm" wrap="wrap">
              {nextLabel ? (
                <Button size="sm" onClick={onNext}>
                  {nextLabel}
                </Button>
              ) : null}
              {onLeave ? (
                <Button size="sm" variant="default" onClick={onLeave}>
                  Leave for now
                </Button>
              ) : null}
              <Button
                size="sm"
                variant="subtle"
                aria-expanded={whyOpen}
                aria-controls={whyOpen ? whyId : undefined}
                onClick={onWhy}
              >
                Why does this matter?
              </Button>
            </Group>
          </>
        ) : (
          <Group gap="sm" wrap="wrap" justify="space-between">
            <Text size="sm" style={{ flex: '1 1 220px', minWidth: 0, overflowWrap: 'anywhere' }}>
              {answerLine(q, r, status, version)}
            </Text>
            <Button
              size="xs"
              variant="default"
              aria-label={`${status === 'left' || status === 'unanswered' ? 'Answer' : 'Change'}: ${q.short}`}
              onClick={onOpen}
            >
              {status === 'left' || status === 'unanswered' ? 'Answer' : 'Change'}
            </Button>
          </Group>
        )}
        {log}
        {open && whyOpen ? <AskAboutRegion id={whyId} focus={whyFocus(q, r, profile)} /> : null}
      </Stack>
    </Paper>
  );
}
