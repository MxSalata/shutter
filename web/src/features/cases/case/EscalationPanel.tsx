import {
  Accordion,
  Alert,
  Button,
  Code,
  Group,
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
  IconFileDownload,
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
import { byEnv } from '@/env/copy';
import { ErrorAlert } from '@/components/ErrorAlert';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import type { Tone } from '@/lib/tone';
import { describeError, isApiError } from '@/lib/errors';
import { addressesProblem, closeNeedsApprover, controlProblem } from '../../site-profile/profile';
import { formatZoned, humanize } from '@/lib/format';
import { ConfirmModal } from '@/components/ConfirmModal';
import { closableByHand } from './caseAction';
import { notModelled } from './derive';
import { ReceiverCheckCard } from './ReceiverCheckCard';
import { receiverNoun, receiverTeam } from './receiver';
import { Section } from './Section';

/**
 * An escalation email's states: sending it is an action taken, not a result verified, so sent is information. Saved is
 * an email file written with no mail server set (v1.53): nobody was emailed, so a person is needed to pass it on.
 */
const EMAIL_TONES: Record<string, Tone> = {
  draft: 'neutral',
  queued: 'info',
  sent: 'info',
  saved: 'attention',
  failed: 'blocking',
  cancelled: 'neutral',
};
/** The badge's words: "Saved, not delivered" says what a saved file is not; the others by their state. */
const emailLabel = (state: string) => (state === 'saved' ? 'Saved, not delivered' : humanize(state));

/** The text's digest, by what was done with it: queued, sent through the mail server, or saved as a file. */
const digestVerb = (state: string) => (state === 'saved' ? 'saved' : state === 'queued' ? 'queued' : 'sent');

const EMAIL_ICONS: Record<string, Icon> = {
  draft: IconPencil,
  queued: IconClock,
  sent: IconSend,
  saved: IconFileDownload,
  failed: IconAlertCircle,
  cancelled: IconMinus,
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
  // Who an escalation goes to, by one name wherever it is named: the team that owns the case's receiver
  const recipient = receiverTeam(c.receiver);
  const [lastSent, setLastSent] = useState({ to: '', cc: '', subject: '' });
  const changed =
    to !== (draft.to ?? '') || cc !== (draft.cc ?? '') || subject !== draft.subject || body !== draft.body;
  const busy = edit.isPending || send.isPending;
  const error = edit.error ?? send.error;
  // The site's rule for addresses, checked as they are typed; the server checks them again at the edit and the send
  const profile = useSiteProfile().data?.profile;
  const domains = profile?.mail?.allowed_domains ?? [];
  // A team that lists neither the receiver nor, for a merge, the source: the draft fell back to the site's first team, or
  // someone picked it. It carries patient identifiers, so the person is told to look.
  const team = profile?.teams?.find((t) => t.id === draft.teamId);
  const teamNotListed =
    !!team &&
    !team.receivers?.includes(c.receiver ?? '') &&
    !(c.event === 'merge' && team.sources?.includes(c.sourceSystem));
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
      title: byEnv({ live: `Escalation ${draft.seq} queued`, trial: 'Saved in the trial, not delivered' }),
      message: byEnv({
        live: `For ${to}. Its line shows whether the mail server took it or it was saved as an email file. Once they have corrected the systems, mark the case as handled${c.failureKind === 'withheld' ? '' : ', or reinvestigate it'}.`,
        trial: 'No email leaves this browser.',
      }),
    });
    onClose();
  };

  return (
    <ConfirmModal
      opened
      onClose={() => (busy ? undefined : onClose())}
      title={`Escalate to ${draft.teamName || recipient}`}
      size="xl"
    >
      <Stack gap="sm">
        {/* What sending does, first: a real email from a live system; nothing at all from the trial */}
        <Text size="sm" fw={600} data-testid="confirm-consequence">
          {byEnv({
            live: `This emails ${draft.teamName ? `the ${draft.teamName}` : recipient} through the site's mail server. With no mail server set, it is saved as an email file and nobody is emailed.`,
            trial:
              'Sending saves it as an email file in the trial, as on an instance with no mail server. No email leaves this browser.',
          })}
        </Text>
        {teamNotListed ? (
          <Text size="sm" fw={600} data-testid="team-not-listed">
            {draft.teamName} does not list {c.receiver} in the site profile. Check it is the right team before
            the patient&apos;s identifiers go to it.
          </Text>
        ) : null}
        <Text size="sm">
          Shutter drafted this from its record of the case: the patient&apos;s identifiers and date of birth,
          the event, why it stopped, what {receiverNoun(c.receiver)} holds and the encounter&apos;s messages.
          No name, address or note text. Check it, change what you need, and send it to{' '}
          {draft.teamName || recipient},{' '}
          {notModelled(c)
            ? "who check the source's Message Viewer before anyone re-enters it."
            : 'who compare the systems and correct them by hand.'}
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
    </ConfirmModal>
  );
}

