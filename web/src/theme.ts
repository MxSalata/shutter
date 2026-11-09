import {
  createTheme,
  rem,
  type CSSVariablesResolver,
  type MantineColorsTuple,
  type MantineThemeOverride,
} from '@mantine/core';
import type { Disposition } from '@/api/types';

export const APP_NAME = 'Shutter';
export const APP_TAGLINE = 'Failed messages, investigated, gated, released and verified';

/**
 * The primary: an ocean blue-teal rather than Mantine's stock indigo. Shades 7 to 9 carry
 * white text and text on white or on the page tone at 5.4:1 and more; shades 3 and 4 carry text
 * on the dark surfaces (styles.css picks, per role, the shade that reaches 4.5:1).
 */
const shutter: MantineColorsTuple = [
  '#e7f5fa',
  '#cdeaf3',
  '#a1d6e8',
  '#6fc0dc',
  '#45acd1',
  '#2a9dc9',
  '#1788b3',
  '#0e7299',
  '#095c7c',
  '#054760',
];

/**
 * Dark surfaces in slate instead of neutral grey: body dark-7, the page behind the cards dark-8.
 * dark-1 (dimmed text) reads at 7.9:1 on dark-7 and dark-2 (icons) at 5.3:1.
 */
const dark: MantineColorsTuple = [
  '#d0d6de',
  '#b3bcc8',
  '#8e99a8',
  '#6b7686',
  '#4a5463',
  '#363f4c',
  '#2a323d',
  '#1f2630',
  '#181e26',
  '#11161c',
];

/** Base theme; App.tsx derives the contrast-aware variant from it. Fonts are the system stacks, which is what actually renders (nothing is web-loaded). */
export const themeBase: MantineThemeOverride = {
  colors: { shutter, dark },
  primaryColor: 'shutter',
  primaryShade: { light: 7, dark: 5 },
  defaultRadius: 'md',
  fontFamily:
    'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
  fontFamilyMonospace: 'ui-monospace, Menlo, Consolas, "Liberation Mono", monospace',
  // One type scale for every page (the restyle's design system, section 3): headings take their size from their
  // level, so no Title sets its own fz; body prose is md, table cells and secondary text sm.
  headings: {
    fontWeight: '650',
    sizes: {
      h1: { fontSize: rem(30), lineHeight: '1.2' },
      h2: { fontSize: rem(20), lineHeight: '1.3' },
      h3: { fontSize: rem(17), lineHeight: '1.35' },
      h4: { fontSize: rem(15), lineHeight: '1.4' },
    },
  },
  fontSizes: { xs: rem(12), sm: rem(14), md: rem(15), lg: rem(17), xl: rem(20) },
  lineHeights: { xs: '1.4', sm: '1.45', md: '1.55', lg: '1.45', xl: '1.3' },
  components: {
    Table: { defaultProps: { highlightOnHover: true, verticalSpacing: 'xs', fz: 'sm' } },
    // Cards sit on the page tone (styles.css --shutter-page) with a hairline shadow.
    Paper: { defaultProps: { withBorder: true, radius: 'md', shadow: 'xs' } },
    Card: { defaultProps: { withBorder: true, radius: 'md', shadow: 'xs' } },
    Badge: { defaultProps: { variant: 'light' } },
    Tooltip: { defaultProps: { withArrow: true, openDelay: 300 } },
    // Forms live in modals; a stray click outside must not discard a half-filled one (Escape still closes).
    Modal: { defaultProps: { closeOnClickOutside: false, closeButtonProps: { 'aria-label': 'Close' } } },
    // Mantine's close button has no accessible name of its own; every drawer gets one here.
    Drawer: { defaultProps: { closeButtonProps: { 'aria-label': 'Close' } } },
    // Without the focusable placeholder Mantine puts first in a menu, which a menu may not contain
    // (axe: aria-required-children); an opened menu focuses its first item, as the pattern has it.
    Menu: { defaultProps: { withInitialFocusPlaceholder: false } },
  },
};

export const theme = createTheme(themeBase);

/**
 * The events of a tooltip that carries a hint on an element made focusable for it (a status badge's hint, a time, a
 * digest, a comparison bar, a trace that is not a link in the trial): it opens on hover, on keyboard focus and on a
 * tap, so the keyboard and a touch screen reach the hint too (WCAG 2.1.1 and 1.4.13). Pass it as `events` to such a
 * tooltip. It is not the theme's default for every tooltip: in jsdom every focus counts as a visible one, so a page
 * test that clicks any control inside a tooltip would open it, and a control's own name already says what it does.
 */
export const HINT_EVENTS = { hover: true, focus: true, touch: true };

/**
 * Under high contrast the low-opacity `light` variant of badges and alerts is replaced by
 * solid/outlined ones at the theme level, so no call site needs a change; explicit
 * `variant` props still win.
 */
export function themeFor(contrast: 'normal' | 'high') {
  if (contrast === 'normal') return theme;
  return createTheme({
    ...themeBase,
    components: {
      ...themeBase.components,
      Badge: { defaultProps: { variant: 'filled' } },
      Alert: { defaultProps: { variant: 'outline' } },
      Tooltip: { defaultProps: { withArrow: true, openDelay: 300 } },
    },
  });
}

