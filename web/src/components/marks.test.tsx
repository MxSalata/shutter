import { screen, within } from '@testing-library/react';
import { describe, expect, it, vi } from 'vitest';
import type { Scenario } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import { renderUi } from '@/test/render';
import { AgreementDots } from './AgreementDots';
import { CheckStrip } from './CheckStrip';
import { CodeChip } from './CodeChip';
import { EnvChip } from './EnvChip';
import { ExpectedMark } from './ExpectedMark';
import { IdentityBadge } from './IdentityBadge';
import { MemberAvatar } from './MemberAvatar';
import { MemberCard } from './MemberCard';
import { OutcomeBadge } from './OutcomeBadge';
import { StatusBadge } from './StatusBadge';
import { ToneLegend } from './ToneLegend';

const mode = vi.hoisted(() => ({ trial: false }));
vi.mock('@/env/mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('@/env/mode')>()),
  get TRIAL() {
    return mode.trial;
  },
}));

const S8 = (fixtures.scenarios as unknown as Scenario[]).find((s) => s.id === 'S8')!;
const C21 = {
  state: 'resolved' as const,
  disposition: 'resend',
  writes: 1,
  verification: 'verified',
  mode: 'rules',
};

describe('the small marks', () => {
  it("names a case's outcome short in a list, long on its page, and how it compares with its scenario", () => {
    renderUi(
      <>
        <OutcomeBadge c={C21} scenario={S8} />
        <OutcomeBadge c={{ ...C21, mode: 'board' }} form="long" />
        <ExpectedMark c={C21} scenario={S8} />
        <ExpectedMark c={{ state: 'awaiting_approval', disposition: 'resend' }} scenario={S8} />
      </>,
    );
    // The outcome badge and the expectation's mark both say it; nothing at all while the case waits
    expect(screen.getAllByText('Not as expected')).toHaveLength(2);
    expect(screen.getByText('Delivered: verified at the receiver')).toBeInTheDocument();
    expect(screen.queryByText('As expected')).not.toBeInTheDocument();
  });

  it('draws the gate checks, the agreement and identities as graphics beside their words', () => {
    const { container } = renderUi(
      <>
        <CheckStrip
          checks={[
            { result: 'pass', reason_code: 'FRESH' },
            { result: 'pass', reason_code: 'NOT_APPLICABLE' },
            { result: 'block', reason_code: 'SUPERSEDED_BY_LATER_EVENT' },
          ]}
        />
        <AgreementDots
          proposed={{ conformance: false, encounter: true, impact: true }}
          agreement="with the majority"
        />
        <IdentityBadge hue="violet">Board</IdentityBadge>
        <MemberAvatar member="impact" />
        <CodeChip>APPROVAL_RECEIVER_CHANGED</CodeChip>
      </>,
    );
    expect(screen.getByText('1 passed, 1 blocked, 1 not applicable')).toBeInTheDocument();
    expect(
      [...container.querySelectorAll('.check-strip span')].map((s) => s.getAttribute('data-tone')),
    ).toEqual(['positive', 'neutral', 'blocking']);
    expect(screen.getByText('With the majority')).toBeInTheDocument();
    expect(container.querySelectorAll('.agreement-dots span[data-hollow]')).toHaveLength(1);
    expect(screen.getByText('Board')).toBeInTheDocument();
    expect(container.querySelector('.identity-mark[data-member="impact"]')).toHaveAttribute(
      'aria-hidden',
      'true',
    );
    expect(screen.getByText('APPROVAL_RECEIVER_CHANGED')).toHaveClass('code-chip');
  });

  it("frames a member's card in its hue, with its name and meta", () => {
    renderUi(
      <MemberCard
        member="encounter"
        meta="claude-opus-5-5 · 14.6 s"
        aria-label="Encounter Integrity's finding"
      >
        Escalate
      </MemberCard>,
    );
    const card = screen.getByRole('region', { name: "Encounter Integrity's finding" });
    expect(within(card).getByRole('heading', { name: 'Encounter Integrity' })).toBeInTheDocument();
    expect(card).toHaveClass('member-card');
    expect(card).toHaveTextContent('claude-opus-5-5 · 14.6 s');
  });

  it('says beside a confirm whether it acts in the trial or on the live system', () => {
    const { unmount } = renderUi(<EnvChip />);
    expect(screen.getByText('Live system')).toBeInTheDocument();
    unmount();
    mode.trial = true;
    renderUi(<EnvChip />);
    expect(screen.getByText('Trial only')).toBeInTheDocument();
    mode.trial = false;
  });

  it("says what each tone means in the legend's own words, and keeps a badge's default size", () => {
    renderUi(
      <>
        <ToneLegend />
        <StatusBadge tone="info" label="Running" />
      </>,
    );
    const legend = screen.getByRole('list', { name: 'What the colours mean' });
    expect(legend).toHaveTextContent('Neutralclosed, or a decision; nothing waiting');
    expect(legend).toHaveTextContent(
      'Positiveverified at the receiver, a passed check, or a result as expected',
    );
    expect(legend).toHaveTextContent('Blockingrefused, failed or contradicted at the receiver');
    expect(screen.getByText('Running').closest('.mantine-Badge-root')).toHaveAttribute('data-size', 'sm');
  });
});
