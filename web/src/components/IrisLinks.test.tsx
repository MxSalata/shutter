import { screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { ApiSource } from './ApiSource';
import { caseIrisLinks, IrisLinks } from './IrisLinks';

const CASE = {
  ensSessionId: '16603',
  workflowSessionId: '16610',
  sourceMessageId: 'MSG00802',
  sourceHeaderId: '16601',
  links: { visualTrace: '/csp/trace?session=16603', workflowTrace: '/csp/trace?session=16610' },
};

describe('IrisLinks', () => {
  it("gives a case's row in IRIS, its numbers as codes, with the guide's marks", () => {
    const { container } = renderUi(<IrisLinks links={caseIrisLinks(CASE, '/csp/healthshare/shutter/')} />);
    const row = container.querySelector('[data-tour="case-iris"]')!;
    expect(row).toHaveTextContent(
      'In IRIS:Message trace (session 16603)·Workflow trace (session 16610)·Source message (MSG00802)',
    );
    expect(screen.getByRole('link', { name: /Message trace/ })).toHaveAttribute(
      'data-tour-action',
      'open-trace',
    );
    expect(screen.getByRole('link', { name: /Source message/ })).toHaveAttribute(
      'href',
      '/csp/healthshare/shutter/EnsPortal.MessageContents.zen?HeaderId=16601',
    );
  });
});

describe('ApiSource', () => {
  it('names the endpoint and offers the JSON, open in Technical', async () => {
    renderUi(<ApiSource endpoint="GET /api/shutter/cases?limit=100" data={{ items: [], total: 0 }} />, {
      detail: 'technical',
    });
    expect(screen.getByRole('button', { name: 'As the API sends it' })).toHaveAttribute(
      'aria-expanded',
      'true',
    );
    expect(screen.getByText('GET /api/shutter/cases?limit=100')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Copy as JSON' })).toBeInTheDocument();
    await userEvent.click(screen.getByRole('button', { name: 'As the API sends it' }));
    expect(screen.getByRole('button', { name: 'As the API sends it' })).toHaveAttribute(
      'aria-expanded',
      'false',
    );
  });
});
