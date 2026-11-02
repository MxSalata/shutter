import { act, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { useAppearance } from '@/stores/appearance';
import { renderUi } from '@/test/render';
import { TechDetail } from './TechDetail';
import { Term } from './Term';

describe('TechDetail', () => {
  it('opens a data detail in Technical and keeps an explanation closed in both modes', () => {
    renderUi(
      <>
        <TechDetail label="Reason codes and keys" kind="data">
          NOT_CONFIGURED
        </TechDetail>
        <TechDetail label="How to read this table" kind="explain">
          Each row is a pass.
        </TechDetail>
      </>,
      { detail: 'technical' },
    );
    expect(screen.getByRole('button', { name: 'Reason codes and keys' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(screen.getByRole('button', { name: 'How to read this table' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
    // The content stays in the page, so a search still finds it
    expect(screen.getByText('Each row is a pass.')).toBeInTheDocument();
  });

  it("keeps the reader's own toggle until the Detail switch changes", async () => {
    renderUi(
      <TechDetail label="Reason codes and keys" kind="data">
        NOT_CONFIGURED
      </TechDetail>,
    );
    const button = screen.getByRole('button', { name: 'Reason codes and keys' });
    expect(button).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(button);
    expect(button).toHaveAttribute('aria-expanded', 'true');
    act(() => useAppearance.setState({ detail: 'technical' }));
    expect(button).toHaveAttribute('aria-expanded', 'true');
    await userEvent.click(button);
    expect(button).toHaveAttribute('aria-expanded', 'false');
    act(() => useAppearance.setState({ detail: 'plain' }));
    expect(button).toHaveAttribute('aria-expanded', 'false');
    expect(button).toHaveAttribute('aria-controls');
  });
});

describe('Term', () => {
  it('describes its word, and opens on focus, on a hover and on a tap, and closes on a second tap', async () => {
    renderUi(
      <p>
        The <Term term="gate">gate</Term> checks it.
      </p>,
    );
    const word = screen.getByText('gate');
    expect(word).toHaveAccessibleDescription(/Mechanical checks of the plan/);
    await userEvent.tab();
    expect(word).toHaveFocus();
    expect(await screen.findByRole('tooltip')).toHaveTextContent(/Mechanical checks/);
    await userEvent.tab();
    await waitFor(() => expect(screen.queryByRole('tooltip')).not.toBeInTheDocument());
    await userEvent.pointer({ keys: '[TouchA]', target: word });
    expect(await screen.findByRole('tooltip')).toBeInTheDocument();
    await userEvent.pointer({ keys: '[TouchA]', target: word });
    await waitFor(() => expect(screen.queryByRole('tooltip')).not.toBeInTheDocument());
  });

  it("reads HL7's own terms plainly in Technical, and keeps Shutter's definitions without the underline", () => {
    const { container } = renderUi(
      <p>
        <Term term="msh-7">MSH-7</Term> and <Term term="rehearsal">rehearsal</Term>
      </p>,
      { detail: 'technical' },
    );
    expect(container.querySelector('p')).toHaveTextContent('MSH-7 and rehearsal');
    expect([...container.querySelectorAll('.term')].map((t) => t.textContent)).toEqual(['rehearsal']);
    expect(screen.getByText('rehearsal')).toHaveAttribute('data-plain', 'true');
  });
});
