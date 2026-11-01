import { Button, CopyButton, Group, Stack, Text } from '@mantine/core';
import { IconCheck, IconCopy } from '@tabler/icons-react';
import { pretty } from '@/lib/json';
import { CodeChip } from './CodeChip';
import { JsonBlock } from './JsonBlock';
import { TechDetail } from './TechDetail';

/**
 * The machine's view of a page, for the engineer: "As the API sends it", a data disclosure (open in Technical) naming
 * the endpoint (`GET /api/shutter/cases?limit=100`, or the file the page reads), with "Copy as JSON" and the JSON.
 */
export function ApiSource({
  endpoint,
  data,
  label = 'As the API sends it',
}: {
  /** The request or the file, as an engineer would type it. */
  endpoint: string;
  data: unknown;
  label?: string;
}) {
  return (
    <TechDetail label={label} kind="data">
      <Stack gap="xs">
        <Group gap="xs" wrap="wrap" justify="space-between">
          <Text size="sm" span>
            From <CodeChip>{endpoint}</CodeChip>
          </Text>
          <CopyButton value={pretty(data)} timeout={1500}>
            {({ copied, copy }) => (
              <Button
                size="xs"
                variant="default"
                leftSection={
                  copied ? <IconCheck size={14} aria-hidden /> : <IconCopy size={14} aria-hidden />
                }
                onClick={copy}
              >
                {copied ? 'Copied' : 'Copy as JSON'}
              </Button>
            )}
          </CopyButton>
        </Group>
        <JsonBlock value={data} label={`${endpoint}, as JSON`} />
      </Stack>
    </TechDetail>
  );
}
