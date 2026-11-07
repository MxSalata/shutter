import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { render, screen, waitFor, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { createMemoryRouter, RouterProvider } from 'react-router';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it, vi } from 'vitest';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { useAppearance } from '@/stores/appearance';
import { layer1Words } from '@/test/words';
import { theme } from '@/theme';
import SiteProfilePage from './SiteProfilePage';

/**
 * The restyle's two layers on the Site profile: the release matrix in plain words, each question's key path, the save
 * bar, the live confirm, "On this page", read-only readers, and the page's word budget in Plain and in Technical.
 */

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
afterEach(() => {
  server.resetHandlers();
  useAppearance.setState({ detail: 'plain' });
});
afterAll(() => server.close());
beforeEach(() => {
  resetMock('approver');
  notifications.clean();
});

function renderPage(detail: 'plain' | 'technical' = 'plain', query = '') {
  useAppearance.setState({ detail });
  const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
  const router = createMemoryRouter([{ path: '/site-profile', element: <SiteProfilePage /> }], {
    initialEntries: [`/site-profile${query}`],
  });
  return render(
    <MantineProvider theme={theme}>
      <Notifications />
      <QueryClientProvider client={client}>
        <RouterProvider router={router} />
      </QueryClientProvider>
    </MantineProvider>,
  );
}

const matrix = async () => within(await screen.findByRole('table', { name: 'Who releases each write' }));

describe('the header', () => {
  it('leads with one plain sentence and names the version and the shipped answers', async () => {
    renderPage();
    // The shipped answers' badge says the page has its data; the heading alone is there while it loads
    expect(await screen.findByText('Shipped answers')).toBeInTheDocument();
    expect(screen.getByRole('heading', { level: 1, name: 'Site profile' })).toBeInTheDocument();
    expect(
      screen.getByText(/This hospital's answers: they decide what Shutter may do at each/),
    ).toBeInTheDocument();
    // The version badge (the list of versions below says "Version 7" too, once it has loaded)
    expect(screen.getAllByText('Version 7').some((e) => e.closest('[data-tone="neutral"]'))).toBe(true);
    expect(screen.getByText('Shipped answers')).toBeInTheDocument();
    // The long paragraph is a list in the header's second layer, closed
    const detail = screen.getByRole('button', { name: 'Technical detail' });
    expect(detail).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getByText("each receiver's category and tier")).toBeInTheDocument();
  });

  it('moves to the next version once it is saved, and drops the shipped answers', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('button', { name: 'Confirm these answers…' }));
    const dialog = await screen.findByRole('dialog');
    await userEvent.click(within(dialog).getByRole('button', { name: 'Confirm as version 8' }));
    expect(await screen.findByText('Version 8 saved')).toBeInTheDocument();
    await waitFor(() =>
      expect(screen.getAllByText('Version 8').some((e) => e.closest('[data-tone="neutral"]'))).toBe(true),
    );
    expect(screen.queryByText('Shipped answers')).not.toBeInTheDocument();
    expect(screen.queryByText('Shutter is running on the shipped answers')).not.toBeInTheDocument();
  });
});

describe('the release matrix', () => {
  it('heads its columns in plain words, with the code definitions behind them', async () => {
    renderPage();
    const m = await matrix();
    for (const head of ['One failed message', 'Several, in a row', 'Several, with deliveries between'])
      expect(m.getByRole('columnheader', { name: head })).toBeInTheDocument();
    // The definitions are the code's own, in each head's term
    expect(m.getByText('One failure with nothing applied after it.')).toBeInTheDocument();
    expect(m.getByText('Several failures with no successful delivery between them.')).toBeInTheDocument();
    expect(
      m.getByText('Successful deliveries between the failures, or a later event already applied.'),
    ).toBeInTheDocument();
    // None of the old chain names in the matrix's first layer
    expect(m.queryByText('single')).not.toBeInTheDocument();
    expect(m.queryByText(/interleaved chain/)).not.toBeInTheDocument();
  });

  it('names the tiers in full, with their receivers on the second line', async () => {
    renderPage();
    const m = await matrix();
    expect(m.getByRole('rowheader', { name: 'Tier 1: information No receivers' })).toBeInTheDocument();
    expect(
      m.getByRole('rowheader', { name: 'Tier 2: operations Downstream Out, Records Out' }),
    ).toBeInTheDocument();
    expect(m.getByRole('rowheader', { name: 'Tier 3: clinical safety No receivers' })).toBeInTheDocument();
  });

  it('draws each cell from the one map: the written policy, a person, a person per chain, the board', async () => {
    renderPage();
    const m = await matrix();
    const row = (name: RegExp) => within(m.getByRole('rowheader', { name }).closest('tr')!);
    expect(row(/Tier 1/).getAllByText("The site's written policy")).toHaveLength(2);
    expect(row(/Tier 2/).getByText('A person')).toBeInTheDocument();
    expect(row(/Tier 3/).getByText('A person, per chain')).toBeInTheDocument();
    expect(row(/Tier 3/).getByText('The board decides')).toBeInTheDocument();
    // "A person" is one colour everywhere on the page: attention, here and on the receiver cards
    expect(
      row(/Tier 2/)
        .getByText('A person')
        .closest('[data-tone]'),
    ).toHaveAttribute('data-tone', 'attention');
  });

  it('says under the table that the board is a board of agents, and that a person releases its plan', async () => {
    renderPage();
    expect(
      await screen.findByText(
        'When the board decides, a board of agents weighs the case and a person releases its plan.',
      ),
    ).toBeInTheDocument();
  });

  it('puts the code’s own kind names beside the heads in Technical', async () => {
    renderPage('technical');
    const m = await matrix();
    for (const kind of ['single', 'ordered', 'interleaved'])
      expect(m.getByText(kind, { selector: 'code' })).toBeInTheDocument();
  });

  it('keeps the guide’s targets on the receivers, the matrix and the approvals', async () => {
    renderPage();
    await screen.findByRole('table', { name: 'Who releases each write' });
    expect(document.querySelector('[data-tour="site-receivers-cards"]')).not.toBeNull();
    expect(document.querySelector('[data-tour="site-summary"]')).not.toBeNull();
    expect(document.querySelector('[data-tour="site-approvals"]')).not.toBeNull();
  });
});