/**
 * The disposition palette: one colour per action a plan can take, so the action reads at a glance wherever it appears
 * (Evaluation's Expected, member, plan and Played columns, the case page, the Cases list, Scenarios). It is a family
 * of its own beside the five status tones and the identity hues: a disposition is a decision, not a result, so its
 * colour says which action, never whether it went well. Every badge keeps its icon and its word; the colour is a third
 * cue, never the only one. DESIGN.md section 2.8 has the table and the checks.
 *
 * Each disposition has a look, which survives without colour: a tinted pill (resend, reconcile, superseded, handled by
 * hand), an outline on the surface (more evidence, abandoned) or a solid pill (escalate, the one a person must act on).
 * The two that need a person, more evidence and escalate, share the vermilion and differ in look.
 *
 * Contrast (WCAG 1.4.3): the text and icon on the pill's own fill reach 5.3:1 or more in light and 7.1:1 in dark; an
 * outline's text reaches 5.3:1 on every surface it sits on (the cards, the page, striped and hovered rows, the Pastel
 * fills; dark-5 to dark-8 in dark). The fills are opaque, so a hovered or Pastel row cannot lower them. Under high
 * contrast every tinted pill turns solid: white on the light scheme's text colour, 6.4:1 or more in both schemes.
 *
 * Colour vision (Machado 2009, full severity; OKLab distance x 100 over the text and the fill together, the card
 * standing in for an outline's fill): resend and superseded sit at the two ends of the blue-yellow axis that protanopia
 * and deuteranopia keep. The closest pair is reconcile and abandoned (about 7 for deuteranopia, where one is a tinted
 * pill and the other an outline); two pills of the same look are 9 apart or more, and the words settle the rest.
 * theme.test.ts holds the palette to these figures.
 */
export interface DispositionSwatch {
  /** The text and the icon. */
  fg: string;
  /** The fill: `transparent` for an outline. */
  bg: string;
  /** The edge. */
  bd: string;
}

export type DispositionLook = 'tint' | 'outline' | 'solid';

export const DISPOSITION_PALETTE: Record<
  Disposition,
  { look: DispositionLook; light: DispositionSwatch; dark: DispositionSwatch }
> = {
  resend: {
    look: 'tint',
    light: { fg: '#1d5aa0', bg: '#dcecfc', bd: '#7fa9dc' },
    dark: { fg: '#b8d8ff', bg: '#173c6b', bd: '#4f86c9' },
  },
  reconcile: {
    look: 'tint',
    light: { fg: '#0f6b5c', bg: '#d3f1e7', bd: '#6fb5a3' },
    dark: { fg: '#9cf4d6', bg: '#083a2c', bd: '#3a9474' },
  },
  superseded: {
    look: 'tint',
    light: { fg: '#7a4600', bg: '#fde9c4', bd: '#d2a052' },
    dark: { fg: '#f7d28f', bg: '#4a340a', bd: '#a57c2c' },
  },
  more_evidence: {
    look: 'outline',
    light: { fg: '#a63c0e', bg: 'transparent', bd: '#a63c0e' },
    dark: { fg: '#f5a47e', bg: 'transparent', bd: '#f5a47e' },
  },
  escalate: {
    look: 'solid',
    light: { fg: '#ffffff', bg: '#a63c0e', bd: '#a63c0e' },
    dark: { fg: '#2b1103', bg: '#f08a58', bd: '#f08a58' },
  },
  handled_by_hand: {
    look: 'tint',
    light: { fg: '#373d44', bg: '#e0e4e8', bd: '#9aa2ab' },
    dark: { fg: '#e6e9ed', bg: '#474c53', bd: '#8a9099' },
  },
  abandoned: {
    look: 'outline',
    light: { fg: '#495057', bg: 'transparent', bd: '#495057' },
    dark: { fg: '#ced4da', bg: 'transparent', bd: '#ced4da' },
  },
};

/** A disposition's token stem: `--shutter-disposition-more-evidence-fg` and the like. */
export const dispositionSlug = (d: string) => d.replace(/_/g, '-');

/** Whether the palette has a colour for this disposition (an unknown one stays a neutral outline). */
export const hasDispositionColour = (d: string): d is Disposition => Object.hasOwn(DISPOSITION_PALETTE, d);

/** Under high contrast a tinted pill turns solid, white on the light scheme's text colour; the other looks stay. */
function highContrast(
  p: (typeof DISPOSITION_PALETTE)[Disposition],
  scheme: 'light' | 'dark',
): DispositionSwatch {
  if (p.look !== 'tint') return p[scheme];
  return { fg: '#ffffff', bg: p.light.fg, bd: p.light.fg };
}

/**
 * The palette as CSS variables, per colour scheme, for MantineProvider's `cssVariablesResolver`:
 * `--shutter-disposition-<slug>-fg`, `-bg` and `-bd`. App.tsx passes the variant for the contrast in use.
 */
export function dispositionVariables(contrast: 'normal' | 'high'): CSSVariablesResolver {
  const tokens = (scheme: 'light' | 'dark') =>
    Object.fromEntries(
      Object.entries(DISPOSITION_PALETTE).flatMap(([d, p]) => {
        const s = contrast === 'high' ? highContrast(p, scheme) : p[scheme];
        const stem = `--shutter-disposition-${dispositionSlug(d)}`;
        return [
          [`${stem}-fg`, s.fg],
          [`${stem}-bg`, s.bg],
          [`${stem}-bd`, s.bd],
        ];
      }),
    );
  return () => ({ variables: {}, light: tokens('light'), dark: tokens('dark') });
}
