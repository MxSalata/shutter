import { Button, Code, Group, List, Paper, Stack, Table, Text, Title } from '@mantine/core';
import { useClipboard } from '@mantine/hooks';
import { IconCheck, IconCopy } from '@tabler/icons-react';
import { useCan, useReadCorrectionDraft } from '@/api/hooks';
import type {
  CorrectionDraftView,
  CorrectionSequence,
  CorrectionSequenceStep,
  CorrectionSteps,
} from '@/api/types';
import { Digest } from '@/components/Digest';
import { ErrorAlert } from '@/components/ErrorAlert';
import { StackTable } from '@/components/StackTable';
import { plural } from '@/lib/format';

/**
 * The cancel-and-replay sequence a person could send to correct a receiver's history (CONTRACTS 10). Shutter sends none
 * of it: this block has no Send button. The plan holds only its structure, which everyone sees; the text comes from the
 * draft route, for an approver, and only on a click, because the server records every read on the case. Times are shown
 * as the server gives them, never converted. The server words the draft; only the structure's lines are worded here.
 */
export function CorrectionDraft({ caseId, correction }: { caseId: string; correction: CorrectionSteps }) {
  const sequence = correction.sequence;
  // A plan from before v1.47 has no sequence, and says nothing about one
  if (!sequence) return null;
  return (
    <Paper
      p="sm"
      radius="md"
      withBorder
      component="section"
      aria-labelledby="correction-draft-title"
      data-testid="correction-draft"
      style={{ overflowWrap: 'anywhere' }}
    >
      <Stack gap="sm">
        <Title order={3} id="correction-draft-title">
          Drafted message sequence
        </Title>
        {sequence.drawn || notYet(sequence.reason_code) ? (
          // A new plan is another draft: what was read of the last one goes with it
          <Readable
            key={`${sequence.observed_at}|${sequence.checked_at}`}
            caseId={caseId}
            receiver={correction.receiver}
            sequence={sequence}
          />
        ) : (
          <Text size="sm" data-testid="correction-draft-none">
            {sequence.reason || 'No sequence.'}
          </Text>
        )}
      </Stack>
    </Paper>
  );
}

/** The index was behind when this was checked: not yet, not no, because every read checks again. */
const notYet = (code?: string) => code === 'feed_not_indexed';

/** A sequence an approver can ask for: one drawn at plan time, or one the index was still behind on then. */
function Readable({
  caseId,
  receiver,
  sequence,
}: {
  caseId: string;
  receiver: string;
  sequence: CorrectionSequence;
}) {
  const can = useCan();
  const read = useReadCorrectionDraft(caseId);
  const draft = read.data;
  return (
    <>
      {draft ? (
        <Read draft={draft} planDrawn={sequence.drawn} />
      ) : sequence.drawn ? (
        <Structure receiver={receiver} sequence={sequence} />
      ) : (
        <Text size="sm" data-testid="correction-draft-none">
          {sequence.reason}
        </Text>
      )}
      {read.isError ? <ErrorAlert error={read.error} title="The draft could not be read" /> : null}
      {can.approve ? (
        <Group gap="sm" align="center">
          <Button size="xs" variant="default" loading={read.isPending} onClick={() => read.mutate()}>
            {draft ? 'Read it again' : 'Read the messages'}
          </Button>
          <Text size="sm" c="dimmed">
            {draft?.drawn
              ? 'Before each message. Each read is recorded on the case.'
              : draft || !sequence.drawn
                ? 'Each read checks again, and one that draws the messages is recorded on the case.'
                : 'Each read is recorded on the case.'}
          </Text>
        </Group>
      ) : (
        <Text size="sm" data-testid="correction-draft-ask">
          An approver reads the message text here: ask one.
        </Text>
      )}
    </>
  );
}

