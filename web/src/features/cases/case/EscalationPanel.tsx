import {
  Accordion,
  Alert,
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
import {
  IconAlertCircle,
  IconCircleCheck,
  IconClock,
  IconMailForward,
  IconMinus,
  IconPencil,
  IconSend,
  type Icon,
} from '@tabler/icons-react';
import { useState } from 'react';
import { newIdempotencyKey } from '@/api/client';
import {
  useCloseCase,
  useDraftEscalation,
  useEditEscalation,
  useEscalations,
  useMe,
  useSendEscalation,
  useSiteProfile,
} from '@/api/hooks';
import type { CaseDetail, Escalation } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import type { Tone } from '@/lib/tone';
import { describeError, isApiError } from '@/lib/errors';
import { addressesProblem, closeNeedsApprover, controlProblem } from '../../site-profile/profile';
import { formatZoned, humanize } from '@/lib/format';
import { Section } from './Section';

/** An escalation email's states: sending it is an action taken, not a result verified, so sent is information. */
const EMAIL_TONES: Record<string, Tone> = {
  draft: 'neutral',
  queued: 'info',
  sent: 'info',
  failed: 'blocking',
  cancelled: 'neutral',
};
const EMAIL_ICONS: Record<string, Icon> = {
  draft: IconPencil,
  queued: IconClock,
  sent: IconSend,
  failed: IconAlertCircle,
  cancelled: IconMinus,
};

/** Who an escalation goes to, by one name wherever it is named: the team that owns the downstream system. */
const RECIPIENT = "the downstream system's team";

/** The dialog: a draft Shutter built from the case, which the person checks, edits and sends. */
function EscalateDialog({ c, draft, onClose }: { c: CaseDetail; draft: Escalation; onClose: () => void }) {
  const edit = useEditEscalation(c.caseId);
  const send = useSendEscalation(c.caseId);
  const [to, setTo] = useState(draft.to ?? '');
  const [cc, setCc] = useState(draft.cc ?? '');
  const [subject, setSubject] = useState(draft.subject);
  const [body, setBody] = useState(draft.body);
  const [key] = useState(newIdempotencyKey);
  const [lastSent, setLastSent] = useState({ to: '', cc: '', subject: '' });
  const changed =
    to !== (draft.to ?? '') || cc !== (draft.cc ?? '') || subject !== draft.subject || body !== draft.body;
  const busy = edit.isPending || send.isPending;
  const error = edit.error ?? send.error;
  // The site's rule for addresses, checked as they are typed; the server checks them again at the edit and the send
  const domains = useSiteProfile().data?.profile.mail?.allowed_domains ?? [];
  const toProblem = addressesProblem(to, domains);
  const ccProblem = addressesProblem(cc, domains);
  // The subject is one header line: no line break or other control character, as the server checks it
  const subjectProblem = controlProblem(subject);
  // A refusal the server named a field for (the domains changed meanwhile) shows on that field, while it still applies
  const refused =
    isApiError(error) && (error.code === 'address_not_allowed' || error.code === 'subject_not_allowed')
      ? ((error.body as { field?: string } | null)?.field ?? '')
      : '';
  const fieldError = (field: 'to' | 'cc' | 'subject', value: string, problem: string) =>
    problem
      ? `Not allowed: ${problem}`
      : refused === field && value === lastSent[field]
        ? error!.message
        : undefined;

  const submit = async () => {
    setLastSent({ to, cc, subject });
    // An edited draft is stored first; the send then names the digest of the text as stored
    const stored = changed
      ? await edit.mutateAsync({ seq: draft.seq, change: { to, cc, subject, body } })
      : draft;
    await send.mutateAsync({ seq: draft.seq, bodyDigest: stored.bodyDigest, idempotencyKey: key });
    notifications.show({
      color: 'blue',
      title: `Escalation ${draft.seq} sent`,
      message: `To ${to}. Once they have corrected the systems, mark the case as handled${c.failureKind === 'withheld' ? '' : ', or reinvestigate it'}.`,
    });
    onClose();
  };

  return (
    <Modal
      opened
      onClose={() => (busy ? undefined : onClose())}
      title={`Escalate to ${draft.teamName || RECIPIENT}`}
      size="xl"
    >
      <Stack gap="sm">
        <Text size="sm">
          Shutter drafted this from its record of the case: the patient&apos;s identifiers and date of birth,
          the event, why it stopped, what the downstream system holds and the encounter&apos;s messages. No
          name, address or note text. Check it, change what you need, and send it to{' '}
          {draft.teamName || RECIPIENT}, who compare the systems and correct them by hand.
        </Text>
        <TextInput
          label="To"
          description={`Addresses separated by commas${domains.length ? `, in ${domains.join(', ')}` : ''}`}
          value={to}
          onChange={(e) => setTo(e.currentTarget.value)}
          error={!to.trim() ? 'Who is it for?' : fieldError('to', to, toProblem)}
          data-autofocus={!to.trim() || undefined}
        />
        <TextInput
          label="Cc"
          description={domains.length ? `Addresses in ${domains.join(', ')}` : undefined}
          value={cc}
          onChange={(e) => setCc(e.currentTarget.value)}
          error={fieldError('cc', cc, ccProblem)}
        />
        <TextInput
          label="Subject"
          value={subject}
          onChange={(e) => setSubject(e.currentTarget.value)}
          error={fieldError('subject', subject, subjectProblem)}
        />
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
            disabled={
              !to.trim() || !!toProblem || !!ccProblem || !subject.trim() || !!subjectProblem || !body.trim()
            }
          >
            Send
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
}

/**
 * Closes a case the team corrected by hand: offered once an escalation is sent, or at once for a withheld case (a merge
 * or a cancel Shutter never sends), where reinvestigating could find nothing new. The reason is recorded on the case,
 * and the case's version guards against closing one that changed meanwhile.
 */
function MarkHandled({ c }: { c: CaseDetail }) {
  const close = useCloseCase(c.caseId);
  const [opened, setOpened] = useState(false);
  const [reason, setReason] = useState('');
  const [key, setKey] = useState('');
  const open = () => {
    setReason('');
    setKey(newIdempotencyKey());
    close.reset();
    setOpened(true);
  };
  const submit = () =>
    close.mutate(
      { reason: reason.trim(), expectedVersion: c.version, idempotencyKey: key },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'blue',
            title: `${c.caseId} marked as handled`,
            message: 'Closed as handled by hand; any email of the case not yet sent is cancelled.',
          });
        },
      },
    );
  return (
    <>
      <Group gap="sm" wrap="wrap">
        <Button variant="light" leftSection={<IconCircleCheck size={16} />} onClick={open}>
          Mark as handled by the team…
        </Button>
        <Text size="xs" c="dimmed">
          When the team has corrected the systems by hand. Nothing is sent.
        </Text>
      </Group>
      <Modal opened={opened} onClose={() => setOpened(false)} title={`Mark ${c.caseId} as handled`}>
        <Stack gap="sm">
          <Textarea
            label="What the team did"
            description="Recorded on the case with your name"
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
            autosize
            minRows={2}
            data-autofocus
          />
          {close.error ? (
            <Text size="sm" c="red">
              {describeError(close.error)}
            </Text>
          ) : null}
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setOpened(false)}>
              Cancel
            </Button>
            <Button onClick={submit} loading={close.isPending} disabled={!reason.trim()}>
              Close the case
            </Button>
          </Group>
        </Stack>
      </Modal>
    </>
  );
}

