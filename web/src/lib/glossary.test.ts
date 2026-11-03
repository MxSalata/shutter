import { readdirSync } from 'node:fs';
import { resolve } from 'node:path';
import { describe, expect, it } from 'vitest';
import { GLOSSARY } from './glossary';

describe('the glossary', () => {
  it('defines each term in at most 25 plain words, with no dashes and no selling', () => {
    for (const [key, e] of Object.entries(GLOSSARY)) {
      expect(e.definition.split(/\s+/).length, key).toBeLessThanOrEqual(25);
      expect(e.definition, key).not.toMatch(/[\u2013\u2014]|AI-powered|intelligent|smart/i);
    }
  });

  it("marks HL7's own terms standard, so Technical reads them as plain text, and none of Shutter's", () => {
    const standard = Object.entries(GLOSSARY)
      .filter(([, e]) => 'standard' in e && e.standard)
      .map(([k]) => k)
      .sort();
    expect(standard).toEqual(['adt', 'hl7', 'hl7-transfer', 'msh-7', 'pas']);
  });

  it("names the catalogue's range as knowledge/catalogue has it", () => {
    // The tests run from web/, beside the catalogue's folder
    const entries = readdirSync(resolve(process.cwd(), '../knowledge/catalogue')).filter((f) =>
      /^E\d+\.md$/.test(f),
    );
    expect(GLOSSARY['catalogue-entry'].term).toBe(`Catalogue entry (E1 to E${entries.length})`);
  });

  it('calls the board agents, on IRIS AI Hub', () => {
    expect(GLOSSARY.board.definition).toMatch(/specialist agents/);
    expect(GLOSSARY.board.definition).toMatch(/IRIS AI Hub/);
  });
});
