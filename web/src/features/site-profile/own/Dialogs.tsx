import { Alert, Button, Code, Group, Stack, Text, TextInput, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useId, useState } from 'react';
import { readOnlyDemo } from '@/api/can';
import { DEMO_LOCKED, saveLocked } from '@/api/saveLocked';
import { useCan, useSiteEntries } from '@/api/hooks';
import type { SiteEntryContent, SiteEntryDetail, SiteEntryProofResult } from '@/api/types';
import { ConfirmModal } from '@/components/ConfirmModal';
import { LockedNote, LockedSaveButton } from '@/components/LockedSave';
import { byEnv, toBecomeApprover } from '@/env/copy';
import { describeError } from '@/lib/errors';
import { useTechnical } from '@/stores/appearance';
import { useDecide, usePropose, useProve, useSuspend, useValidation, versionOf, type Action } from './api';
import { ProofTable } from './ProofTable';
import { ACTION_WORDS, chipLabel, displacesWords, entryYaml } from './words';

/**
 * The three dialogs of the site's own scenarios, in the review dialog's shape (the site profile's `ReviewModal`):
 * sending an action for approval, a second person's approval or rejection, and one approver's suspension. Each shows
 * what the core holds and sends what the person read (the action, the version, the digest) or wrote (a reason); the
 * core decides whether it may be done, and its refusal is shown as it came.
 */

/** The YAML wraps rather than scrolls, so no part of it is a region only a mouse can scroll. */
const YAML_STYLE = { whiteSpace: 'pre-wrap' as const, overflowWrap: 'anywhere' as const };

/** The summary both dialogs open with: the sentence, the exact pattern, what it displaces, the action and the digest. */
function Summary({
  entry,
  action,
  version,
  digest,
  content,
}: {
  entry: SiteEntryDetail;
  action: Action;
  version: number;
  digest: string;
  content?: SiteEntryContent;
}) {
  const technical = useTechnical();
  const validation = useValidation(content ? { ...content, fixtures: [] } : undefined);
  const pattern = Object.entries(content?.pattern ?? {});
  const scope = Object.entries(content?.scope ?? {});
  return (
    <Stack gap="xs" data-testid="own-summary">
      <Text size="sm" fw={600}>
        {`${entry.id}, version ${version}: ${ACTION_WORDS[action]}`}
      </Text>
      <Text size="sm">
        {validation.data?.sentence
          ? `${validation.data.sentence}.`
          : entry.sentence
            ? `${entry.sentence}.`
            : ''}
      </Text>
      <Text size="sm">
        {'The exact pattern: '}
        {pattern.map(([c, v]) => chipLabel(c, v, technical)).join('; ')}
        {scope.length
          ? `; only ${scope.map(([k, v]) => `${k.replace(/_/g, ' ')} ${v.join(' or ')}`).join(', ')}`
          : ''}
        .
      </Text>
      <Text size="sm" data-testid="own-displaces">
        {validation.data
          ? displacesWords(validation.data.overlap)
          : validation.isError
            ? 'What it displaces could not be read.'
            : 'Reading what it displaces…'}
      </Text>
      <Text size="xs" c="dimmed" ff="monospace" style={{ overflowWrap: 'anywhere' }} data-testid="own-digest">
        {`action ${action}, version ${version}, digest ${digest}`}
      </Text>
      {content ? (
        <Code block style={YAML_STYLE} data-testid="own-summary-yaml">
          {entryYaml({ ...content, id: entry.id })}
        </Code>
      ) : null}
    </Stack>
  );
}

/**
 * Send an action for a second person's approval: activate the draft, retire or resume the active version. A passing
 * proof of the version's digest is needed first (the core refuses otherwise); a retirement's or a resumption's proof
 * is run here.
 */