/**
 * Sends a saved escalation again (v1.53): the same text, unchanged, once the site has a mail server. A saved one can't be
 * edited; with no mail server set it is saved as an email file again.
 */
function SendAgain({ c, e }: { c: CaseDetail; e: Escalation }) {
  const send = useSendEscalation(c.caseId);
  const [opened, setOpened] = useState(false);
  const [key, setKey] = useState('');
  const open = () => {
    setKey(newIdempotencyKey());
    send.reset();
    setOpened(true);
  };
  const submit = () =>
    send.mutate(
      { seq: e.seq, bodyDigest: e.bodyDigest, idempotencyKey: key },
      {
        onSuccess: () => {
          setOpened(false);
          notifications.show({
            color: 'blue',
            title: byEnv({
              live: `Escalation ${e.seq} queued again`,
              trial: 'Saved in the trial, not delivered',
            }),
            message: byEnv({
              live: 'Its line shows whether the mail server took it or it was saved as an email file again.',
              trial: 'No email leaves this browser.',
            }),
          });
        },
      },
    );
  return (
    <>
      <Group>
        <Button size="xs" variant="light" onClick={open}>
          Send it again…
        </Button>
      </Group>
      <ConfirmModal opened={opened} onClose={() => setOpened(false)} title={`Send escalation ${e.seq} again`}>
        <Stack gap="sm">
          <Text size="sm" fw={600} data-testid="confirm-consequence">
            {byEnv({
              live: `This sends the same text to ${e.to} through the site's mail server. With no mail server set, it is saved as an email file again and nobody is emailed.`,
              trial: 'Sending saves it as an email file again in the trial. No email leaves this browser.',
            })}
          </Text>
          {send.error ? (
            <Alert color="red" variant="light" role="alert" title="Nothing was sent">
              {describeError(send.error)}
            </Alert>
          ) : null}
          <Group justify="flex-end">
            <Button variant="default" onClick={() => setOpened(false)}>
              Cancel
            </Button>
            <Button leftSection={<IconMailForward size={16} />} onClick={submit} loading={send.isPending}>
              Send again
            </Button>
          </Group>
        </Stack>
      </ConfirmModal>
    </>
  );
}

/**
 * Closes a case the team corrected by hand: offered once an escalation is sent or saved as an email file, or at once for a withheld case (a merge
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
          {notModelled(c)
            ? "When the team has checked the source's Message Viewer, and re-entered the message only if it needed that. Nothing is sent."
            : 'When the team has corrected the systems by hand. Nothing is sent.'}
        </Text>
      </Group>
      <ConfirmModal opened={opened} onClose={() => setOpened(false)} title={`Mark ${c.caseId} as handled`}>
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
      </ConfirmModal>
    </>
  );
}

/**
 * Escalations: when Shutter can't safely recover a message, a person sends the case to the team that owns the
 * case's receiver, who compare the systems and correct them by hand, outside HL7 (T29). Once the team has closed the
 * case, the emails stay on the page as its record: who sent each, when, and the digest of the text sent.
 */
