import { VisuallyHidden } from '@mantine/core';

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

/** A heading kept for screen readers only: focus there would show a sighted reader nothing. */
const hidden = (el: Element) => !!el.closest(`.${VisuallyHidden.classes.root}`);

/** The section's heading: the target itself when it is one, else the first visible heading inside it. */
export function headingOf(el: HTMLElement): HTMLElement {
  if (/^H[1-6]$/.test(el.tagName)) return el;
  const headings = el.querySelectorAll<HTMLElement>('h1, h2, h3, h4, h5, h6');
  return Array.from(headings).find((h) => !hidden(h)) ?? el;
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

/** The room left between what stays at the top of the screen and what was scrolled to. */
const CLEARANCE_PX = 16;
/** How long the page is watched after a step's card is placed: panels open and recorded parts arrive in that time. */
const SETTLE_MS = 4000;
const TICK_MS = 50;

/**
 * Where the free part of the screen starts for this element, measured: under the header, and under a sticky bar whose
 * own container holds the element, which will have stuck by the time the element is up there. A bar further down the
 * page is no cover for what stands above it, and a figure kept in the styles would miss a header that a larger text size
 * has grown, or a card standing just outside the tab panel the styles name.
 */
export function freeTop(el: HTMLElement): number {
  const header = document.querySelector('.mantine-AppShell-header')?.getBoundingClientRect().bottom ?? 0;
  const bar = Array.from(document.querySelectorAll<HTMLElement>('.sticky-tabs')).find(
    (b) => !b.contains(el) && b.parentElement?.contains(el),
  );
  return header + (bar?.getBoundingClientRect().height ?? 0);
}

/** A reader's own move ends the watch: the page is theirs from then on. */
const READER_MOVES = ['wheel', 'touchstart', 'pointerdown', 'keydown'] as const;

/**
 * Scrolls the page, and only the page, so the element stands just under what stays at the top of the screen, and keeps
 * aiming there while the page settles. A smooth scroll fixes where it stops when it starts, and limits that to the page's
 * height then: the card about to be drawn adds height, a story step opening moves everything below it, and a tab lays
 * out after the address changes. So the aim is measured again on every tick and the scroll sent again when it has
 * moved. It stops at its time limit, when the reader moves, or when something else moves the page after it has arrived.
 * Returns the function that stops it. `window.scrollTo` cannot shift the page sideways, as `scrollIntoView` can.
 */
export function landOn(el: HTMLElement, reduced: boolean): () => void {
  const started = Date.now();
  let goal: number | null = null;
  let lastY = -1;
  let arrived = false;
  const stop = () => {
    window.clearInterval(timer);
    READER_MOVES.forEach((m) => window.removeEventListener(m, stop, true));
  };
  const tick = () => {
    if (!el.isConnected || Date.now() - started > SETTLE_MS) return stop();
    const y = window.scrollY;
    const end = document.documentElement.scrollHeight - window.innerHeight;
    const aim = y + el.getBoundingClientRect().top - freeTop(el) - CLEARANCE_PX;
    const wanted = Math.max(0, Math.min(aim, end));
    const aimMoved = goal === null || Math.abs(wanted - goal) > 1;
    const off = Math.abs(y - wanted) > 1;
    if (!aimMoved && arrived && off) return stop();
    if (aimMoved || (off && y === lastY)) {
      goal = wanted;
      arrived = false;
      window.scrollTo({ top: wanted, behavior: reduced ? 'auto' : 'smooth' });
    } else if (!off) arrived = true;
    lastY = y;
  };
  const timer = window.setInterval(tick, TICK_MS);
  READER_MOVES.forEach((m) => window.addEventListener(m, stop, { capture: true, passive: true }));
  tick();
  return stop;
}

/**
 * Brings a control into the free part of the screen, in its middle, when it is not there already: a control already in
 * view stays where it is, and so does the card beside it.
 */
export function bringIntoFreePart(el: HTMLElement, reduced: boolean): void {
  const r = el.getBoundingClientRect();
  const free = freeTop(el);
  if (r.top >= free && r.bottom <= window.innerHeight) return;
  const top = window.scrollY + r.top - (free + window.innerHeight - r.height) / 2;
  window.scrollTo({ top: Math.max(0, top), behavior: reduced ? 'auto' : 'smooth' });
}