export function SendDialog({
  entry,
  action,
  onClose,
}: {
  entry: SiteEntryDetail;
  action: Action;
  onClose: () => void;
}) {
  const can = useCan();
  const locked = saveLocked(can);
  const lockedId = useId();
  const v = versionOf(entry, action);
  const stored = entry.proofs.find((p) => p.action === action && p.digest === v?.digest);
  const [proof, setProof] = useState<SiteEntryProofResult | null>(stored?.result ?? null);
  const [problem, setProblem] = useState('');
  const prove = useProve(entry.id);
  const propose = usePropose(entry.id);
  const busy = prove.isPending || propose.isPending;
  const title =
    action === 'activate'
      ? `Send version ${v?.version ?? ''} of ${entry.id} for approval`
      : action === 'retire'
        ? `Propose retiring ${entry.id}`
        : `Propose resuming ${entry.id}`;
  return (
    <ConfirmModal
      opened
      onClose={() => (busy ? undefined : onClose())}
      title={title}
      chip
      size="lg"
      locked={busy}
    >
      <Stack gap="sm">
        <Text size="md" fw={600}>
          {byEnv({
            live: 'A second person approves it before anything changes.',
            trial: "In the trial this changes only this browser's copy, until you reload or leave.",
          })}
        </Text>
        {action === 'retire' ? (
          <Alert color="yellow" variant="light">
            Retiring it takes this site&apos;s brake away: the cases it catches go back to what the shipped
            catalogue does with them. The proof below lists them.
          </Alert>
        ) : null}
        {v ? (
          <Summary entry={entry} action={action} {...v} />
        ) : (
          <Text size="sm">No version to {action}.</Text>
        )}
        {proof ? (
          <ProofTable proof={proof} />
        ) : (
          <Text size="sm">No proof of this version for this action yet.</Text>
        )}
        {problem ? (
          <Alert color="red" variant="light" role="alert" title="Nothing was sent">
            {problem}
          </Alert>
        ) : null}
        {locked ? (
          <Group justify="flex-end">
            <LockedNote id={lockedId}>{locked}</LockedNote>
          </Group>
        ) : null}
        <Group justify="flex-end" gap="sm" wrap="wrap">
          <Button variant="default" onClick={onClose} disabled={busy}>
            Cancel
          </Button>
          {locked ? (
            <LockedSaveButton label="Send for approval" noteId={lockedId} />
          ) : (
            <>
              <Button
                variant="default"
                loading={prove.isPending}
                disabled={busy}
                onClick={() =>
                  prove.mutate(action, {
                    onSuccess: (r) => {
                      setProblem('');
                      setProof(r);
                    },
                    onError: (e) => setProblem(describeError(e)),
                  })
                }
              >
                {proof ? 'Prove it again' : 'Prove it'}
              </Button>
              <Button
                loading={propose.isPending}
                disabled={busy || !proof?.passed}
                onClick={() =>
                  propose.mutate(action, {
                    onSuccess: () => {
                      notifications.show({
                        color: 'teal',
                        message: `${entry.id}: sent for approval. It changes nothing until a second person approves it.`,
                      });
                      onClose();
                    },
                    onError: (e) => setProblem(describeError(e)),
                  })
                }
              >
                Send for approval
              </Button>
            </>
          )}
        </Group>
      </Stack>
    </ConfirmModal>
  );
}

/**
 * A second person's review of a waiting proposal, in the review dialog's shape: the summary, the proof it was made on,
 * the impact, the plans that will not complete under the old version, a reason, the optional safety reference, and
 * Approve and Reject. The author reads why they cannot approve their own; the core refuses it anyway (409
 * same_person), unless an IRIS administrator lifted the two-person rule, which the dialog then says.
 */
