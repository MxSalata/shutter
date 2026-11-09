import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { TrialPill } from './TrialPill';

describe('TrialPill', () => {
  it('never shrinks, so a narrow header cannot cut its label to a sliver', () => {
    renderUi(<TrialPill />);
    const pill = screen.getByText('Trial').closest<HTMLElement>('.trial-pill')!;
    expect(pill).toHaveStyle({ flexShrink: '0' });
  });
});
