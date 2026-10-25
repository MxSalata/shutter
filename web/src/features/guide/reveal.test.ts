import { VisuallyHidden } from '@mantine/core';
import { afterEach, describe, expect, it } from 'vitest';
import { headingOf } from './reveal';

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
