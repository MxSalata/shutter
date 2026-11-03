import { screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { INSTALL_URL, type LiveUnavailable } from '@/lib/liveAgents';
import { axeViolations } from '@/test/axe';
import { renderUi } from '@/test/render';
import { layer1Words } from '@/test/words';
import { LiveUnavailableNotice } from './LiveUnavailableNotice';

/** The notice's words as they read: its lines are paragraphs of their own. */
const said = (el: HTMLElement) => layer1Words(el).join(' ');

const provider: LiveUnavailable = {
  reason: 'service',
  timing: 'until',
  until: null,
  hourly: true,
  demo: true,
  code: 'live.agents.reason provider_auth',
  detail: "The model provider refused Shutter's key at 2026-11-02T19:00:00Z (provider_auth)",
};
const budget: LiveUnavailable = {
  reason: 'budget',
  timing: 'reset',
  until: null,
  hourly: false,
  demo: true,
  code: 'budget.exhausted',
};

describe('the notice that the live agents cannot run', () => {
  it('says why, what still works and where to install Shutter, as a calm note with the link', async () => {
    const { container } = renderUi(<LiveUnavailableNotice state={budget} />);
    const note = screen.getByRole('note');
    expect(note).toHaveAttribute('data-tone', 'neutral');
    expect(said(note)).toBe(
      'The live AI budget for this demo is used up until 00:00 UTC. Open cases, recorded runs and the trial still work. To run the live agents yourself, install Shutter with your own API key: how to install',
    );
    const link = within(note).getByRole('link', { name: 'how to install' });
    expect(link).toHaveAttribute('href', INSTALL_URL);
    expect(link).toHaveAttribute('href', 'https://github.com/MxSalata/shutter#try-it');
    expect(link).toHaveAttribute('target', '_blank');
    expect(link).toHaveAttribute('rel', 'noreferrer');
    // Not an alert: nothing went wrong, and it is not announced over what the reader is doing
    expect(screen.queryByRole('alert')).not.toBeInTheDocument();
    expect(await axeViolations(container)).toEqual([]);
  });

  it('keeps the code and the server sentence for Technical', () => {
    const plain = renderUi(<LiveUnavailableNotice state={provider} />);
    expect(screen.getByRole('note')).toHaveTextContent(
      'The live AI service for this demo is unavailable for now.',
    );
    expect(screen.queryByText(/provider_auth/)).not.toBeInTheDocument();
    expect(screen.queryByTestId('live-unavailable-code')).not.toBeInTheDocument();
    plain.unmount();
    renderUi(<LiveUnavailableNotice state={provider} />, { detail: 'technical' });
    const code = screen.getByTestId('live-unavailable-code');
    expect(within(code).getByText('live.agents.reason provider_auth')).toBeInTheDocument();
    expect(code).toHaveTextContent("The model provider refused Shutter's key");
  });

  it('is announced once when it answers a press, and has no box inside a card', () => {
    const status = renderUi(<LiveUnavailableNotice state={budget} role="status" />);
    expect(screen.getByRole('status')).toHaveTextContent('The live AI budget for this demo is used up');
    status.unmount();
    renderUi(<LiveUnavailableNotice state={budget} variant="inline" compact />);
    expect(screen.queryByRole('note')).not.toBeInTheDocument();
    expect(said(screen.getByTestId('live-unavailable'))).toBe(
      'The live AI budget for this demo is used up until 00:00 UTC. To run the live agents yourself, install Shutter with your own API key: how to install',
    );
    expect(screen.queryByText(/still work/)).not.toBeInTheDocument();
  });

  it('offers no install link on a site its reader installed', () => {
    renderUi(<LiveUnavailableNotice state={{ ...budget, demo: false }} />);
    expect(said(screen.getByRole('note'))).toBe(
      'The live AI budget for this site is used up until 00:00 UTC. Open cases, recorded runs and the trial still work.',
    );
    expect(screen.queryByRole('link')).not.toBeInTheDocument();
  });
});
