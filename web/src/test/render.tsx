import { MantineProvider } from '@mantine/core';
import { render, type RenderOptions } from '@testing-library/react';
import type { ReactElement, ReactNode } from 'react';
import { MemoryRouter } from 'react-router';
import { useAppearance } from '@/stores/appearance';
import type { DetailLevel } from '@/env/mode';
import { theme } from '@/theme';

/**
 * Renders a piece of the app with its theme and a router, for the components' and the pages' tests; `detail` sets the
 * Detail level first (Plain unless said), so a test reads the page as one audience or the other.
 */
export function renderUi(
  ui: ReactElement,
  { detail = 'plain', path = '/', ...options }: { detail?: DetailLevel; path?: string } & RenderOptions = {},
) {
  useAppearance.setState({ detail });
  const Wrapper = ({ children }: { children: ReactNode }) => (
    <MantineProvider theme={theme}>
      <MemoryRouter initialEntries={[path]}>{children}</MemoryRouter>
    </MantineProvider>
  );
  return render(ui, { wrapper: Wrapper, ...options });
}
