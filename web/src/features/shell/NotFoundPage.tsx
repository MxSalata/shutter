import { Button, Stack, Text, Title } from '@mantine/core';
import { Link } from 'react-router';

export default function NotFoundPage() {
  return (
    <Stack gap="sm" py="xl">
      <Title order={2}>Not found</Title>
      <Text c="dimmed">There is no page at this address.</Text>
      <Button component={Link} to="/home" variant="light" w="fit-content">
        Go to Home
      </Button>
    </Stack>
  );
}
