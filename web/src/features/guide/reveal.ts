/**
 * Finding and showing a step's section: the element with its `data-tour` attribute, once the page has rendered it,
 * and the heading inside it, which takes focus. Targets are the registry's own fixed names, so they need no escaping.
 */
export const tourSelector = (target: string) => `[data-tour="${target}"]`;

const shown = (el: HTMLElement) =>
  el.isConnected && (typeof el.checkVisibility !== 'function' || el.checkVisibility());

/** The target once it is on the page and visible; null when it has not appeared within the time. */
export function waitForTarget(target: string, timeoutMs = 10_000): Promise<HTMLElement | null> {
  return new Promise((resolve) => {
    const started = Date.now();
    const look = () => {
      const el = document.querySelector<HTMLElement>(tourSelector(target));
      if (el && shown(el)) return resolve(el);
      if (Date.now() - started >= timeoutMs) return resolve(null);
      window.setTimeout(look, 100);
    };
    look();
  });
}

/** The section's heading: the target itself when it is one, else the first heading inside it. */
export function headingOf(el: HTMLElement): HTMLElement {
  if (/^H[1-6]$/.test(el.tagName)) return el;
  return el.querySelector<HTMLElement>('h1, h2, h3, h4, h5, h6') ?? el;
}

/** Moves focus to the element, making it focusable from script only (tabIndex -1) when it is not already. */
export function focusFrom(el: HTMLElement): void {
  if (!el.hasAttribute('tabindex') && el.tabIndex < 0) el.tabIndex = -1;
  el.focus({ preventScroll: true });
}

/** The page's own heading, where focus goes when a section could not be found or a closing dialog's opener is gone. */
export function pageHeading(): HTMLElement | null {
  return document.querySelector<HTMLElement>('main h1') ?? document.querySelector<HTMLElement>('main');
}
