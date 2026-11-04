import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { ComparisonBars } from './ComparisonBars';

describe('ComparisonBars', () => {
  it('draws each actor on one base, named in the caption, and shows the same as a table', async () => {
    renderUi(
      <ComparisonBars
        of={11}
        caption="the board against Rules only (no agents), on the same 11 failures"
        bars={[
          { label: 'The board', value: 11, hue: 'violet' },
          { label: 'Rules only', value: 4, hue: 'gray' },
        ]}
      />,
    );
    const figure = screen.getByRole('figure', { name: /on the same 11 failures/ });
    expect(screen.getByRole('img', { name: 'Rules only: 4 of 11' })).toBeInTheDocument();
    expect(figure.querySelectorAll('.comparison-bar')[1]).toHaveStyle({ width: `${(4 / 11) * 100}%` });
    await userEvent.click(screen.getByRole('button', { name: 'Show as a table' }));
    expect(screen.getByRole('table')).toHaveTextContent('Rules only4 of 11');
  });
});
