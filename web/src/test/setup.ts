import '@testing-library/jest-dom/vitest';
import { platform } from '@floating-ui/react';
import { configure } from '@testing-library/react';

// findBy and waitFor wait 1 s by default; a loaded CI runner renders a page with its mock fetches in more than that.
configure({ asyncUtilTimeout: 5_000 });

// jsdom lacks a few browser APIs Mantine relies on.
if (!window.matchMedia) {
  Object.defineProperty(window, 'matchMedia', {
    writable: true,
    value: (query: string) => ({
      matches: false,
      media: query,
      onchange: null,
      addListener: () => {},
      removeListener: () => {},
      addEventListener: () => {},
      removeEventListener: () => {},
      dispatchEvent: () => false,
    }),
  });
}
if (!window.ResizeObserver) {
  class RO {
    observe() {}
    unobserve() {}
    disconnect() {}
  }
  window.ResizeObserver = RO as unknown as typeof ResizeObserver;
}

// Floating UI places every Mantine tooltip, popover, menu and select. jsdom has no layout, so a position means
// nothing there, but three of its measurements walk the element's ancestors with getComputedStyle and take seconds
// each in jsdom: one opened tooltip held the event loop for 50 to 70 s on House. Here they answer at once: the window
// is the offset parent, a rect needs no converting, and the clipping rect reaches past the window on every side.
// Every jsdom rect is empty at the origin, which a clipping rect starting at the origin would count as clipped, so
// Mantine would hide an open dropdown (its hideDetached); nothing is clipped, as for a control in view.
const floating = platform as unknown as Record<string, unknown>;
floating.getOffsetParent = () => window;
floating.getClippingRect = () => ({
  x: -window.innerWidth,
  y: -window.innerHeight,
  width: 3 * window.innerWidth,
  height: 3 * window.innerHeight,
});
floating.convertOffsetParentRelativeRectToViewportRelativeRect = ({ rect }: { rect: unknown }) => rect;
