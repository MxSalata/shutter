import { Alert, Button, Group, Text } from '@mantine/core';
import { useMutation, useQueryClient } from '@tanstack/react-query';
import { fetchCaseBundle, saveTextFile } from '@/api/bundle';
import { keys, useMe } from '@/api/hooks';
import { NOT_IN_TRIAL } from '@/env/copy';
import { TRIAL } from '@/env/mode';
import { describeError } from '@/lib/errors';

/**
 * One case's file for audit or a support handoff: evidence, plans, gate decisions, approvals, attempts, verification
 * and the closure receipt, with identifiers redacted (its first line says so), and a record on the case of who took it.
 * For operators. The trial shows it disabled with its reason, as its recording has no such file.
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
    </>
  );
}
