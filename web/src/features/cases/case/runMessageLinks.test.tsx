import { QueryClient, QueryClientProvider } from '@tanstack/react-query';
import { screen, within } from '@testing-library/react';
import { afterAll, afterEach, beforeAll, beforeEach, describe, expect, it } from 'vitest';
import type { AgentRun, CaseDetail } from '@/api/types';
import { messageContentsLink } from '@/lib/messageLink';
import fixtures from '@/mocks/fixtures.json';
import { resetMock } from '@/mocks/handlers';
import { server } from '@/mocks/node';
import { renderUi } from '@/test/render';
import { BoardPanel } from './BoardPanel';
import { PortalLinks } from './PortalLinks';

beforeAll(() => server.listen({ onUnhandledRequest: 'error' }));
beforeEach(() => resetMock('approver'));
afterEach(() => server.resetHandlers());
afterAll(() => server.close());

const SHUTTER = '/csp/healthshare/shutter/';
const recorded = fixtures.cases['C-000007'];
const detail = recorded.detail as unknown as CaseDetail;
const runs = recorded.runs as unknown as AgentRun[];

/** The header id a link's words name: "message 7936", "Conformance: its message" beside "(message 7936)". */
const idIn = (text: string | null) => /message (\d+)/.exec(text ?? '')?.[1] ?? '';

describe("the links to an agent run's message", () => {
  it("name the header's class on the board's cards, whatever the recorded link says", async () => {
    const client = new QueryClient({ defaultOptions: { queries: { retry: false } } });
    renderUi(
      <QueryClientProvider client={client}>
        <BoardPanel caseId="C-000007" open mode="board" portalBase="/csp/" />
      </QueryClientProvider>,
    );
    const links = await screen.findAllByRole('link', { name: /^message \d+/ });
    expect(links.length).toBeGreaterThan(0);
    const ids = runs.map((r) => r.ensMessageId);
    for (const link of links) {
      const id = idIn(link.textContent);
      expect(ids).toContain(id);
      // The API's own link, under the namespace's portal, not one rebuilt from the base the panel was given
      expect(link).toHaveAttribute('href', messageContentsLink(SHUTTER, id));
    }
  });

  it("name it on the audit trail's list too, one link for each run", () => {
    renderUi(<PortalLinks c={detail} runs={runs} portalBase="/csp/" />);
    const portal = screen.getByRole('region', { name: 'In the Management Portal' });
    const items = within(portal)
      .getAllByRole('listitem')
      .filter((item) => /: its message/.test(item.textContent ?? ''));
    expect(items).toHaveLength(runs.length);
    for (const item of items)
      expect(within(item).getByRole('link', { name: /: its message$/ })).toHaveAttribute(
        'href',
        messageContentsLink(SHUTTER, idIn(item.textContent)),
      );
  });

  it("are built from the portal's base path, with the class, for a run the API sent no link with", () => {
    const bare = runs.map((r) => ({ ...r, messageLink: undefined }));
    renderUi(<PortalLinks c={detail} runs={bare} portalBase="/csp/shutter/" />);
    const first = screen.getAllByRole('link', { name: /: its message$/ })[0];
    expect(first).toHaveAttribute('href', messageContentsLink('/csp/shutter/', runs[0].ensMessageId));
    expect(first.getAttribute('href')).toContain('?HeaderClass=Ens.MessageHeader&HeaderId=');
  });
});
