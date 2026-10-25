import { Accordion, Badge, Group, List, Stack, Text } from '@mantine/core';
import { useSiteProfileHistory } from '@/api/hooks';
import { ErrorAlert } from '@/components/ErrorAlert';
import { JsonBlock } from '@/components/JsonBlock';
import { PageSkeleton } from '@/components/PageSkeleton';
import { formatZoned } from '@/lib/format';
import { NotYet, Section } from '../cases/case/Section';
import { describeSource, diffProfiles } from './profile';

/** Every stored version, newest first, each with what changed from the one before it. */
export function VersionsPanel({ current }: { current: number }) {
  const history = useSiteProfileHistory();
  const entries = history.data ?? [];
  return (
    <Section
      id="site-versions"
      title="Versions"
      note="Every saved version is kept, with who saved it and from where. Approvals and incident plans made under an earlier version are refused at release and come back to a person."
    >
      {history.isPending ? <PageSkeleton label="Loading the versions…" /> : null}
      {history.isError ? (
        <ErrorAlert
          error={history.error}
          title="The versions could not be read"
          onRetry={() => void history.refetch()}
        />
      ) : null}
      {history.isSuccess && !entries.length ? <NotYet>No version stored yet.</NotYet> : null}
      {entries.length ? (
        <Accordion variant="separated" chevronPosition="left">
          {entries.map((e, i) => {
            const older = entries[i + 1];
            const changes = e.profile && older ? diffProfiles(older.profile, e.profile) : [];
            return (
              <Accordion.Item key={e.version} value={String(e.version)}>
                <Accordion.Control>
                  <Group gap={6} wrap="wrap">
                    <Text size="sm" fw={600}>
                      Version {e.version}
                    </Text>
                    {e.version === current ? (
                      <Badge size="xs" color="blue" variant="light" style={{ textTransform: 'none' }}>
                        current
                      </Badge>
                    ) : null}
                    <Text size="xs" c="dimmed">
                      {formatZoned(e.updatedAt)} · {e.updatedBy || 'Setup'} · {describeSource(e.source)}
                    </Text>
                  </Group>
                </Accordion.Control>
                <Accordion.Panel>
                  <Stack gap="xs">
                    {!older ? (
                      <Text size="sm">The first stored version.</Text>
                    ) : changes.length ? (
                      <List size="sm" spacing={2}>
                        {changes.map((c, j) => (
                          <List.Item key={j}>{c.text}</List.Item>
                        ))}
                      </List>
                    ) : (
                      <Text size="sm">Saved with no changes: the answers were confirmed.</Text>
                    )}
                    {e.profile ? (
                      <Accordion variant="contained" chevronPosition="left">
                        <Accordion.Item value="json">
                          <Accordion.Control aria-label={`The stored profile of version ${e.version}`}>
                            <Text size="xs">The stored profile</Text>
                          </Accordion.Control>
                          <Accordion.Panel>
                            <JsonBlock value={e.profile} label={`site profile version ${e.version}`} />
                          </Accordion.Panel>
                        </Accordion.Item>
                      </Accordion>
                    ) : null}
                  </Stack>
                </Accordion.Panel>
              </Accordion.Item>
            );
          })}
        </Accordion>
      ) : null}
    </Section>
  );
}
