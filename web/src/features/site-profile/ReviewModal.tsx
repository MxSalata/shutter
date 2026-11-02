import { Accordion, Alert, Button, Checkbox, Group, List, Modal, Stack, Text } from '@mantine/core';
import { useState } from 'react';
import { DEMO_READ_ONLY } from '@/api/can';
import type { SiteProfile, SiteProfileView } from '@/api/types';
import { EnvChip } from '@/components/EnvChip';
import { JsonBlock } from '@/components/JsonBlock';
import { byEnv } from '@/env/copy';
import type { Change } from './profile';

export type SaveProblem =
  { kind: 'stale'; currentVersion: number | null } | { kind: 'error'; message: string } | null;

/**
 * What a save changes, in words, before anything is sent: the changes, what takes a person out of a release, what
 * happens to approvals made under the version in force, and the exact body.
 */
export function ReviewModal({
  opened,
  view,
  changes,
  body,
  saving,
  readOnly = false,
  problem,
  onCancel,
  onSave,
  onLoadTheirs,
}: {
  opened: boolean;
  view: SiteProfileView;
  changes: Change[];
  body: SiteProfile & { expectedVersion: number };
  saving: boolean;
  /** The public demo: the changes are shown for reading, and a note stands where Save would be. */
  readOnly?: boolean;
  problem: SaveProblem;
  onCancel: () => void;
  onSave: () => void;
  onLoadTheirs: () => void;
}) {
  const next = view.version + 1;
  const tier3 = changes.filter((c) => c.tier3Automatic);
  const lessOversight = changes.filter((c) => c.lessOversight);
  const [acknowledged, setAcknowledged] = useState(false);
  const confirmOnly = changes.length === 0;
  return (
    <Modal
      opened={opened}
      onClose={() => (saving ? undefined : onCancel())}
      title={
        <span style={{ display: 'inline-flex', flexWrap: 'wrap', alignItems: 'center', gap: 8 }}>
          {readOnly
            ? `The changes for version ${next} of the site profile`
            : confirmOnly
              ? `Confirm the answers as version ${next}`
              : `Save version ${next} of the site profile`}
          {readOnly ? null : <EnvChip />}
        </span>
      }
      size="lg"
    >
      <Stack gap="sm">
        {readOnly ? null : (
          <Text size="md" fw={600}>
            {byEnv({
              live: 'This changes what Shutter does at this hospital from the next case.',
              trial: "In the trial, saving changes only this browser's copy, until you reload or leave.",
            })}
          </Text>
        )}
        {confirmOnly ? (
          <Text size="sm">
            The answers stay as they are, and are recorded as answered by you: the shipped answers stop being
            the ones in force.
          </Text>
        ) : (
          <>
            <Text size="sm">What changes:</Text>
            <List size="sm" spacing={2}>
              {changes.map((c, i) => (
                <List.Item key={i}>
                  {c.text}
                  {c.lessOversight ? ' (less oversight: no person approves these releases)' : ''}
                </List.Item>
              ))}
            </List>
          </>
        )}
        {lessOversight.length ? (
          <Alert color="yellow" variant="light" title="Fewer releases wait for a person">
            {lessOversight.length === 1 ? 'This change takes' : 'These changes take'} a person's approval out
            of releases that needed one. They are still gated, rehearsed and verified, and a chain still stops
            at the first surprise.
          </Alert>
        ) : null}
        {tier3.length && !readOnly ? (
          <Checkbox
            checked={acknowledged}
            onChange={(e) => setAcknowledged(e.currentTarget.checked)}
            label={`I mean it: some releases at clinical-safety tier 3 (${tier3.map((c) => c.text.replace(/:.*/, '')).join('; ')}) will go with no person's approval`}
          />
        ) : null}
        {readOnly ? null : (
          <Alert color="blue" variant="light">
            Open cases that have not reached their approval use it too. Approvals and incident plans made
            under version {view.version} are refused at release and come back to a person. Cases and incidents
            opened from now on use version {next}.
          </Alert>
        )}
        <Accordion variant="contained" chevronPosition="left">
          <Accordion.Item value="body">
            <Accordion.Control aria-label={readOnly ? 'What would be sent' : 'What is sent'}>
              <Text size="sm">{readOnly ? 'What would be sent' : 'What is sent'}</Text>
            </Accordion.Control>
            <Accordion.Panel>
              <JsonBlock value={body} label="the profile that is sent" />
            </Accordion.Panel>
          </Accordion.Item>
        </Accordion>
        {problem?.kind === 'stale' ? (
          <Alert color="red" variant="light" role="alert" title="Nothing was saved">
            <Stack gap="xs">
              <Text size="sm">
                Version {problem.currentVersion ?? 'a newer one'} was saved by someone else while you were
                editing. Your changes are kept: close this and review them against version{' '}
                {problem.currentVersion ?? 'the newer one'} before saving, or load their answers instead of
                yours.
              </Text>
              <Group gap="sm">
                <Button size="xs" variant="light" onClick={onLoadTheirs}>
                  Load their answers
                </Button>
                <Button size="xs" variant="default" onClick={onCancel}>
                  Keep editing
                </Button>
              </Group>
            </Stack>
          </Alert>
        ) : null}
        {problem?.kind === 'error' ? (
          <Alert color="red" variant="light" role="alert" title="Nothing was saved">
            {problem.message}
          </Alert>
        ) : null}
        <Group justify="flex-end" gap="sm">
          {readOnly ? (
            <Text size="sm" c="dimmed" data-testid="demo-read-only">
              {DEMO_READ_ONLY}.
            </Text>
          ) : null}
          <Button variant="default" onClick={onCancel} disabled={saving}>
            {readOnly ? 'Done' : 'Cancel'}
          </Button>
          {readOnly ? null : (
            <Button
              loading={saving}
              disabled={(tier3.length > 0 && !acknowledged) || problem?.kind === 'stale'}
              onClick={onSave}
            >
              {confirmOnly ? `Confirm as version ${next}` : `Save version ${next}`}
            </Button>
          )}
        </Group>
      </Stack>
    </Modal>
  );
}
