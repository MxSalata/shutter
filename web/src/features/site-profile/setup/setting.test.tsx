import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { recordedSiteProfile } from '@/mocks/profile';
import { theme } from '@/theme';
import { describePath, diffProfiles, fieldId, validateProfile } from '../profile';
import SiteProfilePage from '../SiteProfilePage';
import { classOf } from './fields';
import { resetSetupForTests } from './setupStore';

/**
 * The site's switch for typed answers in Set up the site (model_content.setup_answers, CONTRACTS 6.4 and 14.7): a key
 * of the profile the validator knows, off by default, set only by a person with the form's control and saved through the
 * review, and never a key a model may draft.
 */

const recorded = recordedSiteProfile()!;
let puts: Record<string, unknown>[] = [];

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  resetSetupForTests();
  notifications.clean();
  puts = [];
  server.events.removeAllListeners();
  server.events.on('request:start', async ({ request }) => {
    if (request.method === 'PUT') puts.push((await request.clone().json()) as Record<string, unknown>);
  });
});

describe('the site switch for typed answers in Set up the site', () => {
  it('is a key the validator knows: true or false, and no misspelling passes as off', () => {
    const p = recorded.profile;
    expect(p.model_content?.setup_answers).toBeUndefined();
    expect(validateProfile({ ...p, model_content: { free_text: false, setup_answers: true } })).toBe('');
    expect(validateProfile({ ...p, model_content: { setup_answers: false } })).toBe('');
    expect(validateProfile({ ...p, model_content: { setup_answers: 'yes' } })).toBe(
      'model_content.setup_answers: must be true or false',
    );
    expect(validateProfile({ ...p, model_content: { setup_answer: true } })).toBe(
      'model_content.setup_answer: unknown setting',
    );
  });

  it("is a person's to set, has its control on the form, and reads plainly in the review", () => {
    expect(classOf('model_content.setup_answers')).toBe('P');
    expect(fieldId('model_content.setup_answers')).toBe('site-model_content-setup_answers');
    expect(describePath('model_content.setup_answers')).toBe('Model, typed answers in Set up the site');
    const on = { ...recorded.profile, model_content: { free_text: false, setup_answers: true } };
    expect(diffProfiles(recorded.profile, on).map((c) => c.text)).toEqual([
      'Set up the site: what a person types there may be read by a model from now on, which drafts answers for review',
    ]);
    expect(diffProfiles(on, recorded.profile).map((c) => c.text)).toEqual([
      'Set up the site: typed answers are no longer read by a model; its controls answer',
    ]);
  });

  it('is off on the form until an approver turns it on and saves it through the review', async () => {
    const user = userEvent.setup();
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    const router = createMemoryRouter([{ path: '/site-profile', element: <SiteProfilePage /> }], {
      initialEntries: ['/site-profile'],
    });
    render(
      <MantineProvider theme={theme}>
        <Notifications />
        <QueryClientProvider client={client}>
          <RouterProvider router={router} />
        </QueryClientProvider>
      </MantineProvider>,
    );
    const control = await screen.findByRole('switch', { name: /^Read typed answers in Set up the site/ });
    expect(control).not.toBeChecked();
    expect(screen.getByText('Off: no typed answer goes to a model.')).toBeInTheDocument();
    await user.click(control);
    await user.click(
      within(screen.getByRole('region', { name: 'Unsaved changes' })).getByRole('button', {
        name: 'Review and save…',
      }),
    );
    const dialog = within(await screen.findByRole('dialog'));
    expect(
      dialog.getByText(/Set up the site: what a person types there may be read by a model from now on/),
    ).toBeInTheDocument();
    await user.click(dialog.getByRole('button', { name: /^Save version/ }));
    expect(await screen.findByText(`Version ${recorded.version + 1} saved`)).toBeInTheDocument();
    expect(puts).toHaveLength(1);
    expect(puts[0].model_content).toMatchObject({ setup_answers: true });
  });
});
