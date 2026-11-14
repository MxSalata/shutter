import { Stack, Text } from '@mantine/core';
import { KeyValueList } from '@/components/KeyValueList';
import type { ChangeRow } from './staleReview';

/**
 * What changed between a review that was stopped and the case as read now (`whatChanged`): the case's state when it
 * moved, then one row each for the plan, its action, the receiver version its write is conditional on, the evidence and
 * the case version. A changed row reads its new value with the old one after it (evidence read again with the same
 * words has no old one); an unchanged row says so, so the reader sees what still holds.
 */
export function WhatChanged({ rows }: { rows: ChangeRow[] }) {
  return (
    <Stack gap={4} data-testid="what-changed">
      <Text size="sm" fw={600}>
        What changed
      </Text>
      <KeyValueList
        labelWidth={150}
        rows={rows.map((r) => [
          r.label,
          r.changed ? (
            <Text size="sm" data-changed="true">
              <Text span inherit fw={600}>
                {r.now}
              </Text>
              {r.was ? <Text span inherit c="dimmed">{` (was ${r.was})`}</Text> : null}
            </Text>
          ) : (
            <Text size="sm" c="dimmed">{`Unchanged: ${r.now}`}</Text>
          ),
        ])}
      />
    </Stack>
  );
}
