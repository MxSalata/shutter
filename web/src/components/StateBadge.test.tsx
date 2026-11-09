import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { DispositionBadge } from './StateBadge';

describe('DispositionBadge', () => {
  it('shows the word and the icon, and names the disposition for its colour in the palette', () => {
    const { container } = renderUi(<DispositionBadge disposition="resend" />);
    const badge = screen.getByText('Resend').closest('.mantine-Badge-root')!;
    expect(badge).toHaveClass('disposition-badge');
    expect(badge).toHaveAttribute('data-disposition', 'resend');
    expect(badge).toHaveAttribute('data-variant', 'outline');
    expect(badge.getAttribute('style')).toContain('--disposition-fg: var(--shutter-disposition-resend-fg)');
    expect(badge.getAttribute('style')).toContain('--disposition-bg: var(--shutter-disposition-resend-bg)');
    expect(badge.getAttribute('style')).toContain('--disposition-bd: var(--shutter-disposition-resend-bd)');
    expect(container.querySelector('svg')).toHaveAttribute('aria-hidden', 'true');
  });

  it('slugs a two-word disposition, and says when it is a proposal', () => {
    renderUi(<DispositionBadge disposition="more_evidence" proposed />);
    const badge = screen.getByText('Proposed: More evidence').closest('.mantine-Badge-root')!;
    expect(badge).toHaveAttribute('data-disposition', 'more-evidence');
  });

  it('leaves what happened as it is, never a proposal, and a disposition the palette does not know uncoloured', () => {
    renderUi(<DispositionBadge disposition="handled_by_hand" proposed />);
    expect(screen.getByText('Handled by hand')).toBeInTheDocument();
    renderUi(<DispositionBadge disposition="something_else" />);
    const odd = screen.getByText('Something else').closest('.mantine-Badge-root')!;
    expect(odd).not.toHaveClass('disposition-badge');
    expect(odd).not.toHaveAttribute('data-disposition');
    expect(odd).toHaveAttribute('data-tone', 'neutral');
  });

  it('renders nothing for no disposition', () => {
    const { container } = renderUi(<DispositionBadge disposition="" />);
    // The provider's style elements are all the container holds
    expect(container.querySelector('.mantine-Badge-root')).toBeNull();
    expect(container.querySelector(':not(style)')).toBeNull();
  });
});
