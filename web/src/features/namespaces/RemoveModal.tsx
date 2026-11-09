import { Button, Checkbox, Group, List, Stack, Text } from '@mantine/core';
import { useState } from 'react';
import { ConfirmModal } from '@/components/ConfirmModal';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { useRemovalPreview } from './onboarding';

/**
 * What taking a namespace off would touch, from the record of what the apply did, before anything goes; what stays is
 * said too. A mapping or a draft may still stay, for the reasons the answer then gives.
 */
export function RemoveModal({
  ns,
  onClose,
  onRemove,
}: {
  ns: string | null;
  onClose: () => void;
  onRemove: (unmap: boolean, credential: boolean) => void;
}) {
  const preview = useRemovalPreview(ns);
  const [unmap, setUnmap] = useState(false);
  const [credential, setCredential] = useState(false);
  const p = preview.data;
  const lines = p
    ? [
        ...p.items.map((i) => `The item ${i} of ${p.production}`),
        ...(p.renamed ? [`The name ${p.renamed}: the site's item is Ens.Alert again`] : []),
        ...p.alertOnError.map((i) => `AlertOnError on ${i}`),
        ...p.drafted.map((d) => `The draft receiver ${d} in the site profile, if nobody has edited it`),
        ...p.mappings.map((m) => `The mapping of ${m}, if no message of Shutter's classes is left in ${ns}`),
      ]
    : [];
  return (
    <ConfirmModal title={`Take ${ns ?? ''} off`} opened={ns !== null} onClose={onClose}>
      <Stack gap="md">
        {preview.isPending ? <PageSkeleton label="Reading what the apply did…" /> : null}
        {preview.isError ? <ErrorAlert error={preview.error} title="The record could not be read" /> : null}
        {p ? (
          <>
            <Text size="sm">Nothing has changed yet. This would go:</Text>
            <List size="sm" spacing={4}>
              {lines.map((l) => (
                <List.Item key={l}>{l}</List.Item>
              ))}
            </List>
            <Text size="sm">
              Shutter&apos;s cases from {ns} and the schemas imported from it stay. The production is updated,
              not stopped.
            </Text>
            <Checkbox
              label="Take the mappings even if messages of Shutter's classes are left there"
              checked={unmap}
              onChange={(e) => setUnmap(e.currentTarget.checked)}
            />
            <Checkbox
              label="Take the credential too, and its user if no other namespace signs in with it"
              checked={credential}
              onChange={(e) => setCredential(e.currentTarget.checked)}
            />
          </>
        ) : null}
        <Group justify="flex-end">
          <Button variant="default" onClick={onClose}>
            Cancel
          </Button>
          <Button color="red" disabled={!p} onClick={() => onRemove(unmap, credential)}>
            Take it off
          </Button>
        </Group>
      </Stack>
    </ConfirmModal>
  );
}
