import { Alert, Button, Group, Stack, Text, Textarea } from '@mantine/core';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { useState } from 'react';
import { fetchCaseBundle, fetchUnredactedCaseBundle, saveTextFile } from '@/api/bundle';
import { keys, useMe } from '@/api/hooks';
import { NOT_IN_TRIAL } from '@/env/copy';
import { TRIAL } from '@/env/mode';
import { describeError } from '@/lib/errors';

/**
 * One case's file for audit or a support handoff: evidence, plans, gate decisions, approvals, attempts, verification
 * and the closure receipt, with identifiers redacted (its first line says so), and a record on the case of who took it.
 * For operators. The trial shows it disabled with its reason, as its recording has no such file. An approver can also
 * take it with the identifiers in, by typing why: the reason goes on the case and the file's first line says what it holds.
 */
export function CaseBundleDownload({ caseId }: { caseId: string }) {
  const me = useMe().data;
  const client = useQueryClient();
  const download = useMutation({
    mutationFn: () => fetchCaseBundle(caseId),
    onSuccess: ({ text, filename }) => {
      saveTextFile(text, filename);
    },
    // The download's record is on the case's timeline.
    onSettled: () => client.invalidateQueries({ queryKey: keys.case(caseId) }),
  });
  if (TRIAL)
    return (
      <Group gap="sm" wrap="wrap">
        <Button variant="default" disabled aria-describedby="case-bundle-reason">
          Download case bundle
        </Button>
        <Text size="xs" c="dimmed" id="case-bundle-reason">
          {NOT_IN_TRIAL.recording}
        </Text>
      </Group>
    );
  if (!me?.operator) return null;
  return (
    <>
      <Group gap="sm" wrap="wrap">
        <Button variant="default" onClick={() => download.mutate()} loading={download.isPending}>
          Download case bundle
        </Button>
        <Text size="xs" c="dimmed">
          Identifiers redacted. Recorded on the case.
        </Text>
      </Group>
      {download.isError ? (
        <Alert color="red" role="alert" mt="xs">
          {describeError(download.error)}
        </Alert>
      ) : null}
      {me.approver ? <UnredactedBundle caseId={caseId} /> : null}
    </>
  );
}

function UnredactedBundle({ caseId }: { caseId: string }) {
  const client = useQueryClient();
  const [open, setOpen] = useState(false);
  const [reason, setReason] = useState('');
  const download = useMutation({
    mutationFn: () => fetchUnredactedCaseBundle(caseId, reason.trim()),
    onSuccess: ({ text, filename }) => {
      saveTextFile(text, filename);
      setOpen(false);
      setReason('');
    },
    onSettled: () => client.invalidateQueries({ queryKey: keys.case(caseId) }),
  });
  if (!open)
    return (
      <Group mt="xs">
        <Button variant="subtle" size="xs" onClick={() => setOpen(true)}>
          Download with identifiers
        </Button>
      </Group>
    );
  return (
    <Stack gap="xs" mt="xs">
      <Text size="sm">This file holds identifiable patient data. Your reason goes on the case.</Text>
      <Textarea
        label="Why you need the identifiers"
        required
        autosize
        minRows={2}
        value={reason}
        onChange={(e) => setReason(e.currentTarget.value)}
      />
      <Group gap="sm" wrap="wrap">
        <Button
          variant="default"
          disabled={reason.trim() === ''}
          loading={download.isPending}
          onClick={() => download.mutate()}
        >
          Download unredacted bundle
        </Button>
        <Button variant="subtle" onClick={() => setOpen(false)}>
          Cancel
        </Button>
      </Group>
      {download.isError ? (
        <Alert color="red" role="alert">
          {describeError(download.error)}
        </Alert>
      ) : null}
    </Stack>
  );
}
