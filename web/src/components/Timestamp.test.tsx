import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { theme } from '@/theme';
import { Timestamp } from './Timestamp';

/** Outside the demo: a time in the feed's zone, or with `age` how long ago it was. */
function renderTimestamp(age: boolean) {
  return render(
    <MantineProvider theme={theme}>
      <Timestamp iso="2026-10-15T08:20:00Z" age={age} />
    </MantineProvider>,
  );
}

describe('Timestamp', () => {
  it('shows the time in the feed zone', () => {
    renderTimestamp(false);
    expect(screen.getByText('15 Oct, 09:20:00 BST')).toHaveAttribute('datetime', '2026-10-15T08:20:00Z');
  });

  it('shows an age when asked, on an instance', () => {
    renderTimestamp(true);
    expect(screen.getByText(/ago$/)).toBeInTheDocument();
    expect(screen.queryByText('15 Oct, 09:20:00 BST')).not.toBeInTheDocument();
  });

  it('shows a time of today without its date in the short form, and any other day with it', () => {
    const now = new Date().toISOString();
    const { unmount } = renderUi(<Timestamp iso={now} short />);
    expect(screen.getByText(/^\d\d:\d\d:\d\d (GMT|BST)$/)).toHaveAttribute('datetime', now);
    unmount();
    renderUi(<Timestamp iso="2026-10-15T08:20:00Z" short />);
    expect(screen.getByText('15 Oct, 09:20:00 BST')).toBeInTheDocument();
  });

  it('puts the UTC time beside the local one in Technical', () => {
    renderUi(<Timestamp iso="2026-10-15T08:20:00Z" />, { detail: 'technical' });
    expect(screen.getByText('15 Oct, 09:20:00 BST, 08:20:00Z')).toBeInTheDocument();
  });
});