/** What the plan holds: the order, the wards and the digests, as they stood at plan time. No message text. */
function Structure({ receiver, sequence }: { receiver: string; sequence: CorrectionSequence }) {
  const k = sequence.k ?? 0;
  return (
    <>
      <Stack gap={4}>
        <Text size="sm" fw={600}>
          Draft. Shutter has sent none of this and will send none of it.
        </Text>
        <Text size="sm">
          {`${plural(sequence.count ?? 0, 'message')}: ${plural(k, 'cancel')}, newest first, then the failed movement, then the later ${k === 1 ? 'movement' : 'movements, oldest first'}. Each cancel reaches only what is current at that step, so one cancel is needed for each later movement.`}
        </Text>
        <Text size="sm">
          {`Drawn from the snapshot taken at ${sequence.observed_at ?? 'an unknown time'} with ${receiver} at version ${sequence.receiver_version ?? 'unknown'}. If the version has moved, throw this away and reinvestigate.`}
        </Text>
        <Text size="sm">
          {`Shutter can't see a change made by hand at ${receiver}, or a message on a route it doesn't index: check ${receiver}'s own screen first.`}
        </Text>
      </Stack>
      <List type="ordered" size="sm" spacing={6} data-testid="correction-draft-structure">
        {(sequence.steps ?? []).map((step) => (
          <List.Item key={step.n}>
            <StepLine step={step} />
          </List.Item>
        ))}
      </List>
      {sequence.end?.ward ? (
        <Text size="sm">
          {`At the end: ${sequence.end.ward}${sequence.end.history?.length ? `, with the history ${sequence.end.history.join(', ')}` : ''}.`}
        </Text>
      ) : null}
    </>
  );
}

function StepLine({ step }: { step: CorrectionSequenceStep }) {
  const moved = (event?: string, ward?: string, time?: string) =>
    `the ${event ?? 'movement'}${ward ? ` to ${ward}` : ''}${time ? ` at ${time}` : ''}`;
  return (
    <Stack gap={2}>
      <Text size="sm">
        {step.kind === 'cancel'
          ? `Cancel (${step.trigger}): ${moved(step.cancels?.event, step.cancels?.ward, step.cancels?.event_time)}.`
          : `Replay, unchanged (${step.trigger}): ${moved(step.event, step.ward, step.event_time)}, control id ${step.source_message_id ?? 'unknown'}.`}
      </Text>
      <Text size="sm" c="dimmed">
        {`After it, by the source: ${step.after?.by_source ?? 'unknown'}. By what this receiver holds: ${step.after?.by_receiver ?? 'unknown'}.`}
      </Text>
      {step.non_ascii ? (
        <Text size="sm">Its text is held back when read: it is resent from the message store.</Text>
      ) : null}
      {step.body_digest ? <Digest value={step.body_digest} label={`digest of message ${step.n}`} /> : null}
    </Stack>
  );
}

