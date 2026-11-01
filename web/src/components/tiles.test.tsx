import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { IconFlask2 } from '@tabler/icons-react';
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
});
