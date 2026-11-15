import { Button, Container, Group, Stack, Text, Title } from '@mantine/core';
import { isRouteErrorResponse, Link, useRouteError } from 'react-router';

/** The browser's words when a page's code is no longer on the server: a release replaced it after this tab loaded. */
const STALE_CHUNK = /dynamically imported module|Importing a module script failed/;

/**
 * What a page shows when it fails: the error in a line, and two ways on. Inside the shell (the pages' boundary in
 * src/routes.tsx) the scenarios link is a plain navigation; on the sign-in page it goes through the sign-in first. A
 * page whose code a new release replaced says so, and Reload opens the new release.
 */
export function RouteError() {
  const error = useRouteError();
  const text = isRouteErrorResponse(error)
    ? `${error.status} ${error.statusText}`
    : error instanceof Error
      ? error.message
      : 'Something went wrong while showing this page.';
  const updated = STALE_CHUNK.test(text);
  return (
    <Container size="sm" py={80}>
      <Stack gap="sm">
        <Title order={2}>{updated ? 'Shutter was just updated' : 'This page failed'}</Title>
        <Text c="dimmed">{updated ? 'Reload to open the new release.' : text}</Text>
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
