import { MantineProvider } from '@mantine/core';
import { render, screen } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { useState } from 'react';
import { describe, expect, it } from 'vitest';
import type { SiteReceiver } from '@/api/types';
import { theme } from '@/theme';
import { fieldId, manualCheckProblem, validateProfile } from './profile';
import { RunbookField } from './RunbookField';

function Harness({ start, seen }: { start: SiteReceiver; seen: (r: SiteReceiver) => void }) {
  const [r, setR] = useState(start);
  return (
    <MantineProvider theme={theme}>
      <RunbookField
        r={r}
        i={0}
        err={() => undefined}
        update={(fn) => {
          const next = structuredClone(r);
          fn(next);
          seen(next);
          setR(next);
        }}
      />
    </MantineProvider>
  );
}

describe("the site's runbook line", () => {
  it('passes a plain line, with the > of a menu path', () => {
    expect(manualCheckProblem({ runbook: 'In Encounter > Movements, search the visit number.' })).toBe('');
    expect(manualCheckProblem({})).toBe('');
    expect(manualCheckProblem({ runbook: 'x'.repeat(300) })).toBe('');
  });

  it.each([
    ['<b>x</b>', 'HTML'],
    ['see http://pas.example/x', 'links'],
    ['see www.example.org', 'links'],
    ['password: hunter2', 'credentials'],
    ['api key = abc', 'credentials'],
    ['patient 1234567', 'identifiers'],
    ['two\nlines', 'one line'],
    ['  ', 'blank'],
    ['x'.repeat(301), '300'],
  ])('refuses %s', (runbook, why) => {
    expect(manualCheckProblem({ runbook })).toContain(why);
  });

  it('refuses another shape, and the profile names the field', () => {
    expect(manualCheckProblem('text')).toBe('must be an object');
    expect(manualCheckProblem({ other: 'x' })).toContain('unknown field');
    expect(manualCheckProblem({ runbook: 5 })).toContain('must be text');
    const p = {
      receivers: [{ name: 'R', tier: 2, manual_check: { runbook: '<script>' } }],
      policy: { '1': {}, '2': {}, '3': {} },
    };
    expect(validateProfile(p)).toContain('receivers[0].manual_check.runbook');
    expect(fieldId('receivers[0].manual_check.runbook')).toBe('site-receivers-0-manual_check.runbook');
  });

  it('is folded until asked for, and clearing it removes it', async () => {
    let last: SiteReceiver | undefined;
    render(<Harness start={{ name: 'R', tier: 2 }} seen={(r) => (last = r)} />);
    expect(screen.queryByLabelText('Where to look at this receiver')).toBeNull();
    await userEvent.click(screen.getByRole('button', { name: 'Site runbook line' }));
    const input = screen.getByLabelText('Where to look at this receiver');
    await userEvent.type(input, 'Yes');
    expect(last?.manual_check).toEqual({ runbook: 'Yes' });
    await userEvent.clear(input);
    expect(last).not.toHaveProperty('manual_check');
  });
});