/** What the draft route answered: the words and the text are the server's, redrawn on this read. */
function Read({ draft, planDrawn }: { draft: CorrectionDraftView; planDrawn: boolean }) {
  // The live check wins over the plan: a further message since then leaves no text on the page
  if (!draft.drawn)
    return (
      <Stack gap={4} data-testid="correction-draft-stopped">
        {planDrawn && !notYet(draft.reason_code) ? (
          <Text size="sm" fw={600}>
            This draft no longer stands.
          </Text>
        ) : null}
        <Text size="sm">{draft.reason || 'No sequence.'}</Text>
        {draft.checked_at ? <Text size="sm" c="dimmed">{`Checked at ${draft.checked_at}.`}</Text> : null}
      </Stack>
    );
  return (
    <>
      <Stack gap={4} data-testid="correction-draft-header">
        {draft.header.map((line, i) => (
          <Text key={i} size="sm" fw={i === 0 ? 600 : undefined}>
            {line}
          </Text>
        ))}
      </Stack>
      <Stack gap="md" data-testid="correction-draft-messages">
        {draft.messages.map((m) => (
          <Message key={m.n} message={m} of={draft.messages.length} />
        ))}
      </Stack>
      <Stack gap={4}>
        <Title order={4} fz="sm">
          What this draft can't know
        </Title>
        <Table.ScrollContainer minWidth={520} className="stack-scroll">
          <StackTable verticalSpacing={4} className="stack-table">
            <StackTable.Thead>
              <StackTable.Tr>
                <StackTable.Th>What</StackTable.Th>
                <StackTable.Th>Why it matters</StackTable.Th>
                <StackTable.Th>What the draft does</StackTable.Th>
              </StackTable.Tr>
            </StackTable.Thead>
            <StackTable.Tbody>
              {draft.cannot_know.map((row) => (
                <StackTable.Tr key={row.what}>
                  <StackTable.Td data-label="What">
                    <Text size="sm" fw={600}>
                      {row.what}
                    </Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="Why it matters">
                    <Text size="sm">{row.why}</Text>
                  </StackTable.Td>
                  <StackTable.Td data-label="What the draft does">
                    <Text size="sm">{row.does}</Text>
                  </StackTable.Td>
                </StackTable.Tr>
              ))}
            </StackTable.Tbody>
          </StackTable>
        </Table.ScrollContainer>
      </Stack>
      <Stack gap={4}>
        <Title order={4} fz="sm">
          Never
        </Title>
        <List size="sm" spacing={2}>
          {draft.never.map((line, i) => (
            <List.Item key={i}>{line}</List.Item>
          ))}
        </List>
      </Stack>
      <Group gap="xs" align="center">
        <Text size="sm" c="dimmed">
          {`Checked at ${draft.checked_at ?? 'an unknown time'}. Digest of this draft:`}
        </Text>
        <Digest value={draft.digest} label="digest of this draft" />
      </Group>
    </>
  );
}

function Message({ message: m, of }: { message: CorrectionDraftView['messages'][number]; of: number }) {
  const text = m.text ?? '';
  const placeholders = /\[(SENDER|SITE):/.test(text);
  return (
    <Stack gap={4} data-testid={`correction-message-${m.n}`}>
      <Title order={4} fz="sm">{`Message ${m.n} of ${of}: ${m.trigger}`}</Title>
      <Text size="sm">{m.label}</Text>
      {m.withheld ? (
        <Text size="sm" fw={600} data-testid="correction-message-withheld">
          {m.withheld}
        </Text>
      ) : null}
      {text ? (
        <>
          {/* Segments end with a carriage return, which a browser doesn't break a line on. The page breaks there; the copy keeps it */}
          <Code block style={{ whiteSpace: 'pre-wrap', overflowWrap: 'anywhere' }}>
            {text.replace(/\r\n?/g, '\n').replace(/\n$/, '')}
          </Code>
          {placeholders ? (
            <Text size="sm">The values in square brackets are for the person sending to fill in.</Text>
          ) : null}
          {/* "Don't paste this message" and a Copy button can't stand together */}
          {m.withheld ? null : <CopyMessage n={m.n} text={text} />}
        </>
      ) : null}
      {m.after ? (
        <Text size="sm" c="dimmed">
          {m.after}
        </Text>
      ) : null}
    </Stack>
  );
}

/**
 * Copies the message as the server gave it. A browser on plain http has no clipboard, and a copy that fails in silence
 * would leave the last message there to be pasted, so a failure is said.
 */
function CopyMessage({ n, text }: { n: number; text: string }) {
  const clipboard = useClipboard({ timeout: 1500 });
  return (
    <Group gap="xs" align="center">
      <Button
        size="xs"
        variant="default"
        leftSection={
          clipboard.copied ? <IconCheck size={14} aria-hidden /> : <IconCopy size={14} aria-hidden />
        }
        onClick={() => {
          clipboard.reset();
          clipboard.copy(text);
        }}
      >
        {clipboard.copied ? `Copied message ${n}` : `Copy message ${n}`}
      </Button>
      {clipboard.error ? (
        <Text size="sm" data-testid="correction-copy-failed">
          This browser refused the copy: select the text above by hand.
        </Text>
      ) : null}
    </Group>
  );
}
