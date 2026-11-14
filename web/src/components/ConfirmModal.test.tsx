import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it, vi } from 'vitest';
import { renderUi } from '@/test/render';
import { ConfirmModal } from './ConfirmModal';

const mode = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return mode.trial;
  },
}));

describe('ConfirmModal', () => {
  it('is named by its title alone, with where the action takes effect beside it', async () => {
    const { unmount } = renderUi(
      <ConfirmModal opened onClose={() => {}} title="Approve the resend: plan v1">
        <p>This sends the fix.</p>
      </ConfirmModal>,
    );
    const dialog = await screen.findByRole('dialog', { name: 'Approve the resend: plan v1' });
    expect(within(dialog).getByText('Live system')).toBeInTheDocument();
    expect(within(dialog).getByRole('button', { name: 'Close' })).toBeInTheDocument();
    expect(dialog).toHaveTextContent('This sends the fix.');
    unmount();
    mode.trial = true;
    renderUi(
      <ConfirmModal opened onClose={() => {}} title="Approve the resend: plan v1">
        <p>Nothing leaves this browser.</p>
      </ConfirmModal>,
    );
    expect(
      within(await screen.findByRole('dialog', { name: 'Approve the resend: plan v1' })).getByText(
        'Trial only',
      ),
    ).toBeInTheDocument();
    mode.trial = false;
  });

  it('leaves the chip out for a dialog that only lets the reader look', async () => {
    renderUi(
      <ConfirmModal opened onClose={() => {}} title="The suggested change" chip={false}>
        <p>Read only.</p>
      </ConfirmModal>,
    );
    const dialog = await screen.findByRole('dialog', { name: 'The suggested change' });
    expect(within(dialog).queryByText('Live system')).not.toBeInTheDocument();
  });

  it('closes on its close button and on Escape, never on a click outside, and on none of them while it is locked', async () => {
    const onClose = vi.fn();
    const { rerender } = renderUi(
      <ConfirmModal opened onClose={onClose} title="Approve the resend: plan v1" locked>
        <p>This sends the fix.</p>
      </ConfirmModal>,
    );
    const dialog = await screen.findByRole('dialog', { name: 'Approve the resend: plan v1' });
    // Locked, while its action is on its way: no way of closing it answers
    expect(within(dialog).getByRole('button', { name: 'Close' })).toBeDisabled();
    await userEvent.keyboard('{Escape}');
    const overlay = document.querySelector('.mantine-Modal-overlay') as HTMLElement;
    await userEvent.click(overlay);
    expect(onClose).not.toHaveBeenCalled();
    // The action answered: the dialog closes as any other
    rerender(
      <ConfirmModal opened onClose={onClose} title="Approve the resend: plan v1">
        <p>This sends the fix.</p>
      </ConfirmModal>,
    );
    expect(within(dialog).getByRole('button', { name: 'Close' })).toBeEnabled();
    await userEvent.keyboard('{Escape}');
    expect(onClose).toHaveBeenCalledTimes(1);
    await userEvent.click(within(dialog).getByRole('button', { name: 'Close' }));
    expect(onClose).toHaveBeenCalledTimes(2);
    // A stray click outside never discards a confirm, locked or not
    await userEvent.click(overlay);
    expect(onClose).toHaveBeenCalledTimes(2);
  });
});
