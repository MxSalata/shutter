import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { PlanView } from '@/api/types';
import { renderUi } from '@/test/render';
import { RehearsalPanel } from './PlanPanel';

const viewWith = (rehearsal: Record<string, unknown>) => ({ rehearsal }) as unknown as PlanView;

describe('the rehearsal', () => {
  it('says a dry run nobody answered shows nothing, not that the action would fail or was rolled back', () => {
    renderUi(
      <RehearsalPanel
        view={viewWith({ wouldApply: false, httpStatus: 0, at: '2026-11-05T03:00:00Z' })}
        write
        receiver="Downstream Out"
      />,
    );
    expect(screen.getAllByText('No answer').length).toBeGreaterThan(0);
    expect(screen.queryByText(/Would not apply/)).not.toBeInTheDocument();
    expect(screen.queryByText('Rolled back')).not.toBeInTheDocument();
    expect(screen.queryByText(/HTTP 0/)).not.toBeInTheDocument();
  });

  it("keeps the receiver's own answer and the roll back when it refused the dry run", () => {
    renderUi(
      <RehearsalPanel
        view={viewWith({
          wouldApply: false,
          httpStatus: 409,
          reason: 'version_conflict',
          at: '2026-11-05T03:00:00Z',
        })}
        write
        receiver="Downstream Out"
      />,
    );
    expect(screen.getByText(/Would not apply: version_conflict/)).toBeInTheDocument();
    expect(screen.getByText('Rolled back')).toBeInTheDocument();
    expect(screen.getByText(/HTTP 409, version_conflict/)).toBeInTheDocument();
  });
});
