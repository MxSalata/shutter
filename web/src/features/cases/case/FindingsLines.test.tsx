import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { kindLabel } from './derive';
import { FindingsLines } from './FindingsLines';

/** A findings item as Shutter.Util.CaseFindings builds it; every wording and code is made up. */
const FINDINGS = {
  custody: {
    attempts: 'reached_receiver',
    state: 'settled',
    words: 'The receiver took this message on at least one attempt.',
  },
  reply: { kind: 'words', quote: 'MSA-3: Test code ZZUNK not recognised', msa1: 'AE', errors: [] },
  obx: {
    kind: 'obx',
    sentence: "The receiver's words name the 4th OBX of 6, set id OBX-1 = 4, code 'ZZUNK'.",
  },
  character: {
    kind: 'characters',
    sentence: 'PID-5 holds e with a grave accent, U+00E8 at position 5; the operation sends E8.',
  },
};

describe('FindingsLines', () => {
  it('shows the custody, the receiver words, the OBX and the character, each on its own line', () => {
    renderUi(<FindingsLines d={FINDINGS} />);
    const block = screen.getByTestId('findings');
    expect(block).toHaveTextContent('The receiver took this message on at least one attempt.');
    expect(block).toHaveTextContent("The receiver's words: MSA-3: Test code ZZUNK not recognised");
    expect(block).toHaveTextContent('set id OBX-1 = 4');
    expect(block).toHaveTextContent('PID-5 holds e with a grave accent');
  });

  it('says why when nothing was found, and names the section', () => {
    renderUi(
      <FindingsLines
        d={{ custody: {}, reply: {}, obx: {}, character: {}, why: 'the delivery header could not be read' }}
      />,
    );
    expect(screen.getByText('No finding: the delivery header could not be read.')).toBeInTheDocument();
    expect(kindLabel('findings')).toBe('What Shutter found in the order or result');
  });
});
