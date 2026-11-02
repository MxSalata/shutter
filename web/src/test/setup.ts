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
// each in jsdom: one opened tooltip held the event loop for 50 to 70 s on House. In jsdom the window is the offset
// parent and the clipping rect, and a rect needs no converting, so these answer at once with what they would find.
const floating = platform as unknown as Record<string, unknown>;
floating.getOffsetParent = () => window;
floating.getClippingRect = () => ({ x: 0, y: 0, width: window.innerWidth, height: window.innerHeight });
floating.convertOffsetParentRelativeRectToViewportRelativeRect = ({ rect }: { rect: unknown }) => rect;
