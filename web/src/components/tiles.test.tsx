import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { IconFlask2 } from '@tabler/icons-react';
import { createRef } from 'react';
import { describe, expect, it, vi } from 'vitest';
import { renderUi } from '@/test/render';
import { HeroBand } from './HeroBand';
import { StatTile } from './StatTile';
import { StatusBadge } from './StatusBadge';
import { SummaryBand } from './SummaryBand';

describe('StatTile and SummaryBand', () => {
  it('shows a figure with its label, caption and status, its tone in an edge and words', () => {
    renderUi(
      <SummaryBand title="Closed cases">
        <StatTile
          label="Delivered"
          figure="26"
          caption="verified at the receiver"
          tone="positive"
          status={<StatusBadge tone="positive" label="Delivered, verified" />}
        />
        <StatTile label="Scenarios" figure="25" hue="cyan" icon={IconFlask2} />
      </SummaryBand>,
    );
    const band = screen.getByRole('region', { name: 'Closed cases' });
    expect(band).toHaveTextContent('Delivered26verified at the receiverDelivered, verified');
    expect(band.querySelector('.stat-tile[data-tone="positive"]')).not.toBeNull();
    expect(band.querySelectorAll('.stat-tile')).toHaveLength(2);
  });

  it('is a toggle that filters, pressed or not, or a link', async () => {
    const choose = vi.fn();
    renderUi(
      <>
        <StatTile
          label="Escalated"
          figure="15"
          tone="attention"
          onClick={choose}
          pressed={false}
          aria-label="15 Escalated Show these"
        />
        <StatTile label="Evaluation" figure="24 of 24" to="/evaluation" />
      </>,
    );
    const toggle = screen.getByRole('button', { name: '15 Escalated Show these' });
    expect(toggle).toHaveAttribute('aria-pressed', 'false');
    await userEvent.click(toggle);
    expect(choose).toHaveBeenCalledOnce();
    expect(screen.getByRole('link', { name: /24 of 24/ })).toHaveAttribute('href', '/evaluation');
  });

  it('leaves the figure out for a graphic, and makes its label a heading, except on a button', () => {
    renderUi(
      <>
        <StatTile label="Head to head" labelOrder={3}>
          <span>the bars</span>
        </StatTile>
        <StatTile label="Escalated" figure="15" labelOrder={3} onClick={() => {}} aria-label="15 Escalated" />
      </>,
    );
    const heading = screen.getByRole('heading', { name: 'Head to head', level: 3 });
    const tile = heading.closest('.stat-tile')!;
    expect(tile.querySelector('.stat-figure')).toBeNull();
    expect(tile).toHaveTextContent('Head to headthe bars');
    expect(screen.queryByRole('heading', { name: 'Escalated' })).not.toBeInTheDocument();
  });
});

describe('HeroBand', () => {
  it('leads with the outcome in a region, its tone in the edge, with a status and facts', () => {
    renderUi(
      <HeroBand
        tone="positive"
        label="Outcome"
        statement="Delivered: verified at the receiver"
        status={<StatusBadge tone="positive" label="Delivered, verified" />}
        className="outcome-band"
      >
        <span>1 write to Downstream Out</span>
      </HeroBand>,
    );
    const band = screen.getByRole('region', { name: 'Outcome' });
    expect(band).toHaveAttribute('data-tone', 'positive');
    expect(band).toHaveClass('hero-band', 'outcome-band');
    expect(band).toHaveTextContent('Delivered: verified at the receiver');
    expect(band).toHaveTextContent('1 write to Downstream Out');
  });

  it('takes an overline heading, and an id, a tab index and a ref on its statement, which then names it', () => {
    const ref = createRef<HTMLElement>();
    renderUi(
      <HeroBand
        tone="attention"
        id="site-suggestion"
        overline="The board against the expected outcome"
        overlineOrder={2}
        statement="A suggested change from case C-000008"
        statementAs="h2"
        statementProps={{ id: 'site-suggestion-title', tabIndex: -1, ref }}
      />,
    );
    const band = screen.getByRole('region', { name: 'A suggested change from case C-000008' });
    expect(band).toHaveAttribute('id', 'site-suggestion');
    expect(
      screen.getByRole('heading', { name: 'The board against the expected outcome', level: 2 }),
    ).toBeInTheDocument();
    expect(ref.current).toHaveAttribute('id', 'site-suggestion-title');
    ref.current!.focus();
    expect(screen.getByRole('heading', { name: 'A suggested change from case C-000008' })).toHaveFocus();
  });
});
