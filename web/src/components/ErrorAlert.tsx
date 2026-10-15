import { Alert, Button, Group, Text } from '@mantine/core';
import { IconAlertTriangle } from '@tabler/icons-react';
import { describeError, isApiError } from '@/lib/errors';

export function ErrorAlert({
  error,
  title,
  onRetry,
}: {
  error: unknown;
  title?: string;
  onRetry?: () => void;
}) {
  const status = isApiError(error) && error.status ? `HTTP ${error.status}` : '';
  return (
    <Alert
      color="red"
      variant="light"
      icon={<IconAlertTriangle size={18} />}
      title={title ?? 'Something went wrong'}
      role="alert"
    >
      <Text size="sm">{describeError(error)}</Text>
      {status || onRetry ? (
        <Group gap="sm" mt="xs">
          {status ? (
            <Text size="xs" c="dimmed">
              {status}
            </Text>
          ) : null}
          {onRetry ? (
            <Button size="xs" variant="light" color="red" onClick={onRetry}>
              Try again
            </Button>
          ) : null}
        </Group>
      ) : null}
    </Alert>
  );
}
