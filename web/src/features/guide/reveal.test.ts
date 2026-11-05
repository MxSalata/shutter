import { VisuallyHidden } from '@mantine/core';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { bringIntoFreePart, freeTop, headingOf, landOn } from './reveal';

afterEach(() => document.body.replaceChildren());

describe('headingOf', () => {
  it('passes over a heading kept for screen readers only, to the first one a reader sees', () => {
    const section = document.createElement('div');
    section.innerHTML = `<h2 class="${VisuallyHidden.classes.root}">Every scenario</h2><div><h3>S2</h3></div>`;
    document.body.append(section);
    expect(headingOf(section).textContent).toBe('S2');
  });

  it('falls back to the section itself when it has no visible heading', () => {
    const section = document.createElement('div');
    section.innerHTML = `<h2 class="${VisuallyHidden.classes.root}">Every scenario</h2>`;
    document.body.append(section);
    expect(headingOf(section)).toBe(section);
  });
});

/** An element whose measured box starts at `top` and is `height` tall. */
function box(parent: HTMLElement, className: string, top: number, height: number) {
  const el = document.createElement('div');
  el.className = className;
  el.getBoundingClientRect = () => ({ top, bottom: top + height, height }) as DOMRect;
  parent.append(el);
  return el;
}

describe('freeTop', () => {
  it("counts the header, and a sticky bar only for what stands in the bar's own container", () => {
    box(document.body, 'mantine-AppShell-header', 0, 110);
    const tabs = document.createElement('div');
    document.body.append(tabs);
    box(tabs, 'sticky-tabs', 900, 40);
    const inside = box(tabs, 'panel', 950, 10);
    const above = box(document.body, 'band', 300, 10);
    expect(freeTop(inside)).toBe(150);
    expect(freeTop(above)).toBe(110);
  });
});

describe('landOn and bringIntoFreePart', () => {
  it('stops when the reader moves, and aims again when the page moves until then', () => {
    vi.useFakeTimers();
    const scrollTo = vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    Object.defineProperty(document.documentElement, 'scrollHeight', { configurable: true, value: 5000 });
    let top = 1000;
    const el = box(document.body, 'host', 0, 10);
    el.getBoundingClientRect = () => ({ top, bottom: top + 10, height: 10 }) as DOMRect;
    const stop = landOn(el, false);
    expect(scrollTo).toHaveBeenLastCalledWith({ top: 984, behavior: 'smooth' });
    top = 1200;
    vi.advanceTimersByTime(60);
    expect(scrollTo).toHaveBeenLastCalledWith({ top: 1184, behavior: 'smooth' });
    window.dispatchEvent(new Event('wheel'));
    const calls = scrollTo.mock.calls.length;
    top = 1500;
    vi.advanceTimersByTime(200);
    expect(scrollTo.mock.calls.length).toBe(calls);
    stop();
    vi.useRealTimers();
    scrollTo.mockRestore();
    Reflect.deleteProperty(document.documentElement, 'scrollHeight');
  });

  it('leaves a control that is already in the free part where it is', () => {
    const scrollTo = vi.spyOn(window, 'scrollTo').mockImplementation(() => {});
    box(document.body, 'mantine-AppShell-header', 0, 88);
    bringIntoFreePart(box(document.body, 'control', 200, 36), false);
    expect(scrollTo).not.toHaveBeenCalled();
    bringIntoFreePart(box(document.body, 'control', 40, 36), false);
    expect(scrollTo).toHaveBeenCalledTimes(1);
    scrollTo.mockRestore();
  });
});
