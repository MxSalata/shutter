import { DEFAULT_THEME } from '@mantine/core';
import { describe, expect, it } from 'vitest';
import { DISPOSITIONS } from '@/lib/status';
import {
  DISPOSITION_PALETTE,
  dispositionSlug,
  dispositionVariables,
  hasDispositionColour,
  type DispositionSwatch,
} from './theme';

/**
 * The disposition palette's promises (theme.ts): a colour for every disposition the app knows; the text and the icon
 * at 4.5:1 (WCAG 1.4.3) on the pill's own fill, or, for an outline, on every surface it can sit on; under high contrast
 * every tinted pill solid; and the dispositions told apart under protanopia and deuteranopia, by the simulation of
 * Machado, Oliveira and Fernandes (2009) at full severity, the distance measured in OKLab over the text and the fill.
 */

/** The surfaces a badge can sit on: the card, the page, a hovered row, and the darkest Pastel hovers; black and white. */
const SURFACES = {
  light: [
    '#ffffff',
    '#f9fafb',
    '#ebeef2',
    '#f1f3f5',
    '#e9ecef',
    '#faf8fe',
    '#f0ecf9',
    '#ddf2e6',
    '#f7edc9',
    '#e1effa',
  ],
  dark: ['#363f4c', '#2a323d', '#1f2630', '#181e26', '#000000'],
};

const rgb = (hex: string) => [1, 3, 5].map((i) => parseInt(hex.slice(i, i + 2), 16) / 255);
const linear = (c: number) => (c <= 0.04045 ? c / 12.92 : ((c + 0.055) / 1.055) ** 2.4);
const luminance = (hex: string) => {
  const [r, g, b] = rgb(hex).map(linear);
  return 0.2126 * r + 0.7152 * g + 0.0722 * b;
};
const contrast = (a: string, b: string) => {
  const [hi, lo] = [luminance(a), luminance(b)].sort((x, y) => y - x);
  return (hi + 0.05) / (lo + 0.05);
};

type Matrix = number[][];
const PROTAN: Matrix = [
  [0.152286, 1.052583, -0.204868],
  [0.114503, 0.786281, 0.099216],
  [-0.003882, -0.048116, 1.051998],
];
const DEUTAN: Matrix = [
  [0.367322, 0.860646, -0.227968],
  [0.280085, 0.672501, 0.047413],
  [-0.01182, 0.04294, 0.968881],
];
const apply = (m: Matrix, v: number[]) => m.map((row) => row.reduce((sum, x, i) => sum + x * v[i], 0));
const clamp = (v: number[]) => v.map((x) => Math.min(1, Math.max(0, x)));
const OKLAB_M1: Matrix = [
  [0.4122214708, 0.5363325363, 0.0514459929],
  [0.2119034982, 0.6806995451, 0.1073969566],
  [0.0883024619, 0.2817188376, 0.6299787005],
];
const OKLAB_M2: Matrix = [
  [0.2104542553, 0.793617785, -0.0040720468],
  [1.9779984951, -2.428592205, 0.4505937099],
  [0.0259040371, 0.7827717662, -0.808675766],
];
const oklab = (lin: number[]) => apply(OKLAB_M2, apply(OKLAB_M1, clamp(lin)).map(Math.cbrt));
const seen = (hex: string, vision: Matrix | null) => {
  const lin = rgb(hex).map(linear);
  return oklab(vision ? apply(vision, lin) : lin);
};
/** The distance between two badges as a kind of vision sees them: text and fill together, x 100. */
function apart(a: DispositionSwatch, b: DispositionSwatch, card: string, vision: Matrix | null): number {
  const fill = (s: DispositionSwatch) => (s.bg === 'transparent' ? card : s.bg);
  const d = (x: string, y: string) =>
    seen(x, vision).reduce((sum, v, i) => sum + (v - seen(y, vision)[i]) ** 2, 0);
  return Math.sqrt(d(a.fg, b.fg) + d(fill(a), fill(b))) * 100;
}

const names = Object.keys(DISPOSITION_PALETTE);
const pairs = names.flatMap((a, i) => names.slice(i + 1).map((b) => [a, b] as const));

describe('the disposition palette', () => {
  it('colours every disposition the status table knows, and no other', () => {
    expect(Object.keys(DISPOSITIONS).every(hasDispositionColour)).toBe(true);
    expect(names.sort()).toEqual(Object.keys(DISPOSITIONS).sort());
    expect(hasDispositionColour('something_else')).toBe(false);
    expect(dispositionSlug('more_evidence')).toBe('more-evidence');
  });

  for (const scheme of ['light', 'dark'] as const)
    it(`reads at 4.5:1 or more in ${scheme}, on its fill or on every surface an outline can sit on`, () => {
      for (const [name, p] of Object.entries(DISPOSITION_PALETTE)) {
        const s = p[scheme];
        const against = s.bg === 'transparent' ? SURFACES[scheme] : [s.bg];
        for (const surface of against)
          expect(contrast(s.fg, surface), `${name} on ${surface}`).toBeGreaterThanOrEqual(4.5);
        if (p.look === 'solid') expect(contrast(s.fg, s.bg), name).toBeGreaterThanOrEqual(4.5);
      }
    });

  it('turns a tinted pill solid under high contrast, white on the light text colour, and keeps the other looks', () => {
    const resolver = dispositionVariables('high');
    const vars = resolver(DEFAULT_THEME);
    for (const [name, p] of Object.entries(DISPOSITION_PALETTE)) {
      const stem = `--shutter-disposition-${dispositionSlug(name)}`;
      for (const scheme of ['light', 'dark'] as const) {
        const set = vars[scheme] as Record<string, string>;
        const got = { fg: set[`${stem}-fg`], bg: set[`${stem}-bg`], bd: set[`${stem}-bd`] };
        if (p.look === 'tint') {
          expect(got).toEqual({ fg: '#ffffff', bg: p.light.fg, bd: p.light.fg });
          expect(contrast('#ffffff', p.light.fg), name).toBeGreaterThanOrEqual(4.5);
        } else expect(got).toEqual(p[scheme]);
      }
    }
    const normal = dispositionVariables('normal')(DEFAULT_THEME);
    const light = normal.light as Record<string, string>;
    const dark = normal.dark as Record<string, string>;
    expect(light['--shutter-disposition-resend-bg']).toBe(DISPOSITION_PALETTE.resend.light.bg);
    expect(dark['--shutter-disposition-more-evidence-bg']).toBe('transparent');
    expect(normal.variables).toEqual({});
  });

  for (const scheme of ['light', 'dark'] as const)
    it(`keeps the dispositions apart for protanopia and deuteranopia in ${scheme}`, () => {
      const card = scheme === 'light' ? '#f9fafb' : '#1f2630';
      for (const [a, b] of pairs) {
        const pa = DISPOSITION_PALETTE[a as keyof typeof DISPOSITION_PALETTE];
        const pb = DISPOSITION_PALETTE[b as keyof typeof DISPOSITION_PALETTE];
        const worst = Math.min(
          apart(pa[scheme], pb[scheme], card, PROTAN),
          apart(pa[scheme], pb[scheme], card, DEUTAN),
        );
        // Two badges of the same look differ by colour alone, so they stand further apart; a tinted pill beside an
        // outline differs in shape as well
        expect(worst, `${a} and ${b}`).toBeGreaterThanOrEqual(pa.look === pb.look ? 9 : 6);
      }
    });
});
