import { createTheme, rem } from '@mantine/core';

export const APP_NAME = 'Interlock';
export const APP_TAGLINE = 'Failed messages, investigated, gated, approved and verified';

/** Mantine's indigo as the primary; the fonts are the system stacks (nothing is web-loaded). */
export const theme = createTheme({
  primaryColor: 'indigo',
  primaryShade: { light: 7, dark: 4 },
  defaultRadius: 'md',
  fontFamily:
    'ui-sans-serif, system-ui, -apple-system, "Segoe UI", Roboto, "Helvetica Neue", Arial, sans-serif',
  fontFamilyMonospace: 'ui-monospace, Menlo, Consolas, "Liberation Mono", monospace',
  headings: { fontWeight: '650', sizes: { h1: { fontSize: rem(26), lineHeight: '1.25' } } },
  fontSizes: { xs: rem(12), sm: rem(13.5), md: rem(15), lg: rem(17), xl: rem(20) },
  components: {
    Table: { defaultProps: { highlightOnHover: true, verticalSpacing: 'xs', fz: 'sm' } },
    Paper: { defaultProps: { withBorder: true, radius: 'md' } },
    Card: { defaultProps: { withBorder: true, radius: 'md' } },
    Badge: { defaultProps: { variant: 'light' } },
    Tooltip: { defaultProps: { withArrow: true, openDelay: 300 } },
    // A stray click outside must not discard a half-written decision (Escape still closes).
    Modal: { defaultProps: { closeOnClickOutside: false, closeButtonProps: { 'aria-label': 'Close' } } },
  },
});
