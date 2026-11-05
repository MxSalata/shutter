import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { useAppearance, useDetail } from '@/stores/appearance';
import { renderUi } from '@/test/render';
import { DetailSwitch } from './DetailSwitch';

function Shown() {
  return <output>{useDetail()}</output>;
}

describe('DetailSwitch', () => {
  it('switches the whole page between Plain and Technical, and says so politely', async () => {
    const { container } = renderUi(
      <>
        <DetailSwitch />
        <Shown />
      </>,
    );
    const group = screen.getByRole('radiogroup', { name: 'Detail' });
    expect(group).toBeInTheDocument();
    expect(screen.getByRole('radio', { name: 'Plain' })).toBeChecked();
    await userEvent.click(screen.getByText('Technical'));
    expect(useAppearance.getState().detail).toBe('technical');
    expect(screen.getByRole('status')).toHaveTextContent('technical');
    expect(container.querySelector('[aria-live="polite"]')).toHaveTextContent('Technical detail on');
    // The phone's button names the current level
    // and shows it: filled in Technical, plain in Plain
    expect(screen.getByRole('button', { name: 'Detail: Technical' })).toHaveAttribute(
      'data-variant',
      'light',
    );
    useAppearance.setState({ detail: 'plain' });
    expect(await screen.findByRole('button', { name: 'Detail: Plain' })).toHaveAttribute(
      'data-variant',
      'subtle',
    );
  });
});