export function ApprovalDialog({
  entry,
  me,
  onClose,
}: {
  entry: SiteEntryDetail;
  me: string;
  onClose: () => void;
}) {
  const can = useCan();
  const list = useSiteEntries().data;
  const decide = useDecide(entry.id);
  const lockedId = useId();
  const [reason, setReason] = useState('');
  const [reference, setReference] = useState('');
  const [problem, setProblem] = useState('');
  const p = entry.proposal!;
  const action = p.action;
  const v = entry.versions.find((x) => x.version === p.version);
  const content = versionOf(entry, action)?.content;
  const proof = entry.proofs.find((x) => String(x.id) === String(p.proofId))?.result;
  const onePerson = list?.status.onePerson ?? null;
  const author = me !== '' && (me === p.by || (action === 'activate' && me === v?.writtenBy));
  // Why this reader cannot decide here: no approval right, or the public demo's (which changes nothing of the site), as
  // the site profile's Save says it. The author may still reject (withdraw) their own, and reads why they cannot approve
  const cannot = !can.approve
    ? `Only an approver approves here: ${toBecomeApprover()}.`
    : readOnlyDemo(can)
      ? DEMO_LOCKED
      : null;
  const locked =
    cannot ??
    (author && !onePerson
      ? `You ${me === p.by ? 'proposed this' : 'wrote this version'}: a second person approves it, so that no one person adds or removes a brake alone.`
      : null);
  const waiting = list?.waitingPlans;
  const send = (decision: 'approve' | 'reject') => {
    setProblem('');
    if (!reason.trim()) {
      setProblem('A reason is needed, for the record.');
      return;
    }
    decide.mutate(
      {
        action,
        version: p.version,
        digest: p.digest,
        decision,
        reason: reason.trim(),
        ...(reference.trim() ? { safetyReference: reference.trim() } : {}),
      },
      {
        onSuccess: (r) => {
          notifications.show({
            color: 'teal',
            message:
              decision === 'reject'
                ? `${entry.id}: rejected. The draft stays, with your reason.`
                : `${entry.id}: approved.${typeof r.waitingPlans === 'number' ? ` ${r.waitingPlans} waiting ${r.waitingPlans === 1 ? 'plan was' : 'plans were'} made under the old version and will be planned again.` : ''}`,
          });
          onClose();
        },
        onError: (e) => setProblem(describeError(e)),
      },
    );
  };
  return (
    <ConfirmModal
      opened
      onClose={() => (decide.isPending ? undefined : onClose())}
      title={`Approve or reject: ${entry.id} version ${p.version}`}
      chip
      size="lg"
      locked={decide.isPending}
    >
      <Stack gap="sm" data-testid="own-approval">
        <Text size="md" fw={600}>
          {byEnv({
            live: 'This changes what Shutter does at this hospital from the next case.',
            trial: "In the trial, approving changes only this browser's copy, until you reload or leave.",
          })}
        </Text>
        <Text size="sm">{`Proposed by ${p.by}.`}</Text>
        <Summary entry={entry} action={action} version={p.version} digest={p.digest} content={content} />
        {proof ? (
          <ProofTable proof={proof} testId="own-approval-proof" />
        ) : (
          <Text size="sm">The proof it was proposed on cannot be read here; the approval runs it again.</Text>
        )}
        <Alert color="blue" variant="light" data-testid="own-waiting">
          {typeof waiting === 'number'
            ? `${waiting} open ${waiting === 1 ? 'case has a plan' : 'cases have plans'} made under the catalogue version in force. Once this is approved none of them completes under it: each is planned again on fresh evidence.`
            : 'Open cases with a plan made under the catalogue version in force do not complete under it once this is approved: each is planned again.'}
        </Alert>
        {onePerson && author ? (
          <Alert color="yellow" variant="light">
            {`The two-person rule is lifted (by ${onePerson.by}): you may approve your own, and the record will say so.`}
          </Alert>
        ) : null}
        <Textarea
          label="Reason"
          required
          autosize
          minRows={2}
          value={reason}
          onChange={(e) => setReason(e.currentTarget.value)}
        />
        <TextInput
          label="Safety reference"
          description="Optional: your own safety record for this change, such as a hazard log entry. Shutter keeps it and checks nothing."
          value={reference}
          onChange={(e) => setReference(e.currentTarget.value)}
        />
        {problem ? (
          <Alert color="red" variant="light" role="alert" title="Nothing was changed">
            {problem}
          </Alert>
        ) : null}
        {locked ? (
          <Group justify="flex-end">
            <LockedNote id={lockedId}>{locked}</LockedNote>
          </Group>
        ) : null}
        <Group justify="flex-end" gap="sm" wrap="wrap">
          <Button variant="default" onClick={onClose} disabled={decide.isPending}>
            Cancel
          </Button>
          {cannot ? (
            <LockedSaveButton label="Reject" noteId={lockedId} />
          ) : (
            <Button variant="light" color="red" loading={decide.isPending} onClick={() => send('reject')}>
              Reject
            </Button>
          )}
          {locked ? (
            <LockedSaveButton label="Approve" noteId={lockedId} />
          ) : (
            <Button loading={decide.isPending} onClick={() => send('approve')}>
              Approve
            </Button>
          )}
        </Group>
      </Stack>
    </ConfirmModal>
  );
}

/** One approver switches an active entry off at once, with a reason (R12); resuming it takes two people. */
export function SuspendDialog({ entry, onClose }: { entry: SiteEntryDetail; onClose: () => void }) {
  const suspend = useSuspend(entry.id);
  const [reason, setReason] = useState('');
  const [problem, setProblem] = useState('');
  return (
    <ConfirmModal
      opened
      onClose={() => (suspend.isPending ? undefined : onClose())}
      title={`Suspend ${entry.id}`}
      chip
      locked={suspend.isPending}
    >
      <Stack gap="sm">
        <Text size="sm">
          Its protection is off at once: the cases it catches go back to what the shipped catalogue does with
          them. The page and the Doctor warn for as long as it lasts, and resuming it needs a proposal and a
          second person.
        </Text>
        <Textarea
          label="Reason"
          required
          autosize
          minRows={2}
          value={reason}
          onChange={(e) => setReason(e.currentTarget.value)}
        />
        {problem ? (
          <Alert color="red" variant="light" role="alert" title="Nothing was changed">
            {problem}
          </Alert>
        ) : null}
        <Group justify="flex-end" gap="sm">
          <Button variant="default" onClick={onClose} disabled={suspend.isPending}>
            Cancel
          </Button>
          <Button
            color="red"
            loading={suspend.isPending}
            onClick={() => {
              if (!reason.trim()) return setProblem('A reason is needed, for the record.');
              suspend.mutate(reason.trim(), {
                onSuccess: () => {
                  notifications.show({ color: 'teal', message: `${entry.id} is suspended.` });
                  onClose();
                },
                onError: (e) => setProblem(describeError(e)),
              });
            }}
          >
            Suspend now
          </Button>
        </Group>
      </Stack>
    </ConfirmModal>
  );
}
