import { screen } from '@testing-library/react';
import { IconStack2 } from '@tabler/icons-react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { EmptyState } from './EmptyState';
import { Meta } from './Meta';
import { PageSkeleton } from './PageSkeleton';
import { NotYet, Section } from './Section';

describe('the empty, loading and section states', () => {
  it('says nothing is here yet in one sentence, with one action', () => {
    renderUi(
      <EmptyState icon={IconStack2} hue="pink" action={<a href="#/site-profile">Site profile</a>}>
        No incidents yet. One opens when 5 deliveries to one receiver fail within 10 minutes.
      </EmptyState>,
    );
    expect(screen.getByText(/^No incidents yet\./)).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Site profile' })).toBeInTheDocument();
  });

  it("sketches the page's layout while it loads, as its one status region, or the spinner without a shape", () => {
    const { unmount } = renderUi(<PageSkeleton shape="header-tiles-table" label="Loading the cases…" />);
    expect(screen.getByRole('status')).toHaveTextContent('Loading the cases…');
    expect(screen.getByRole('status')).toHaveAttribute('data-shape', 'header-tiles-table');
    unmount();
    renderUi(<PageSkeleton label="Checking…" />);
    expect(screen.getByRole('status')).toHaveTextContent('Checking…');
  });

  it('frames a section with its h2 and intro, and a labelled fact', () => {
    renderUi(
      <Section id="plan" title="The plan" note="One plan, approved once, covers the ordered chain.">
        <Meta label="Receiver">Downstream Out</Meta>
        <NotYet>No plan yet.</NotYet>
      </Section>,
    );
    const section = screen.getByRole('region', { name: 'The plan' });
    expect(screen.getByRole('heading', { level: 2, name: 'The plan' })).toBeInTheDocument();
    expect(section).toHaveTextContent('ReceiverDownstream Out');
  });
});
