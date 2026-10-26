import '@testing-library/jest-dom/vitest';
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
