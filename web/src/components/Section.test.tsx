import { screen } from '@testing-library/react';
import { describe, expect, it } from 'vitest';
import { renderUi } from '@/test/render';
import { Section } from './Section';

describe('Section', () => {
  it('keeps its intro to the prose width, under the heading and beside the aside', () => {
    renderUi(
      <Section id="plan" title="The plan" note="What Shutter proposes." aside={<span>Draft</span>}>
        <p>Content</p>
      </Section>,
    );
    const heading = screen.getByRole('heading', { level: 2, name: 'The plan' });
    const intro = heading.nextElementSibling as HTMLElement;
    expect(intro).toHaveTextContent('What Shutter proposes.');
    expect(intro.style.maxWidth).toBe('68ch');
    expect(screen.getByRole('region', { name: 'The plan' })).toHaveTextContent('Draft');
  });

  it('runs a wide intro the whole width, still next after the heading, with the aside kept', () => {
    renderUi(
      <Section
        id="receivers"
        title="Receivers"
        wideNote
        note="For each system this production feeds."
        aside={<button type="button">Collapse</button>}
      >
        <p>Content</p>
      </Section>,
    );
    const heading = screen.getByRole('heading', { level: 2, name: 'Receivers' });
    expect(heading).toHaveAttribute('id', 'receivers-title');
    const intro = heading.nextElementSibling as HTMLElement;
    expect(intro.tagName).toBe('P');
    expect(intro).toHaveTextContent('For each system this production feeds.');
    expect(intro.style.maxWidth).toBe('');
    const region = screen.getByRole('region', { name: 'Receivers' });
    expect(region).toContainElement(screen.getByRole('button', { name: 'Collapse' }));
    expect(region).toHaveTextContent('Content');
  });

  it('needs no intro or aside to be wide', () => {
    renderUi(
      <Section id="a08" title="An A08 location" wideNote>
        <p>Content</p>
      </Section>,
    );
    expect(screen.getByRole('heading', { level: 2, name: 'An A08 location' }).nextElementSibling).toBeNull();
  });
});
