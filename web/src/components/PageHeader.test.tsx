import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { IconStack2 } from '@tabler/icons-react';
import { describe, expect, it, vi } from 'vitest';
import { renderUi } from '@/test/render';
import { PageHeader } from './PageHeader';
import { StatusBadge } from './StatusBadge';

const mode = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return mode.trial;
  },
}));

describe('PageHeader', () => {
  it("carries the section's icon, the title and its status, the lead, the facts and the technical detail", async () => {
    renderUi(
      <PageHeader
        title="Incidents"
        icon={IconStack2}
        hue="pink"
        status={<StatusBadge tone="info" label="Taking cases" />}
        lead="Many failures to one receiver, handled together and released in order."
        meta={<span>Receiver: Downstream Out</span>}
        details="The long paragraph an expert reads."
        actions={<button type="button">Refresh</button>}
      />,
    );
    expect(screen.getByRole('heading', { level: 1, name: 'Incidents' })).toBeInTheDocument();
    expect(screen.getByText('Taking cases')).toBeInTheDocument();
    expect(screen.getByText(/^Many failures to one receiver/)).toBeInTheDocument();
    expect(screen.getByText('Receiver: Downstream Out')).toBeInTheDocument();
    const detail = screen.getByRole('button', { name: 'Technical detail' });
    expect(detail).toHaveAttribute('aria-expanded', 'false');
    await userEvent.click(detail);
    expect(detail).toHaveAttribute('aria-expanded', 'true');
    expect(document.querySelector('.page-icon')).toHaveAttribute('aria-hidden', 'true');
  });

  it('sets the tab title, with "(trial)" in the trial', () => {
    const { unmount } = renderUi(<PageHeader title="Cases" />);
    expect(document.title).toBe('Cases · Shutter');
    unmount();
    mode.trial = true;
    renderUi(<PageHeader title={<span>Case C-000002</span>} docTitle="Case C-000002" />);
    expect(document.title).toBe('Case C-000002 · Shutter (trial)');
    mode.trial = false;
  });

  it('keeps the deprecated subtitle, so the pages can move to the lead one at a time', () => {
    renderUi(<PageHeader title="Health" subtitle="The installation's own readiness report." />);
    expect(screen.getByText("The installation's own readiness report.")).toBeInTheDocument();
  });
});
