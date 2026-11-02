import { Anchor, MantineProvider, Paper, Stack, Text, Title } from '@mantine/core';
import { ENV, liveHref } from '@/env/mode';
import { theme } from '@/theme';

/**
 * The page a trial shows when its recorded mock could not load. It never falls back to the live system: nothing was
 * sent anywhere, and the way back to the live app is a link the person chooses.
 */
export function TrialFailed() {
  return (
    <MantineProvider theme={theme} defaultColorScheme="auto">
      <main style={{ minHeight: '100vh', display: 'grid', placeItems: 'center', padding: 16 }}>
        <Paper p="xl" maw={480} withBorder>
          <Stack gap="sm">
            <Title order={1} fz={22}>
              The trial could not be opened
            </Title>
            <Text>Nothing was sent anywhere. Reload the page to try again.</Text>
            {ENV.canLeave ? (
              <Text>
                Or <Anchor href={liveHref()}>go to the live system</Anchor>.
              </Text>
            ) : null}
          </Stack>
        </Paper>
      </main>
    </MantineProvider>
  );
}
