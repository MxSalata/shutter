import { MantineProvider } from '@mantine/core';
import { Notifications, notifications } from '@mantine/notifications';
import { act, render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import type { ReactNode } from 'react';
import { afterEach, describe, expect, it } from 'vitest';
import { theme } from '@/theme';
import { BACK_IN_LIVE, BackFromTrial } from './BackFromTrial';
import { LIVE_WELCOME_KEY, LiveWelcome } from './LiveWelcome';
import { TRIAL_VISITED_KEY } from './visit';

const ui = (children: ReactNode) =>
  render(
    <MantineProvider theme={theme}>
      <Notifications />
      {children}
    </MantineProvider>,
  );

afterEach(() => {
  act(() => notifications.clean());
  sessionStorage.clear();
  localStorage.clear();
  window.history.replaceState(null, '', '/');
});

describe('a live page after the trial', () => {
  it('says the tab is back in the live system on load, once, when the tab carries the mark', async () => {
    sessionStorage.setItem(TRIAL_VISITED_KEY, '1');
    ui(<BackFromTrial />);
    expect(await screen.findByText(BACK_IN_LIVE)).toBeInTheDocument();
    expect(sessionStorage.getItem(TRIAL_VISITED_KEY)).toBeNull();
  });

  it('says it again on a return from the back-forward cache', async () => {
    ui(<BackFromTrial />);
    expect(screen.queryByText(BACK_IN_LIVE)).not.toBeInTheDocument();
    sessionStorage.setItem(TRIAL_VISITED_KEY, '1');
    act(() => {
      const e = new Event('pageshow') as PageTransitionEvent;
      Object.defineProperty(e, 'persisted', { value: true });
      window.dispatchEvent(e);
    });
    expect(await screen.findByText(BACK_IN_LIVE)).toBeInTheDocument();
  });

  it('says nothing to a tab that never was in the trial', async () => {
    ui(<BackFromTrial />);
    await new Promise((r) => setTimeout(r, 100));
    expect(screen.queryByText(BACK_IN_LIVE)).not.toBeInTheDocument();
  });
});

describe('the live first-run prompt', () => {
  it('points to the trial with real links, once per device', async () => {
    window.history.replaceState(null, '', '/shutter/');
    const { unmount } = ui(<LiveWelcome />);
    const dialog = await screen.findByRole('dialog', { name: 'New here?' });
    expect(dialog).toHaveTextContent('a demo hospital with made-up patients');
    // It sits beside the page, which stays in reach behind it
    expect(dialog).not.toHaveAttribute('aria-modal');
    expect(screen.getByRole('link', { name: 'Take the guided tour' })).toHaveAttribute(
      'href',
      '/shutter/?trial=tour#/scenarios',
    );
    expect(screen.getByRole('link', { name: 'Open the trial' })).toHaveAttribute(
      'href',
      '/shutter/?trial#/home',
    );
    await userEvent.click(screen.getByRole('button', { name: 'Not now' }));
    expect(localStorage.getItem(LIVE_WELCOME_KEY)).not.toBeNull();
    unmount();
    ui(<LiveWelcome />);
    await new Promise((r) => setTimeout(r, 100));
    expect(screen.queryByRole('dialog', { name: 'New here?' })).not.toBeInTheDocument();
  });
});
