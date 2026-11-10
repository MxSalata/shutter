import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { kindLabel } from './derive';
import { FindingsLines } from './FindingsLines';
import { characterLines } from './characterLines';

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

  it('gives each field its own line, every place it stands named once, with its count, as the 1.4.0 recheck found it was not', () => {
    const e = 'e with a grave accent, U+00E8';
    const f = (field: string, position: number, component = 1) => ({
      field,
      position,
      component,
      character: e,
      wire: 'E8',
    });
    const character = {
      kind: 'characters',
      sentence: 'one long paragraph',
      shared: { failures: 7, of_failures: 7, characters: e },
      count: {
        'PID-5': { failures: 6, of_failures: 7, delivered: 0, of_delivered: 2 },
        'NTE-3': { failures: 6, of_failures: 7, delivered: 0, of_delivered: 2 },
      },
      fields: [f('PID-5', 3), f('PID-5', 4, 2), f('NTE-3', 9), f('NTE-3', 11), f('NTE-3', 28)],
      questions: [],
      msh18: '',
      setting: 'latin1',
    };
    expect(characterLines(character)).toEqual([
      `7 of the last 7 failures to this receiver in 7 days hold ${e}, in any field.`,
      `PID-5 holds ${e} at position 3 and position 4 of component 2; the operation sends E8. 6 of the last 7 failures to this receiver in 7 days carry a character above ASCII in PID-5; 0 of the last 2 delivered do.`,
      `NTE-3 holds ${e} at position 9, position 11 and position 28; the operation sends E8. 6 of the last 7 failures to this receiver in 7 days carry a character above ASCII in NTE-3; 0 of the last 2 delivered do.`,
      "Stored MSH-18: empty; the operation's DefCharEncoding: latin1.",
    ]);
    renderUi(<FindingsLines d={{ ...FINDINGS, character }} />);
    const block = screen.getByTestId('findings');
    expect(block.children).toHaveLength(3 + 4);
    expect(block).not.toHaveTextContent('one long paragraph');
    // A finding with no fields keeps its own sentence
    expect(characterLines({ kind: 'question', sentence: 'PID-3 holds a ? at position 6.' })).toEqual([
      'PID-3 holds a ? at position 6.',
    ]);
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
