import { MantineProvider } from '@mantine/core';
import { ModalsProvider } from '@mantine/modals';
import { Notifications } from '@mantine/notifications';
import { QueryClientProvider } from '@tanstack/react-query';
import { useMemo } from 'react';
import { RouterProvider } from 'react-router';
import { router } from './routes';
import { queryClient } from './query';
import { themeFor } from './theme';
import { useApplyAppearance } from './features/shell/useApplyAppearance';

export default function App() {
  const contrast = useApplyAppearance();
  const theme = useMemo(() => themeFor(contrast), [contrast]);
  return (
    <MantineProvider theme={theme} defaultColorScheme="auto">
      <Notifications position="top-right" limit={5} />
      <ModalsProvider>
        <QueryClientProvider client={queryClient}>
          <RouterProvider router={router} />
        </QueryClientProvider>
      </ModalsProvider>
    </MantineProvider>
  );
}