/**
 * Escalations: when Shutter can't safely recover a message, a person sends the case to the team that owns the
 * downstream system, who compare the systems and correct them by hand, outside HL7 (T29). Once the team has closed the
 * case, the emails stay on the page as its record: who sent each, when, and the digest of the text sent.
 */
export function EscalationPanel({ c }: { c: CaseDetail }) {
  const stopped = ['blocked', 'escalated', 'failed'].includes(c.state);
  const handled = c.state === 'resolved' && c.disposition === 'handled_by_hand';
  const me = useMe().data;
  const list = useEscalations(c.caseId, stopped || handled);
  const site = useSiteProfile();
  const profile = site.data?.profile;
  const draft = useDraftEscalation(c.caseId);
  const teams = profile?.teams ?? [];
  const [teamId, setTeamId] = useState('');
  const [open, setOpen] = useState<Escalation | null>(null);
  const escalations = list.data ?? [];
  if (!stopped && !(handled && escalations.length)) return null;
  const pending = escalations.find((e) => e.state === 'draft' || e.state === 'failed');
  const latest = escalations.reduce<Escalation | undefined>(
    (a, e) => (!a || e.seq > a.seq ? e : a),
    undefined,
  );
  const closable = stopped && (c.failureKind === 'withheld' || latest?.state === 'sent');
  // Closing needs the operator resource first, as the server checks it; then the site's two-person rule: an operator
  // without the approver role closes only where the profile allows it, and the server decides when the profile could
  // not be read
  const needsApprover = closeNeedsApprover(profile);
  const mayClose = !!me?.operator && (!!me.approver || site.isError || (!!profile && !needsApprover));
  const start = () =>
    draft.mutate(
      { teamId: teamId || undefined, idempotencyKey: newIdempotencyKey() },
      { onSuccess: (e) => setOpen(e) },
    );
  return (
    <Section
      id="escalations"
      title="Escalations"
      note={
        stopped
          ? `When Shutter can't safely recover a message, don't guess: send the case to ${RECIPIENT}, so they compare the systems and correct them by hand. Shutter drafts the email from its record; a person checks it and sends it.`
          : 'The emails sent before the team corrected the systems by hand and the case was closed.'
      }
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
                <StatusBadge
                  tone={EMAIL_TONES[e.state] ?? 'neutral'}
                  label={humanize(e.state)}
                  icon={EMAIL_ICONS[e.state]}
                />
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
                {(e.state === 'queued' || e.state === 'sent') && e.bodyDigest ? (
                  <Text size="xs" c="dimmed" className="mono-wrap">
                    Digest of the text sent: {e.bodyDigest}
                  </Text>
                ) : null}
                {e.state === 'failed' && e.result ? (
                  <Text size="sm" c="red">
                    {e.result}
                  </Text>
                ) : null}
                <Text size="sm" fw={600}>
                  {e.subject}
                </Text>
                {e.purgedAt ? (
                  <Text size="xs" c="dimmed" className="mono-wrap">
                    Text removed on {formatZoned(e.purgedAt)} by the retention task; digest of the text sent{' '}
                    {e.bodyDigest}
                  </Text>
                ) : (
                  <Code block>{e.body}</Code>
                )}
                {stopped && (e.state === 'draft' || e.state === 'failed') && !e.purgedAt && me?.operator ? (
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
      {/* Until the user is read, neither the actions nor the note that they need the operator role */}
      {!stopped || me === undefined ? null : me?.operator ? (
        <Group gap="sm" align="flex-end" wrap="wrap">
          {teams.length ? (
            <NativeSelect
              label="Team"
              value={teamId}
              onChange={(e) => setTeamId(e.currentTarget.value)}
              data={[
                { value: '', label: RECIPIENT.charAt(0).toUpperCase() + RECIPIENT.slice(1) },
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
            {`Escalate to ${teams.find((t) => t.id === teamId)?.name ?? RECIPIENT}…`}
          </Button>
        </Group>
      ) : (
        <Text size="sm" c="dimmed">
          Escalating and marking a case handled need the operator role.
        </Text>
      )}
      {closable && mayClose ? <MarkHandled c={c} /> : null}
      {closable && !mayClose && me?.operator && needsApprover ? (
        <Text size="sm" c="dimmed">
          On this site closing a case by hand needs an approver (the site profile&apos;s two-person rule):
          once the team has corrected the systems, ask an approver to mark it handled.
        </Text>
      ) : null}
      {stopped && !teams.length ? (
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
