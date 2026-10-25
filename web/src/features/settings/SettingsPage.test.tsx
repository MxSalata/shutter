import { MantineProvider } from '@mantine/core';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen } from '@testing-library/react';
import { http, HttpResponse } from 'msw';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { Settings } from '@/api/types';
import { server } from '@/mocks/node';
import { resetMock } from '@/mocks/handlers';
import { theme } from '@/theme';
import SettingsPage from './SettingsPage';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => resetMock('approver'));

const settings = (mock: boolean): Settings => ({
  agentMode: 'auto',
  providerConfigured: true,
  mode: 'board',
  scenario: '',
  resetAt: '',
  demo: true,
  agentItems: [
    {
      name: 'Agent Coordinator',
      enabled: true,
      agentClass: 'Shutter.Agent.Coordinator',
      mode: 'live',
      effectiveMode: 'live',
      providerConfig: 'Shutter',
      answeredBy: mock ? 'the API mimic' : 'AI.LLM.Shutter',
    },
  ],
  prices: [],
  aiHubPresent: true,
  liveRunnerPresent: true,
  mock,
  mockConfig: mock ? 'AI.LLM.ShutterMock' : '',
  mockModel: mock ? 'mock' : '',
});

function renderSettings(s: Settings) {
  server.use(http.get('/api/shutter/settings', () => HttpResponse.json(s)));
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/settings', element: <SettingsPage /> }], {
    initialEntries: ['/settings'],
  });
  return render(
    <MantineProvider theme={theme}>
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

describe('SettingsPage', () => {
  it('says when the API mimic answers the live items, and who answers each', async () => {
    renderSettings(settings(true));
    expect(
      await screen.findByText(
        /1 AI Hub agent, running live against the API mimic \(tests\/mock\): no model is called and the runs cost nothing/,
      ),
    ).toBeInTheDocument();
    expect(screen.getByText('API mimic on (AI.LLM.ShutterMock)')).toBeInTheDocument();
    expect(
      screen.getByText(
        'No model answers while the mimic is on; the runs are labelled mock and cost nothing.',
      ),
    ).toBeInTheDocument();
    expect(screen.getByRole('columnheader', { name: 'Answered by' })).toBeInTheDocument();
    expect(screen.getByText('the API mimic')).toBeInTheDocument();
  });

  it('names the model provider when the mimic is off', async () => {
    renderSettings(settings(false));
    expect(
      await screen.findByText(/1 AI Hub agent, running live on the configured model provider/),
    ).toBeInTheDocument();
    expect(screen.queryByText(/API mimic on/)).not.toBeInTheDocument();
    expect(screen.getByText('AI.LLM.Shutter')).toBeInTheDocument();
  });
});
