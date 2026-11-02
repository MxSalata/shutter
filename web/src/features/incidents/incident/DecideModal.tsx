import { Alert, Button, Group, Stack, Text, Textarea } from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { useState } from 'react';
import { newIdempotencyKey } from '@/api/client';
import { useDecideIncident } from '@/api/hooks';
import type { Chain, IncidentDetail } from '@/api/types';
import { ConfirmModal } from '@/components/ConfirmModal';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { TechDetail } from '@/components/TechDetail';
import { byEnv } from '@/env/copy';
import { describeError, isApiError } from '@/lib/errors';
import { plural } from '@/lib/format';
import { ApproveWords } from './ApproveWords';

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
                ? byEnv({
                    live: 'The chains are released in order; each operation is checked again just before it goes.',
                    trial: 'The recorded chains go out in order. Nothing leaves this browser.',
                  })
                : 'Nothing is sent for these chains: their cases go to a person.',
          });
        },
      },
    );
  };
  const changed = decide.error && isApiError(decide.error) && decide.error.code === 'plan_changed';
  const what = chain ? `chain ${chain.seq} (${chain.encounterId})` : `${plural(covered.length, 'chain')}`;
  const modal = (
    <ConfirmModal
      opened={decision !== null}
      onClose={close}
      title={decision === 'approve' ? `Approve the release of ${what}` : `Reject the release of ${what}`}
      size="lg"
    >
      <Stack gap="sm">
        {decision === 'approve' ? (
          <ApproveWords operations={operations} receiver={inc.receiver} />
        ) : (
          <Text size="sm">
            You reject the release: nothing is sent for these chains, and their cases go to a person with the
            reason.
          </Text>
        )}
        <KeyValueList
          rows={[['Chains', covered.map((c) => `${c.seq} (${c.encounterId})`).join(', ')]]}
          labelWidth={120}
        />
        <TechDetail label="What this decision is bound to" kind="data">
          <KeyValueList
            rows={[['Plan digest', <Digest key="p" value={inc.planDigest} label="incident plan digest" />]]}
            labelWidth={120}
          />
        </TechDetail>
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
    </ConfirmModal>
  );
  return { open, modal };
}
