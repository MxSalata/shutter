import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';
import { revealSection } from './revealSection';

/** A section with its heading, as the case page's tabs draw them. */
function addSection(id: string, focusable = true) {
  const section = document.createElement('section');
  section.id = id;
  section.scrollIntoView = vi.fn();
  const heading = document.createElement('h2');
  heading.id = `${id}-title`;
  if (focusable) heading.tabIndex = -1;
  section.appendChild(heading);
  document.body.appendChild(section);
  return { section, heading };
}

describe('revealSection', () => {
  beforeEach(() => {
    vi.useFakeTimers();
  });
  afterEach(() => {
    vi.useRealTimers();
    document.body.innerHTML = '';
  });

  it('focuses the heading and scrolls to a section already on the page', () => {
    const { section, heading } = addSection('evidence');
    revealSection(['evidence']);
    vi.advanceTimersByTime(250);
    expect(document.activeElement).toBe(heading);
    expect(section.scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it('waits for a section that mounts late, as a tab does on a slow machine', () => {
    revealSection(['precedents']);
    vi.advanceTimersByTime(1000);
    const { section, heading } = addSection('precedents');
    vi.advanceTimersByTime(100);
    expect(document.activeElement).toBe(heading);
    expect(section.scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it('tries again while the heading cannot take the focus yet, and scrolls once', () => {
    const { section, heading } = addSection('precedents', false);
    revealSection(['precedents']);
    vi.advanceTimersByTime(600);
    expect(section.scrollIntoView).not.toHaveBeenCalled();
    heading.tabIndex = -1;
    vi.advanceTimersByTime(100);
    expect(document.activeElement).toBe(heading);
    expect(section.scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it('takes the first target on the page', () => {
    const { heading } = addSection('fallback');
    revealSection(['missing', 'fallback']);
    vi.advanceTimersByTime(250);
    expect(document.activeElement).toBe(heading);
  });

  it('leaves the focus where the reader put it, and still scrolls', () => {
    const { section, heading } = addSection('precedents');
    revealSection(['precedents'], () => false);
    vi.advanceTimersByTime(250);
    expect(document.activeElement).not.toBe(heading);
    expect(section.scrollIntoView).toHaveBeenCalledTimes(1);
  });

  it('gives up after three seconds, and still scrolls to a heading that never took the focus', () => {
    const { section } = addSection('precedents', false);
    revealSection(['precedents']);
    vi.advanceTimersByTime(10_000);
    expect(section.scrollIntoView).toHaveBeenCalledTimes(1);
    expect(vi.getTimerCount()).toBe(0);
  });

  it('stops quietly when no section ever comes', () => {
    revealSection(['missing']);
    vi.advanceTimersByTime(10_000);
    expect(vi.getTimerCount()).toBe(0);
  });
});
