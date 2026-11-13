import { screen, within } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import type { CaseDetail, PlanView, Snapshot } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { renderUi } from '@/test/render';
import { PlanPanel, RehearsalPanel } from './PlanPanel';

const viewWith = (rehearsal: Record<string, unknown>) => ({ rehearsal }) as unknown as PlanView;

/** A recorded case's plan section, as the case page draws it. */
function renderPlan(caseId: keyof typeof fixtures.cases, detail: 'plain' | 'technical' = 'plain') {
  const recorded = fixtures.cases[caseId];
  renderUi(
    <PlanPanel
      view={recorded.plan as unknown as PlanView}
      loading={false}
      c={recorded.detail as unknown as CaseDetail}
      snapshot={recorded.snapshot as unknown as Snapshot}
    />,
    { detail },
  );
  return screen.getByRole('region', { name: 'The plan' });
}

describe('the plan', () => {
  it('leads with its action in plain words, the conditions beside it, and why', () => {
    const plan = renderPlan('C-000002');
    expect(within(plan).getByTestId('plan-action')).toHaveTextContent(
      /^Resend the PAS transfer to WARD-B, once, only if the bed-management system is still at version 1\.$/,
    );
    const conditions = within(within(plan).getByTestId('plan-only-if'))
      .getAllByRole('listitem')
      .map((li) => li.textContent);
    expect(conditions).toEqual([
      'The bed-management system still holds the encounter at version 1',
      'No later event has moved the encounter on',
    ]);
    expect(within(plan).getByTestId('plan-why')).toHaveTextContent(
      /^Why: E2 preferred \(RP-2\.1\): the transfer was not committed/,
    );
    // The headline comes before everything else the section says of the plan
    const headline = within(plan).getByTestId('plan-headline');
    const why = within(plan).getByTestId('plan-why');
    expect(headline.compareDocumentPosition(why) & Node.DOCUMENT_POSITION_FOLLOWING).toBeTruthy();
  });

  it('keeps the keys, digests, catalogue entry and version one click away in Plain', () => {
    const plan = renderPlan('C-000002');
    const details = within(plan).getByRole('button', { name: 'Plan details' });
    expect(details).toHaveAttribute('aria-expanded', 'false');
    const folded = document.getElementById(details.getAttribute('aria-controls')!)!;
    expect(folded).toHaveAttribute('data-tech-detail', 'closed');
    for (const label of ['Operation key', 'Plan digest', 'Catalogue entry', 'Plan version'])
      expect(within(folded).getByRole('rowheader', { name: label, hidden: true })).toBeInTheDocument();
    expect(within(folded).getByText(/^Preconditions as the plan's author wrote them/)).toBeInTheDocument();
  });

  it('opens them in Technical', () => {
    const plan = renderPlan('C-000002', 'technical');
    expect(within(plan).getByRole('button', { name: 'Plan details' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
  });

  it('says first that a plan which is no resend sends nothing, with no conditions of a write', () => {
    const plan = renderPlan('C-000003');
    expect(within(plan).getByTestId('plan-action')).toHaveTextContent(
      /^Send nothing: record the PAS transfer to WARD-B as already delivered\.$/,
    );
    expect(within(plan).queryByTestId('plan-only-if')).not.toBeInTheDocument();
    expect(within(plan).getByText('1 disagreement(s) kept in the plan.')).toBeInTheDocument();
  });

  it("speaks of the case's own operation on a plan that only hands the case on", () => {
    const plan = renderPlan('C-000008');
    expect(within(plan).getByTestId('plan-action')).toHaveTextContent(
      /^Send nothing: hand the PAS transfer to WARD-B to a person\.$/,
    );
  });
});

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
