import { Button, Container, Group, Stack, Text, Title } from '@mantine/core';
import { isRouteErrorResponse, Link, useRouteError } from 'react-router';

/**
 * What a page shows when it fails: the error in a line, and two ways on. Inside the shell (the pages' boundary in
 * src/routes.tsx) the scenarios link is a plain navigation; on the sign-in page it goes through the sign-in first.
 */
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
        <Group gap="sm">
          <Button variant="light" onClick={() => window.location.reload()}>
            Reload
          </Button>
          <Button component={Link} to="/home" variant="subtle">
            Go to Home
          </Button>
        </Group>
      </Stack>
    </Container>
  );
}
