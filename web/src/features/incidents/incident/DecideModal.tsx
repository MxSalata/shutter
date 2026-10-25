import { Alert, Button, Group, Modal, Stack, Text, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { newIdempotencyKey } from '@/api/client';
import { useDecideIncident } from '@/api/hooks';
import type { Chain, IncidentDetail } from '@/api/types';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { describeError, isApiError } from '@/lib/errors';

export type Decision = 'approve' | 'reject';

/**
 * The decision on an incident's release: the policy chains under the incident's approval, or one chain under its own
 * (chain set). The approval binds the plan's digest; a digest that moved answers 409 plan_changed.
 */
export function useDecideDialog(inc: IncidentDetail) {
  const decide = useDecideIncident(inc.incidentId);
  const [decision, setDecision] = useState<Decision | null>(null);
  const [chain, setChain] = useState<Chain | null>(null);
  const [comment, setComment] = useState('');
  const [key, setKey] = useState('');
  const open = (d: Decision, forChain: Chain | null = null) => {
    setDecision(d);
    setChain(forChain);
    setComment('');
    setKey(newIdempotencyKey());
    decide.reset();
  };
  const close = () => setDecision(null);
  const covered = chain
    ? [chain]
    : inc.chains.filter((c) => c.decides === 'policy' && c.policy === 'approval');
  const operations = covered.reduce((n, c) => n + c.items.length, 0);
  const submit = () => {
    if (!decision || !inc.planDigest) return;
    decide.mutate(
      {
        decision: { decision, planDigest: inc.planDigest, comment },
        chainSeq: chain?.seq,
        idempotencyKey: key,
      },
      {
        onSuccess: () => {
          setDecision(null);
          notifications.show({
            color: decision === 'approve' ? 'blue' : 'gray',
            title: decision === 'approve' ? 'Approved' : 'Rejected',
            message:
              decision === 'approve'
                ? 'The chains are released in order; each operation is checked again just before it goes.'
                : 'Nothing is sent for these chains: their cases go to a person.',
          });
        },
      },
    );
  };
  const changed = decide.error && isApiError(decide.error) && decide.error.code === 'plan_changed';
  const what = chain
    ? `chain ${chain.seq} (${chain.encounterId})`
    : `${covered.length} chain${covered.length === 1 ? '' : 's'}`;
  const modal = (
    <Modal
      opened={decision !== null}
      onClose={close}
      title={decision === 'approve' ? `Approve the release of ${what}` : `Reject the release of ${what}`}
      size="lg"
    >
      <Stack gap="sm">
        <Text size="sm">
          {decision === 'approve'
            ? `You approve exactly this: resend these ${operations} operation${operations === 1 ? '' : 's'} to ${inc.receiver}, in this order. Each one is rehearsed, gated and verified just before it goes, and goes at exactly the receiver version the one before it verified; a chain stops at the first surprise, and the rest comes back to a person. Each operation goes only under the catalogue entry and outcome listed for it; one whose fresh evidence reads differently stops its chain and comes back to a person.`
            : 'You reject the release: nothing is sent for these chains, and their cases go to a person with the reason.'}
        </Text>
        <KeyValueList
          rows={[
            ['Plan digest', <Digest key="p" value={inc.planDigest} label="incident plan digest" />],
            ['Chains', covered.map((c) => `${c.seq} (${c.encounterId})`).join(', ')],
          ]}
        />
        <Textarea
          label="Comment"
          description="Recorded with your decision"
          autosize
          minRows={2}
          value={comment}
          onChange={(e) => setComment(e.currentTarget.value)}
        />
        {decide.error ? (
          <Alert color="red" variant="light" role="alert">
            {changed
              ? "The incident's plan changed since this page loaded: close this and review it again."
              : describeError(decide.error)}
          </Alert>
        ) : null}
        <Group justify="flex-end" gap="sm">
          <Button variant="default" onClick={close}>
            Cancel
          </Button>
          <Button
            color={decision === 'approve' ? undefined : 'red'}
            loading={decide.isPending}
            onClick={submit}
            disabled={!!changed || !inc.planDigest}
          >
            {decision === 'approve' ? 'Approve the release' : 'Reject the release'}
          </Button>
        </Group>
      </Stack>
    </Modal>
  );
  return { open, modal };
}