describe('the questions', () => {
  it('fixes question 7’s text and numbers each question for a screen reader', async () => {
    renderPage();
    expect(await screen.findByText("How each tier's chains are approved")).toBeInTheDocument();
    expect(screen.queryByText(/\\u2019/)).not.toBeInTheDocument();
    expect(screen.getByText('Question 7:')).toBeInTheDocument();
  });

  it('says what an icon means once, at the top of the answers, and in each icon’s name', async () => {
    renderPage();
    const legend = await screen.findByRole('list', { name: 'What the icons mean' });
    expect(within(legend).getByText('Changes what Shutter does')).toBeInTheDocument();
    expect(within(legend).getByText('Kept on record; nothing reads it yet')).toBeInTheDocument();
    expect(screen.getAllByRole('img', { name: 'Changes what Shutter does' }).length).toBeGreaterThan(5);
    expect(
      screen.getAllByRole('img', { name: 'Kept on record; nothing reads it yet' }).length,
    ).toBeGreaterThan(2);
    // The pills of old are gone
    expect(screen.queryByText('On record: nothing reads it yet')).not.toBeInTheDocument();
  });

  it('gives every question its profile key path, open in Technical and closed in Plain', async () => {
    const keys = [
      'receivers[0].category',
      'receivers[0].tier',
      'receivers[0].applies',
      'receivers[0].resend_timestamp',
      'receivers[0].cancels',
      'receivers[0].merges',
      'policy.2',
      'approvers.role',
      'approvers.close_needs_approver',
      'incident.threshold',
      'teams',
      'mail.allowed_domains',
      'feed.time_zone',
      'model_content.free_text',
      'merges',
      'feed.prevent_failures',
      'further_messages.a08_location',
    ];
    const plain = renderPage();
    await screen.findByRole('table', { name: 'Who releases each write' });
    for (const key of keys) {
      const chip = screen.getAllByText(key, { selector: 'code' })[0];
      expect(chip.closest('[data-tech-detail]')).toHaveAttribute('data-tech-detail', 'closed');
    }
    plain.unmount();
    renderPage('technical');
    await screen.findByRole('table', { name: 'Who releases each write' });
    for (const key of keys) {
      const chip = screen.getAllByText(key, { selector: 'code' })[0];
      expect(chip.closest('[data-tech-detail]')).toHaveAttribute('data-tech-detail', 'open');
    }
    // Stored value and what is read when nothing is stored, after the path
    const close = screen.getAllByText('approvers.close_needs_approver', { selector: 'code' })[0];
    expect([...close.parentElement!.children].map((c) => c.textContent)).toEqual([
      'approvers.close_needs_approver',
      'stored as',
      'false',
      'When not set: false.',
    ]);
  });

  it('keeps the prose past 25 words in the question’s own “More about this question”, closed in Technical', async () => {
    renderPage('technical');
    await screen.findByRole('table', { name: 'Who releases each write' });
    const more = screen.getAllByRole('button', { name: 'More about this question' });
    expect(more.length).toBeGreaterThan(8);
    for (const b of more) expect(b).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getByText(/Shutter checks the role of whoever closes the case/)).toBeInTheDocument();
  });

  it('says what Automatic overwrites, beside the choice', async () => {
    renderPage();
    const section = (await screen.findByRole('heading', { name: 'Approvals' })).closest('section')!;
    expect(section).toHaveTextContent(
      "Automatic overwrites the receiver's record, such as a patient's placement, with no person looking. It is still gated, rehearsed and verified.",
    );
  });

  it('keeps the Approvals grid’s names and shortens its choices so a value is never cut', async () => {
    renderPage();
    const select = await screen.findByRole('combobox', { name: 'Tier 3, single failures' });
    expect(select).toHaveValue('approval');
    expect(within(select).getByRole('option', { name: 'Automatic (written policy)' })).toBeInTheDocument();
    expect(within(select).getByRole('option', { name: 'One approval per chain' })).toBeInTheDocument();
    expect(select).toHaveAccessibleDescription('One failed message');
  });
});

