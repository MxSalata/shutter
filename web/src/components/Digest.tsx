import { ActionIcon, CopyButton, Group, Text, Tooltip } from '@mantine/core';
import { IconCheck, IconCopy } from '@tabler/icons-react';
import { shortDigest } from '@/lib/format';

/** A digest or key, shortened to compare by eye, with the full value in a tooltip and a copy button. */
export function Digest({
  value,
  label,
  length,
}: {
  value: string | undefined | null;
  label?: string;
  length?: number;
}) {
  if (!value)
    return (
      <Text size="sm" c="dimmed">
        none
      </Text>
    );
  return (
    <Group gap={4} wrap="nowrap">
      <Tooltip label={value} multiline maw={460}>
        <Text size="sm" className="mono-wrap" tabIndex={0} aria-label={label ? `${label}: ${value}` : value}>
          {shortDigest(value, length)}
        </Text>
      </Tooltip>
      <CopyButton value={value} timeout={1500}>
        {({ copied, copy }) => (
          <ActionIcon
            size="sm"
            variant="subtle"
            color={copied ? 'teal' : 'gray'}
            onClick={copy}
            aria-label={copied ? 'Copied' : `Copy ${label ?? 'value'}`}
          >
            {copied ? <IconCheck size={14} /> : <IconCopy size={14} />}
          </ActionIcon>
        )}
      </CopyButton>
    </Group>
  );
}
