import { MantineProvider } from '@mantine/core';
import { ModalsProvider } from '@mantine/modals';
import { Notifications } from '@mantine/notifications';
import { QueryClientProvider } from '@tanstack/react-query';
import { useMemo } from 'react';
import { RouterProvider } from 'react-router';
import { router } from './routes';
import { queryClient } from './query';
import { dispositionVariables, themeFor } from './theme';
import { useApplyAppearance } from './features/shell/useApplyAppearance';
import { TRIAL } from './env/mode';
import { BackFromTrial } from './trial/BackFromTrial';

export default function App() {
  const contrast = useApplyAppearance();
  const theme = useMemo(() => themeFor(contrast), [contrast]);
  // The disposition palette as CSS variables per colour scheme (theme.ts), solid under high contrast
  const variables = useMemo(() => dispositionVariables(contrast), [contrast]);
  return (
    <MantineProvider theme={theme} cssVariablesResolver={variables} defaultColorScheme="auto">
      <Notifications position="top-right" limit={5} />
      {/* A live page tells a tab that has just been in the trial that it is back in the live system */}
      {TRIAL ? null : <BackFromTrial />}
      <ModalsProvider>
        <QueryClientProvider client={queryClient}>
          <RouterProvider router={router} />
        </QueryClientProvider>
      </ModalsProvider>
    </MantineProvider>
  );
}