describe('the receivers section', () => {
  it('offers to fold the receivers, and keeps every field in the page when they are folded', async () => {
    renderPage();
    const fold = await screen.findByRole('button', { name: 'Collapse the receivers' });
    expect(fold).toHaveAttribute('aria-expanded', 'true');
    await userEvent.click(fold);
    const show = screen.getByRole('button', { name: 'Show the receivers (2)' });
    expect(show).toHaveAttribute('aria-expanded', 'false');
    expect(
      screen.getByRole('combobox', { name: 'Category of Downstream Out', hidden: true }),
    ).toBeInTheDocument();
    await userEvent.click(show);
    expect(screen.getByRole('button', { name: 'Collapse the receivers' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
  });
});

describe('the save bar and the confirm', () => {
  it('shows only while the draft differs from the saved version, with the change count', async () => {
    renderPage();
    const sw = await screen.findByRole('switch', { name: /Downstream Out accepts cancels/ });
    expect(screen.queryByRole('region', { name: 'Unsaved changes' })).not.toBeInTheDocument();
    // The shipped answers' own button lives in the notice until there is something to review
    expect(screen.getByRole('button', { name: 'Confirm these answers…' })).toBeInTheDocument();
    await userEvent.click(sw);
    const bar = await screen.findByRole('region', { name: 'Unsaved changes' });
    expect(within(bar).getByText('1 change')).toBeInTheDocument();
    expect(within(bar).getByRole('button', { name: 'Review and save…' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'Confirm these answers…' })).not.toBeInTheDocument();
    await userEvent.click(within(bar).getByRole('button', { name: 'Discard changes' }));
    await waitFor(() => expect(screen.queryByRole('region', { name: 'Unsaved changes' })).toBeNull());
    expect(sw).not.toBeChecked();
  });

  it('keeps the page clear of the bar while it shows, and lets go when it goes', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('switch', { name: /Downstream Out accepts cancels/ }));
    await screen.findByRole('region', { name: 'Unsaved changes' });
    expect(document.documentElement.style.getPropertyValue('scroll-padding-bottom')).toMatch(/px$/);
    await userEvent.click(screen.getByRole('button', { name: 'Discard changes' }));
    await waitFor(() =>
      expect(document.documentElement.style.getPropertyValue('scroll-padding-bottom')).toBe(''),
    );
  });

  it('opens the live confirm with the consequence in its first sentence and the Live system chip', async () => {
    renderPage();
    await userEvent.click(await screen.findByRole('switch', { name: /Downstream Out accepts cancels/ }));
    await userEvent.click(screen.getByRole('button', { name: 'Review and save…' }));
    const dialog = await screen.findByRole('dialog');
    expect(
      within(dialog).getByText('This changes what Shutter does at this hospital from the next case.'),
    ).toBeInTheDocument();
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
    expect(within(dialog).queryByText('Trial only')).not.toBeInTheDocument();
    // Approvals made under the version in force still come back to a person, as the page has always said
    expect(within(dialog).getByText(/made under version 7 are refused at release/)).toBeInTheDocument();
  });
});

describe('On this page', () => {
  it('links to each section of the answers, and the select jumps to one and moves focus to its heading', async () => {
    const scrollTo = vi.fn();
    window.scrollTo = scrollTo as unknown as typeof window.scrollTo;
    renderPage();
    const nav = await screen.findByRole('navigation', { name: 'On this page' });
    expect(
      within(nav)
        .getAllByRole('button')
        .map((b) => b.textContent),
    ).toEqual([
      'Receivers, 1 to 6',
      'Approvals, 7',
      'Incidents, 8',
      'Escalation, 9',
      'Feed, model, merges, 10 to 13',
      'Recovery, 14',
      'Reminders, 15',
      'An A08 location, 16',
      'Versions',
    ]);
    await userEvent.selectOptions(screen.getByRole('combobox', { name: 'On this page' }), 'site-approvals');
    expect(scrollTo).toHaveBeenCalledTimes(1);
    expect(screen.getByRole('heading', { level: 2, name: 'Approvals' })).toHaveFocus();
    await userEvent.click(within(nav).getByRole('button', { name: 'Versions' }));
    expect(scrollTo).toHaveBeenCalledTimes(2);
    expect(screen.getByRole('heading', { name: 'Versions' })).toHaveFocus();
  });
});

describe('a reader who cannot save', () => {
  it('can still open the second layer of every question, while the answers stay disabled', async () => {
    resetMock('operator');
    renderPage();
    const switchEl = await screen.findByRole('switch', { name: /Downstream Out accepts cancels/ });
    expect(switchEl).toBeDisabled();
    const keys = screen.getAllByRole('button', { name: 'Keys and values' });
    expect(keys.length).toBeGreaterThan(10);
    for (const b of keys) expect(b).toBeEnabled();
    // Nor does the page offer the buttons that add or remove answers
    expect(screen.getByRole('button', { name: 'Add a receiver' })).toBeDisabled();
    await userEvent.click(keys[0]);
    expect(keys[0]).toHaveAttribute('aria-expanded', 'true');
  });

  it('gives the public role the review of a draft and the read-only note in the bar', async () => {
    resetMock('demo');
    renderPage('plain', '?suggest=C-000008&fact=W1');
    const bar = await screen.findByRole('region', { name: 'Unsaved changes' });
    expect(within(bar).getByRole('button', { name: 'Review the changes…' })).toBeInTheDocument();
    expect(within(bar).getByTestId('demo-read-only')).toBeInTheDocument();
    expect(within(bar).queryByRole('button', { name: 'Discard changes' })).not.toBeInTheDocument();
    // One note, not two
    expect(screen.getAllByTestId('demo-read-only')).toHaveLength(1);
  });
});

describe('the second layer at the foot', () => {
  it('names the endpoint and copies the profile as the API sends it', async () => {
    renderPage('technical');
    const source = await screen.findByRole('button', { name: 'As the API sends it' });
    expect(source).toHaveAttribute('aria-expanded', 'true');
    expect(screen.getByText('GET /api/shutter/site-profile')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Copy as JSON' })).toBeInTheDocument();
  });

  it('keeps the version, the source and the other stored settings in one data disclosure', async () => {
    renderPage();
    const toggle = await screen.findByRole('button', { name: 'Version, source and other settings' });
    expect(toggle).toHaveAttribute('aria-expanded', 'false');
    expect(screen.getByText('Seeded from knowledge/site/profile.json')).toBeInTheDocument();
    expect(screen.getByText('Unconditional resends')).toBeInTheDocument();
  });
});

/** The words of the first layer: `layer1Words` leaves out the API's JSON and what a closed disclosure holds. */
function words(container: HTMLElement): number {
  return layer1Words(container).length;
}

describe('the word budget', () => {
  // The top half (what the policy does) is at most 220 words; each description at most 25; the page in Technical, with
  // every data detail open, at most 1.5 times its Plain words (DESIGN.md 1.2 and 1.4, specs/site-profile.md 3)
  const POLICY_HALF = 220;
  const DESCRIPTION = 25;

  it('keeps the policy half to 220 words in Plain', async () => {
    renderPage();
    const half = await screen.findByRole('region', { name: "What this site's policy does" });
    expect(words(half)).toBeLessThanOrEqual(POLICY_HALF);
  });

  it('keeps every question’s description and every section’s intro to 25 words', async () => {
    renderPage();
    await screen.findByRole('table', { name: 'Who releases each write' });
    const descriptions = [
      ...document.querySelectorAll<HTMLElement>('[class*="-description"]'),
      ...[...document.querySelectorAll('section[id^="site-"] h2')]
        .map((h) => h.nextElementSibling as HTMLElement | null)
        .filter((n): n is HTMLElement => n?.tagName === 'P'),
    ];
    expect(descriptions.length).toBeGreaterThan(20);
    const long = descriptions
      .map((d) => ({ text: d.textContent ?? '', n: layer1Words(d).length }))
      .filter((d) => d.n > DESCRIPTION);
    expect(long).toEqual([]);
  });

  it('keeps Technical within 1.5 times Plain', async () => {
    const plain = renderPage();
    await screen.findByRole('table', { name: 'Who releases each write' });
    const inPlain = words(plain.container);
    plain.unmount();
    const technical = renderPage('technical');
    await screen.findByRole('table', { name: 'Who releases each write' });
    const inTechnical = words(technical.container);
    // The page held 2,776 words before the restyle; it is a questionnaire, so it stays long (1,775 when measured)
    expect(inPlain).toBeLessThanOrEqual(2000);
    expect(inTechnical).toBeGreaterThan(inPlain);
    expect(inTechnical).toBeLessThanOrEqual(Math.round(inPlain * 1.5));
  });
});
