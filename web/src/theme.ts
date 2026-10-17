import { createTheme, rem, type MantineColorsTuple, type MantineThemeOverride } from '@mantine/core';

export const APP_NAME = 'Shutter';
export const APP_TAGLINE = 'Failed messages, investigated, gated, approved and verified';

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
  headings: { fontWeight: '650', sizes: { h1: { fontSize: rem(28), lineHeight: '1.25' } } },
  fontSizes: { xs: rem(12), sm: rem(13.5), md: rem(15), lg: rem(17), xl: rem(20) },
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
