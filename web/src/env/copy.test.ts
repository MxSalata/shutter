import { readdirSync, readFileSync, statSync } from 'node:fs';
import { join, relative } from 'node:path';
import { describe, expect, it, vi } from 'vitest';

const mode = vi.hoisted(() => ({ trial: false }));
vi.mock('./mode', async (importOriginal) => ({
  ...(await importOriginal<typeof import('./mode')>()),
  get TRIAL() {
    return mode.trial;
  },
}));

const { byEnv, NOT_IN_TRIAL } = await import('./copy');

describe('byEnv', () => {
  it("picks the live wording in a live page and the trial's in a trial page", () => {
    const words = {
      live: 'Version 11 saved.',
      trial: 'Saved in the trial. It lasts until you reload or leave.',
    };
    mode.trial = false;
    expect(byEnv(words)).toBe('Version 11 saved.');
    mode.trial = true;
    expect(byEnv(words)).toBe('Saved in the trial. It lasts until you reload or leave.');
  });

  it("names the trial's limits in the trial's own words", () => {
    expect(Object.values(NOT_IN_TRIAL).every((s) => /trial/.test(s))).toBe(true);
  });
});

/** Every source file under src/, for the writing rules that hold everywhere. */
function sources(dir: string): string[] {
  return readdirSync(dir).flatMap((name) => {
    const path = join(dir, name);
    return statSync(path).isDirectory() ? sources(path) : /\.(tsx?|css|json|html)$/.test(name) ? [path] : [];
  });
}

describe('the writing rules', () => {
  it('leave no em or en dash anywhere in src/', () => {
    const root = join(__dirname, '..');
    const found = sources(root).flatMap((path) =>
      readFileSync(path, 'utf8')
        .split('\n')
        .flatMap((line, i) => (/[\u2013\u2014]/.test(line) ? [`${relative(root, path)}:${i + 1}`] : [])),
    );
    expect(found).toEqual([]);
  });
});
