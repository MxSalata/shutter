import { Anchor, Button, Group, Stack, Text, Textarea } from '@mantine/core';
import { useState } from 'react';
import { useCan, useClearRecovery, useRecoveryControl, useStopRecovery } from '@/api/hooks';
import { API_BASE } from '@/api/client';
import { ErrorAlert } from '@/components/ErrorAlert';
import { Section } from '@/components/Section';
import { TRIAL } from '@/env/mode';

/**
 * Stop Shutter recovery (CONTRACTS 18): the mode, the stop and the calls still outstanding, with what it covers beside the
 * switch. Clearing enables nothing; enabling recovery is the site profile's own save. A server without the control shows
 * nothing here.
 */
export function RecoveryControlSection() {
  const control = useRecoveryControl();
  const can = useCan();
  const stop = useStopRecovery();
  const clear = useClearRecovery();
  const [reason, setReason] = useState('');
  const c = control.data;
  if (!c) return null;
  const mayClear = can.configure && can.approve;
  const words = reason.trim();
  const error = stop.error ?? clear.error;
  return (
    <Section id="recovery-control" title="Stop Shutter recovery">
      <Stack gap="sm">
        <Text size="sm">
          {c.mode === 'enabled' ? 'Recovery is enabled.' : 'Shadow mode: recovery is off.'}{' '}
          {c.stopped
            ? `Stopped by ${c.stoppedBy} at ${c.stoppedAt}${c.stopReason ? `: ${c.stopReason}` : ''}.`
            : 'Not stopped.'}
        </Text>
        <Text size="sm" c="dimmed">
          It stops: {c.covers} It does not stop: {c.doesNotCover}
        </Text>
        <Text size="sm" c="dimmed">
          A call already admitted may still reach the receiver, and stopping doesn&apos;t cancel it.{' '}
          {c.outstandingCount
            ? `${c.outstandingCount} earlier call(s) outstanding: ${c.outstanding
                .map((p) => `${p.caseId || p.kind} (${p.state})`)
                .join(', ')}.`
            : 'None is outstanding.'}
        </Text>
        {error ? <ErrorAlert error={error} title="The recovery control did not change" /> : null}
        {can.stopRecovery || mayClear ? (
          <Textarea
            label="Reason"
            required
            value={reason}
            onChange={(e) => setReason(e.currentTarget.value)}
            autosize
            minRows={1}
          />
        ) : null}
        <Group gap="sm" wrap="wrap">
          {can.stopRecovery && !c.stopped ? (
            <Button
              color="red"
              disabled={!words}
              loading={stop.isPending}
              onClick={() => stop.mutate({ reason: words }, { onSuccess: () => setReason('') })}
            >
              Stop Shutter recovery
            </Button>
          ) : null}
          {mayClear && c.stopped ? (
            <Button
              variant="default"
              disabled={!words}
              loading={clear.isPending}
              onClick={() =>
                clear.mutate(
                  { reason: words, expectedGeneration: c.generation },
                  { onSuccess: () => setReason('') },
                )
              }
            >
              {c.mode === 'enabled' ? 'Clear the stop' : 'Clear the stop, remain in shadow mode'}
            </Button>
          ) : null}
        </Group>
        {c.stopped && !mayClear ? (
          <Text size="sm" c="dimmed">
            Clearing needs a person who may both approve and configure the site.
          </Text>
        ) : null}
        {c.mode !== 'enabled' && !TRIAL ? (
          <Anchor size="sm" href={`${API_BASE}/shadow-observations.csv`}>
            Download the shadow report (CSV)
          </Anchor>
        ) : null}
      </Stack>
    </Section>
  );
}
