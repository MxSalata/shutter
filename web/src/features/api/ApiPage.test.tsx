import { screen, within } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import ApiPage from './ApiPage';
import { routesOf } from './openapi';

const routes = routesOf();
const ROUTE_LINE = /^(GET|POST|PUT|PATCH|DELETE) \/api\/shutter/;

/** The accordion buttons of the Routes section, one per route shown. */
const routeButtons = () =>
  within(screen.getByRole('region', { name: 'Routes' })).getAllByRole('button', { name: ROUTE_LINE });

describe('ApiPage', () => {
  it('lists every route of the document in its groups, with how to call it first and the shapes last', () => {
    renderUi(<ApiPage />, { detail: 'technical' });
    expect(screen.getByRole('heading', { level: 1, name: 'API reference' })).toBeInTheDocument();
    expect(
      screen.getByText(`${routes.length} routes under /api/shutter`, { exact: false }),
    ).toBeInTheDocument();
    const calling = screen.getByRole('region', { name: 'Calling it' });
    expect(calling).toHaveTextContent('POST /api/shutter/session');
    expect(calling).toHaveTextContent('X-Requested-With: Shutter');
    expect(calling).toHaveTextContent('Idempotency-Key');
    expect(routeButtons()).toHaveLength(routes.length);
    const routesRegion = screen.getByRole('region', { name: 'Routes' });
    expect(
      within(routesRegion)
        .getAllByRole('heading', { level: 3 })
        .map((h) => h.textContent),
    ).toEqual([
      'Session',
      'Health',
      'Scenarios',
      'Cases',
      'Approvals',
      'Precedents',
      'Escalations',
      'Questions',
      'Incidents',
      'Outages',
      'Intake',
      'Site profile',
      'Settings',
      'Index',
      'Costs',
      'Reviews',
    ]);
    const shapes = screen.getByRole('region', { name: 'Shapes' });
    expect(within(shapes).getByRole('button', { name: /^CaseSummary/ })).toBeInTheDocument();
    // Nothing is open until asked: a closed route renders no tables
    expect(screen.queryByRole('table', { name: 'Parameters' })).not.toBeInTheDocument();
  });

  it('narrows the list by words, by reads or changes and by resource', async () => {
    const user = userEvent.setup();
    renderUi(<ApiPage />, { detail: 'technical' });
    await user.type(screen.getByRole('textbox', { name: 'Find' }), 'site-profile');
    const found = routeButtons();
    expect(found).toHaveLength(3);
    expect(found[0]).toHaveAccessibleName(/^GET \/api\/shutter\/site-profile /);
    expect(found[1]).toHaveAccessibleName(/^PUT \/api\/shutter\/site-profile /);
    expect(found[2]).toHaveAccessibleName(/^GET \/api\/shutter\/site-profile\/history /);
    await user.selectOptions(screen.getByRole('combobox', { name: 'Show' }), 'changes');
    expect(routeButtons()).toHaveLength(1);
    expect(routeButtons()[0]).toHaveTextContent('Shutter_Configure');
    await user.clear(screen.getByRole('textbox', { name: 'Find' }));
    await user.selectOptions(screen.getByRole('combobox', { name: 'Needs' }), 'Shutter_Intake');
    expect(routeButtons()).toHaveLength(1);
    expect(routeButtons()[0]).toHaveAccessibleName(/^POST \/api\/shutter\/intake /);
    await user.type(screen.getByRole('textbox', { name: 'Find' }), 'nothing-like-this');
    expect(screen.getByText(/No route matches/)).toBeInTheDocument();
  });

  it('opens a route to what it needs, its parameters, body, replies and a curl line', async () => {
    const user = userEvent.setup();
    renderUi(<ApiPage />, { detail: 'technical' });
    const approve = within(screen.getByRole('region', { name: 'Routes' })).getByRole('button', {
      name: /^POST \/api\/shutter\/cases\/\{caseId\}\/approvals /,
    });
    expect(approve).toHaveTextContent('(a change)');
    await user.click(approve);
    expect(approve).toHaveAttribute('aria-expanded', 'true');
    const panel = document.getElementById(approve.getAttribute('aria-controls')!)!;
    expect(panel).toHaveTextContent('Shutter_Approve');
    expect(panel).toHaveTextContent('Yes: send X-Requested-With: Shutter');
    expect(panel).toHaveTextContent('The same key and body replay the first reply');
    expect(panel).toHaveTextContent('docs/CONTRACTS.md section 5');
    // The panel opens with a transition: wait for it to be shown before reading its tables by role
    const parameters = await within(panel).findByRole('table', { name: 'Parameters' });
    expect(within(parameters).getByRole('rowheader', { name: /caseId/ })).toBeInTheDocument();
    const body = within(panel).getByRole('table', { name: /^Body of POST/ });
    expect(within(body).getByRole('rowheader', { name: /^decision/ })).toHaveTextContent('required');
    expect(within(body).getByRole('row', { name: /^decision/ })).toHaveTextContent('One of approve, reject');
    const replies = within(panel).getByRole('table', { name: 'Replies' });
    expect(within(replies).getByRole('row', { name: /^409/ })).toHaveTextContent('wrong_state');
    expect(within(panel).getByLabelText('Example body')).toHaveTextContent('"decision": "approve"');
    expect(within(panel).getByLabelText(/as curl$/)).toHaveTextContent("-H 'X-Requested-With: Shutter'");
    expect(within(panel).getByRole('button', { name: 'Copy the command' })).toBeInTheDocument();
  });

  it('opens the route the address names, and a type in its tables reaches the shape below', async () => {
    const user = userEvent.setup();
    renderUi(<ApiPage />, { detail: 'technical', path: '/api?op=caseApprove' });
    const approve = within(screen.getByRole('region', { name: 'Routes' })).getByRole('button', {
      name: /^POST \/api\/shutter\/cases\/\{caseId\}\/approvals /,
    });
    expect(approve).toHaveAttribute('aria-expanded', 'true');
    const panel = document.getElementById(approve.getAttribute('aria-controls')!)!;
    await user.click(within(panel).getByRole('button', { name: 'ApprovalDecided' }));
    const shape = within(screen.getByRole('region', { name: 'Shapes' })).getByRole('button', {
      name: /^ApprovalDecided/,
    });
    expect(shape).toHaveAttribute('aria-expanded', 'true');
    const shapePanel = document.getElementById(shape.getAttribute('aria-controls')!)!;
    expect(within(shapePanel).getByRole('table', { name: 'ApprovalDecided' })).toBeInTheDocument();
    expect(within(shapePanel).getByRole('row', { name: /^approver/ })).toHaveTextContent(
      'The signed-in user, never a name from the body.',
    );
  });
});
