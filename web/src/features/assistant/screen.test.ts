import { describe, expect, it } from 'vitest';
import {
  CONTEXT_MAX_CHARS,
  MAX_HEADINGS,
  MAX_ITEMS,
  MAX_TEXT,
  fitted,
  pageNameOf,
  summariseScreen,
} from './screen';

/** A page as the main region holds it. */
function page(html: string): HTMLElement {
  const main = document.createElement('main');
  main.innerHTML = html;
  return main;
}

describe("the page's name for the server", () => {
  it('is the first segment of the path, singular for a detail page, home for the root', () => {
    expect(pageNameOf('/')).toBe('home');
    expect(pageNameOf('/home')).toBe('home');
    expect(pageNameOf('/scenarios')).toBe('scenarios');
    expect(pageNameOf('/cases')).toBe('cases');
    expect(pageNameOf('/cases/C-000008')).toBe('case');
    expect(pageNameOf('/incidents/I-000001')).toBe('incident');
    expect(pageNameOf('/reviews/PR-000004')).toBe('review');
    expect(pageNameOf('/site-profile')).toBe('site-profile');
  });

  it("is always a lower-case word with hyphens, as the server's rule has it", () => {
    for (const p of ['/Site Profile', '/cases%20x', '/a_b', '/' + 'x'.repeat(60)])
      expect(pageNameOf(p)).toMatch(/^[a-z][a-z0-9-]{0,39}$/);
  });
});

describe('the summary of the screen', () => {
  it('reads the title, the lead, the headings and the ids the page links to, and nothing else', () => {
    const root = page(`
      <h1>Cases</h1>
      <p>Every failed delivery, newest first. The tiles show which need a person.</p>
      <h2>What needs you now</h2>
      <table><tr><td>MRN9007 in WARD-B</td><td><a href="#/cases/C-000008">Case C-000008</a></td></tr></table>
      <a href="#/cases/C-000008">Case C-000008</a>
      <a href="#/scenarios">S8: a transfer in a crowded ward</a>
      <a href="#/incidents/I-000002">Incident I-000002</a>
      <a href="#/site-profile">Site profile</a>
      <input value="a secret the reader typed" />
    `);
    const s = summariseScreen(root, 'cases');
    expect(s).toEqual({
      page: 'cases',
      title: 'Cases',
      lead: 'Every failed delivery, newest first. The tiles show which need a person.',
      headings: ['What needs you now'],
      items: [
        { id: 'C-000008', kind: 'case', label: 'Case C-000008' },
        { id: 'S8', kind: 'scenario', label: 'S8: a transfer in a crowded ward' },
        { id: 'I-000002', kind: 'incident', label: 'Incident I-000002' },
      ],
    });
    const json = JSON.stringify(s);
    expect(json).not.toContain('MRN9007');
    expect(json).not.toContain('secret');
  });

  it('leaves out the panel itself, the guide and anything hidden', () => {
    const root = page(`
      <h1>Scenarios</h1>
      <div id="ask-panel"><h2>Ask Shutter</h2><a href="#/cases/C-000001">C-000001</a></div>
      <div data-guide-card><h2>Step 7 of 9</h2></div>
      <div aria-hidden="true"><a href="#/cases/C-000002">C-000002</a></div>
      <h2>Then follow this path</h2>
    `);
    expect(summariseScreen(root, 'scenarios')).toEqual({
      page: 'scenarios',
      title: 'Scenarios',
      headings: ['Then follow this path'],
      items: [],
    });
  });

  it('caps the texts, the headings and the items at the server limits, and the whole at its length', () => {
    const headings = Array.from({ length: 30 }, (_, i) => `<h2>Heading ${i}</h2>`).join('');
    const links = Array.from(
      { length: 60 },
      (_, i) => `<a href="#/cases/C-${String(i + 1).padStart(6, '0')}">Case ${'x'.repeat(300)}</a>`,
    ).join('');
    const s = summariseScreen(page(`<h1>${'T'.repeat(500)}</h1>${headings}${links}`), 'cases');
    expect(s.title.length).toBeLessThanOrEqual(MAX_TEXT);
    expect(s.headings.length).toBeLessThanOrEqual(MAX_HEADINGS);
    expect(s.items.length).toBeLessThanOrEqual(MAX_ITEMS);
    for (const i of s.items) expect(i.label.length).toBeLessThanOrEqual(MAX_TEXT);
    expect(JSON.stringify(s).length).toBeLessThanOrEqual(CONTEXT_MAX_CHARS);
  });

  it('drops items first, then headings, then the lead, until it fits', () => {
    const big = {
      page: 'cases',
      title: 'Cases',
      lead: 'L'.repeat(200),
      headings: Array.from({ length: 20 }, (_, i) => `${'H'.repeat(190)}${i}`),
      items: Array.from({ length: 40 }, (_, i) => ({ id: `C-${i}`, kind: 'case', label: 'x'.repeat(190) })),
    };
    const s = fitted(big);
    expect(JSON.stringify(s).length).toBeLessThanOrEqual(CONTEXT_MAX_CHARS);
    expect(s.items.length).toBe(0);
    expect(s.headings.length).toBeLessThan(20);
    expect(s.title).toBe('Cases');
  });

  it('is empty, but for the page, with no page to read', () => {
    expect(summariseScreen(null, 'home')).toEqual({ page: 'home', title: '', headings: [], items: [] });
  });
});