export function EscalationPanel({
  c,
  primary = true,
}: {
  c: CaseDetail;
  /** Whether escalating is the case's next action: its button is then the main one, otherwise a secondary one. */
  primary?: boolean;
}) {
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
  const recipient = receiverTeam(c.receiver);
  const escalations = list.data ?? [];
  if (!stopped && !(handled && escalations.length)) return null;
  const pending = escalations.find((e) => e.state === 'draft' || e.state === 'failed');
  // The same rule as the action button at the top, so the button it names is here when it is pressed
  const closable = stopped && closableByHand(c, escalations);
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
          ? notModelled(c)
            ? "Shutter resends only ADT. Send it to the team, who check the source's Message Viewer before anyone re-enters it."
            : "Shutter can't recover this safely. Send it to the team."
          : 'The emails sent or saved before the team corrected the systems by hand and the case was closed.'
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
                  label={emailLabel(e.state)}
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
                  {e.state === 'saved' ? (
                    <Group gap={4}>
                      <Text size="xs" c="dimmed">
                        Queued by {e.sentBy}; saved as an email file
                      </Text>
                      <Timestamp iso={e.savedAt || e.sentAt} size="xs" />
                    </Group>
                  ) : e.sentAt ? (
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
                  {e.state === 'sent' && e.transport === 'smtp' ? (
                    <Text size="xs" c="dimmed">
                      Sent through the mail server, which accepted it; that does not show anyone has read it
                    </Text>
                  ) : null}
                </Group>
                {e.state === 'saved' ? (
                  <Text size="sm" data-testid="escalation-saved">
                    Saved as an email file, not delivered: no mail server is set, so nobody was emailed. Pass
                    the file on, or set the mail server and send it again.
                  </Text>
                ) : null}
                {['queued', 'sent', 'saved'].includes(e.state) && e.bodyDigest ? (
                  <Text size="xs" c="dimmed" className="mono-wrap">
                    Digest of the text {digestVerb(e.state)}: {e.bodyDigest}
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
                    Text removed on {formatZoned(e.purgedAt)} by the retention task; digest of the text{' '}
                    {digestVerb(e.state)} {e.bodyDigest}
                  </Text>
                ) : (
                  // A long email scrolls: the keyboard reaches it to scroll it, and a screen reader names it
                  <Code block tabIndex={0} role="region" aria-label={`The text of escalation ${e.seq}`}>
                    {e.body}
                  </Code>
                )}
                {stopped && (e.state === 'draft' || e.state === 'failed') && !e.purgedAt && me?.operator ? (
                  <Group>
                    <Button size="xs" variant="light" onClick={() => setOpen(e)}>
                      {e.state === 'failed' ? 'Check and send again…' : 'Check and send…'}
                    </Button>
                  </Group>
                ) : null}
                {stopped && e.state === 'saved' && !e.purgedAt && me?.operator ? (
                  <SendAgain c={c} e={e} />
                ) : null}
              </Stack>
            </Accordion.Panel>
          </Accordion.Item>
        </Accordion>
      ))}
      {stopped ? <ReceiverCheckCard caseId={c.caseId} /> : null}
      {/* Until the user is read, neither the actions nor the note that they need the operator role */}
      {!stopped || me === undefined ? null : me?.operator ? (
        <Group gap="sm" align="flex-end" wrap="wrap">
          {teams.length ? (
            <NativeSelect
              label="Team"
              value={teamId}
              onChange={(e) => setTeamId(e.currentTarget.value)}
              data={[
                { value: '', label: 'Automatic' },
                ...teams.map((t) => ({ value: t.id, label: `${t.name} (${t.mailbox})` })),
              ]}
              w={{ base: '100%', xs: 300 }}
            />
          ) : null}
          <Button
            className="wrap-button"
            maw="100%"
            leftSection={<IconMailForward size={16} />}
            variant={pending || !primary ? 'default' : 'filled'}
            loading={draft.isPending}
            onClick={start}
          >
            {`Escalate to ${teams.find((t) => t.id === teamId)?.name ?? recipient}…`}
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
