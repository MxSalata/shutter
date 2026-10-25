import { Button, CopyButton, Group, Text } from '@mantine/core';
import { IconCheck, IconCopy } from '@tabler/icons-react';
import { useApprovals, useAttempts, useClosure, usePlan, useSnapshot } from '@/api/hooks';
import type { CaseDetail } from '@/api/types';
import { Digest } from '@/components/Digest';
import { KeyValueList } from '@/components/KeyValueList';
import { StatusBadge } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { writes } from '@/lib/status';
import { safetyReceipt } from './receipt';
import { Section } from './Section';

/**
 * The case's safety receipt at the top of the page: the action, the digests it was bound to, the gate, who let it
 * through, the writes and the verification in one card, with the whole as JSON to copy. It reads the same queries as
 * the panels below, so it costs no extra request.
 */
export function ReceiptCard({ c, open }: { c: CaseDetail; open: boolean }) {
  const plan = usePlan(c.caseId, open);
  const approvals = useApprovals(c.caseId, open);
  const attempts = useAttempts(c.caseId, open);
  const closure = useClosure(c.caseId, !open);
  const snapshot = useSnapshot(c.caseId, open);
  const r = safetyReceipt({
    c,
    plan: plan.data,
    approvals: approvals.data,
    attempts: attempts.data,
    closure: closure.data,
    snapshot: snapshot.data,
  });
  const zero = r.writes === 0 && ['escalated', 'blocked'].includes(r.state);
  return (
    <Section
      id="receipt"
      title="Receipt"
      note={r.status}
      aside={
        <>
          <StatusBadge {...writes(r.writes)} />
          <CopyButton value={JSON.stringify(r, null, 2)} timeout={1500}>
            {({ copied, copy }) => (
              <Button
                size="xs"
                variant="light"
                leftSection={copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
                onClick={copy}
              >
                {copied ? 'Copied' : 'Copy JSON'}
              </Button>
            )}
          </CopyButton>
        </>
      }
    >
      <KeyValueList
        rows={[
          ['Proposed action', r.action],
          ['Catalogue entry', r.catalogueEntry],
          [
            'Plan',
            r.planDigest ? (
              <Digest key="p" value={r.planDigest} label="plan digest" />
            ) : (
              <Text size="sm" c="dimmed">
                none yet
              </Text>
            ),
          ],
          [
            'Evidence',
            r.snapshotDigest ? <Digest key="s" value={r.snapshotDigest} label="snapshot digest" /> : '',
          ],
          [
            'Receiver',
            r.expectedVersion
              ? `version ${r.expectedVersion}${r.receiverEpoch ? `, epoch ${r.receiverEpoch}` : ''}`
              : '',
          ],
          [
            'Gate',
            r.gate
              ? `${r.gate.outcome === 'pass' ? 'Passed' : r.gate.outcome === 'block' ? 'Blocked' : 'Unknown: write blocked'} at ${r.gate.stage}, policy ${r.gate.policyVersion}`
              : 'Not checked yet',
          ],
          [
            'Decided by',
            r.decidedAt ? (
              <Group key="d" gap={6}>
                <Text size="sm">{`${r.decidedBy},`}</Text>
                <Timestamp iso={r.decidedAt} />
              </Group>
            ) : (
              r.decidedBy
            ),
          ],
          [
            'Writes to the receiver',
            [
              r.writes
                ? `${r.writes}, ${r.acknowledged} acknowledged`
                : zero
                  ? '0: nothing was written'
                  : '0',
              r.notWritten
                ? `${r.notWritten} attempt${r.notWritten === 1 ? '' : 's'} the receiver did not take`
                : '',
            ]
              .filter(Boolean)
              .join('; '),
          ],
          ['Verification', r.verification || 'Not verified yet'],
        ]}
      />
    </Section>
  );
}
