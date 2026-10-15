import { Button, Container, Stack, Text, Title } from '@mantine/core';
import { isRouteErrorResponse, useRouteError } from 'react-router';

export function RouteError() {
  const error = useRouteError();
  const text = isRouteErrorResponse(error)
    ? `${error.status} ${error.statusText}`
    : error instanceof Error
      ? error.message
      : 'Something went wrong while showing this page.';
  return (
    <Container size="sm" py={80}>
      <Stack gap="sm">
        <Title order={2}>This page failed</Title>
        <Text c="dimmed">{text}</Text>
        <Button variant="light" w="fit-content" onClick={() => window.location.reload()}>
          Reload
        </Button>
      </Stack>
    </Container>
  );
}
