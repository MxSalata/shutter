import {
  Accordion,
  Alert,
  Badge,
  Button,
  Code,
  Group,
  Modal,
  NativeSelect,
  Stack,
  Text,
  Textarea,
  TextInput,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconMailForward } from '@tabler/icons-react';
import { useState } from 'react';
import { newIdempotencyKey } from '@/api/client';
import {
  useDraftEscalation,
  useEditEscalation,
  useEscalations,
  useMe,
  useSendEscalation,
  useSiteProfile,
} from '@/api/hooks';
import type { CaseDetail, Escalation } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { Timestamp } from '@/components/Timestamp';
import { describeError } from '@/lib/errors';
import { humanize } from '@/lib/format';
import { Section } from './Section';

const STATE_COLOURS: Record<string, string> = {
  draft: 'gray',
  queued: 'blue',
  sent: 'teal',
  failed: 'red',
  cancelled: 'gray',
};

/** The dialog: a draft Shutter built from the case, which the person checks, edits and sends. */
function EscalateDialog({ c, draft, onClose }: { c: CaseDetail; draft: Escalation; onClose: () => void }) {
  const edit = useEditEscalation(c.caseId);
  const send = useSendEscalation(c.caseId);
  const [to, setTo] = useState(draft.to ?? '');
  const [cc, setCc] = useState(draft.cc ?? '');
  const [subject, setSubject] = useState(draft.subject);
  const [body, setBody] = useState(draft.body);
  const [key] = useState(newIdempotencyKey);
  const changed =
    to !== (draft.to ?? '') || cc !== (draft.cc ?? '') || subject !== draft.subject || body !== draft.body;
  const busy = edit.isPending || send.isPending;
  const error = edit.error ?? send.error;

  const submit = async () => {
    // An edited draft is stored first; the send then names the digest of the text as stored
    const stored = changed
      ? await edit.mutateAsync({ seq: draft.seq, change: { to, cc, subject, body } })
      : draft;
    await send.mutateAsync({ seq: draft.seq, bodyDigest: stored.bodyDigest, idempotencyKey: key });
    notifications.show({
      color: 'teal',
      title: `Escalation ${draft.seq} sent`,
      message: `To ${to}. Reinvestigate the case once they have corrected the systems.`,
    });
    onClose();
  };

  return (
    <Modal
      opened
      onClose={() => (busy ? undefined : onClose())}
      title="Escalate to system administrators"
      size="xl"
    >
      <Stack gap="sm">
        <Text size="sm">
          Shutter drafted this from its record of the case: the patient&apos;s identifiers and date of birth,
          the event, why it stopped, what the downstream system holds and the encounter&apos;s messages. No
          name, address or note text. Check it, change what you need, and send it to the team that can compare
          the systems and correct them by hand.
        </Text>
        <TextInput
          label="To"
          description="Addresses separated by commas"
          value={to}
          onChange={(e) => setTo(e.currentTarget.value)}
          error={!to.trim() ? 'Who is it for?' : undefined}
          data-autofocus={!to.trim() || undefined}
        />
        <TextInput label="Cc" value={cc} onChange={(e) => setCc(e.currentTarget.value)} />
        <TextInput label="Subject" value={subject} onChange={(e) => setSubject(e.currentTarget.value)} />
        <Textarea
          label="Message"
          value={body}
          onChange={(e) => setBody(e.currentTarget.value)}
          autosize
          minRows={12}
          maxRows={24}
          styles={{ input: { fontFamily: 'var(--mantine-font-family-monospace)', fontSize: 13 } }}
        />
        {error ? (
          <Alert color="red" variant="light" role="alert" title="Nothing was sent">
            {describeError(error)}
          </Alert>
        ) : null}
        <Group justify="flex-end" gap="sm">
          <Button variant="default" onClick={onClose} disabled={busy}>
            Keep as a draft
          </Button>
          <Button
            leftSection={<IconMailForward size={16} />}
            onClick={() => void submit().catch(() => undefined)}
            loading={busy}
            disabled={!to.trim() || !subject.trim() || !body.trim()}
          >
            Send
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

/**
 * Escalations: when Shutter can't safely recover a message, a person sends the case to the team that owns the
 * downstream system, who compare the systems and correct them by hand, outside HL7 (T29).
 */
export function EscalationPanel({ c }: { c: CaseDetail }) {
  const stopped = ['blocked', 'escalated', 'failed'].includes(c.state);
  const me = useMe().data;
  const list = useEscalations(c.caseId, stopped);
  const profile = useSiteProfile().data?.profile;
  const draft = useDraftEscalation(c.caseId);
  const teams = profile?.teams ?? [];
  const [teamId, setTeamId] = useState('');
  const [open, setOpen] = useState<Escalation | null>(null);
  if (!stopped) return null;
  const escalations = list.data ?? [];
  const pending = escalations.find((e) => e.state === 'draft' || e.state === 'failed');
  const start = () =>
    draft.mutate(
      { teamId: teamId || undefined, idempotencyKey: newIdempotencyKey() },
      { onSuccess: (e) => setOpen(e) },
    );
  return (
    <Section
      id="escalations"
      title="Escalations"
      note="When Shutter can't safely recover a message, don't guess: send the case to the team that owns the downstream system, so they compare the systems and correct them by hand. Shutter drafts the email from its record; a person checks it and sends it."
    >
      {list.isError ? <ErrorAlert error={list.error} title="The escalations could not be read" /> : null}
      {escalations.map((e) => (
        <Accordion key={e.seq} variant="separated" chevronPosition="left">
          <Accordion.Item value={String(e.seq)}>
            <Accordion.Control>
              <Group gap={6} wrap="wrap">
                <Text size="sm" fw={600}>
                  Escalation {e.seq}
                </Text>
                <Badge
                  color={STATE_COLOURS[e.state] ?? 'gray'}
                  variant="light"
                  style={{ textTransform: 'none' }}
                >
                  {humanize(e.state)}
                </Badge>
                <Text size="xs" c="dimmed">
                  {e.teamName ? `${e.teamName}, ` : ''}
                  {e.to || 'no recipient yet'}
                </Text>
              </Group>
            </Accordion.Control>
            <Accordion.Panel>
              <Stack gap="xs">
                <Group gap="lg" wrap="wrap">
                  {e.sentAt ? (
                    <Group gap={4}>
                      <Text size="xs" c="dimmed">
                        Sent by {e.sentBy}
                      </Text>
                      <Timestamp iso={e.sentAt} size="xs" />
                    </Group>
                  ) : e.draftedAt ? (
                    <Group gap={4}>
                      <Text size="xs" c="dimmed">
                        Drafted for {e.draftedBy}
                      </Text>
                      <Timestamp iso={e.draftedAt} size="xs" />
                    </Group>
                  ) : null}
                  {e.transport ? (
                    <Text size="xs" c="dimmed">
                      {e.transport === 'file'
                        ? 'Written as an email file: no mail server is configured'
                        : 'Sent by email'}
                    </Text>
                  ) : null}
                </Group>
                {e.state === 'failed' && e.result ? (
                  <Text size="sm" c="red">
                    {e.result}
                  </Text>
                ) : null}
                <Text size="sm" fw={600}>
                  {e.subject}
                </Text>
                <Code block>{e.body}</Code>
                {(e.state === 'draft' || e.state === 'failed') && me?.operator ? (
                  <Group>
                    <Button size="xs" variant="light" onClick={() => setOpen(e)}>
                      {e.state === 'failed' ? 'Check and send again…' : 'Check and send…'}
                    </Button>
                  </Group>
                ) : null}
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>
        </Accordion>
      ))}
      {me?.operator ? (
        <Group gap="sm" align="flex-end" wrap="wrap">
          {teams.length ? (
            <NativeSelect
              label="Team"
              value={teamId}
              onChange={(e) => setTeamId(e.currentTarget.value)}
              data={[
                { value: '', label: 'The downstream system’s team' },
                ...teams.map((t) => ({ value: t.id, label: `${t.name} (${t.mailbox})` })),
              ]}
              w={300}
            />
          ) : null}
          <Button
            leftSection={<IconMailForward size={16} />}
            variant={pending ? 'default' : 'filled'}
            loading={draft.isPending}
            onClick={start}
          >
            Escalate to system administrators{'…'}
          </Button>
        </Group>
      ) : (
        <Text size="sm" c="dimmed">
          Escalating needs the operator role.
        </Text>
      )}
      {!teams.length ? (
        <Text size="xs" c="dimmed">
          No teams are set in the site profile yet, so the draft has no recipient: add one there, or type the
          address.
        </Text>
      ) : null}
      {draft.isError ? <ErrorAlert error={draft.error} title="The draft could not be made" /> : null}
      {open ? (
        <EscalateDialog
          key={`${open.seq}:${open.bodyDigest}`}
          c={c}
          draft={open}
          onClose={() => setOpen(null)}
        />
      ) : null}
    </Section>
  );
}
