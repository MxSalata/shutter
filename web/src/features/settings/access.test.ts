import { describe, expect, it } from 'vitest';
import type { AccessReport, AccessRow } from '@/api/types';
import {
  ACCESS_COLUMNS,
  ACCESS_ROW_WORDS,
  compareLine,
  JUDGES_SENTENCE,
  matchingRoles,
  needsWords,
  rowWords,
  yourColumnSentence,
} from './access';

const row = (
  id: AccessRow['id'],
  cells: Record<string, boolean>,
  you: boolean,
  available = true,
): AccessRow => ({
  id,
  needs: [[`Shutter_${id}:U`]],
  available,
  roles: cells,
  you,
});

const cells = (demo: boolean, judge: boolean, operator: boolean, approver: boolean) => ({
  Shutter_Demo: demo,
  Shutter_Judge: judge,
  Shutter_Operator: operator,
  Shutter_Approver: approver,
  Shutter_Trace: false,
});

/** The installed roles' columns on a demo install, with `you` the judge's column. */
const judgeReport = (): Pick<AccessReport, 'rows' | 'read'> => ({
  read: 'recorded',
  rows: [
    row('view', cells(true, true, true, true), true),
    row('approve', cells(true, true, false, true), true),
    row('scenarios', cells(false, false, true, true), false),
    row('liveAgents', cells(false, true, true, true), true),
    row('configure', cells(false, false, false, true), false),
  ],
});

describe('matchingRoles', () => {
  it("names the installed role whose column is the user's, cell for cell", () => {
    expect(matchingRoles(judgeReport())).toEqual(['Shutter_Judge']);
  });

  it('names every role that matches when two columns are alike', () => {
    const r = judgeReport();
    r.rows = r.rows.filter((x) => x.id === 'view' || x.id === 'approve');
    expect(matchingRoles(r)).toEqual(['Shutter_Demo', 'Shutter_Judge', 'Shutter_Approver']);
  });

  it('names none for a sign-in with a role of its own', () => {
    const r = judgeReport();
    r.rows = r.rows.map((x) => ({ ...x, you: x.id === 'view' }));
    expect(matchingRoles(r)).toEqual([]);
  });

  it('leaves out the rows this instance has nothing to hold for', () => {
    const r = judgeReport();
    r.rows.push(row('guide', cells(false, false, false, false), false, false));
    expect(matchingRoles(r)).toEqual(['Shutter_Judge']);
  });

  it("names none while the roles' columns are not recorded, since they all read false", () => {
    const r = judgeReport();
    r.read = 'none';
    r.rows = r.rows.map((x) => ({ ...x, roles: cells(false, false, false, false) }));
    expect(matchingRoles(r)).toEqual([]);
  });
});

describe('compareLine', () => {
  it('names the role the user matches, in few words', () => {
    expect(compareLine(judgeReport())).toBe('Each sign-in compared: yours matches Judge');
  });

  it('says so for a role of its own, and names none while nothing is recorded', () => {
    const r = judgeReport();
    r.rows = r.rows.map((x) => ({ ...x, you: x.id === 'view' }));
    expect(compareLine(r)).toBe('Each sign-in compared: yours is a role of its own');
    expect(compareLine({ read: 'none', rows: [] })).toBe('Each sign-in compared');
  });
});

describe('yourColumnSentence', () => {
  it('names the matching role with its column head', () => {
    expect(yourColumnSentence(judgeReport())).toBe(
      "Your column is your sign-in's own. It matches Judge (Shutter_Judge).",
    );
  });

  it('says so for a role of its own', () => {
    const r = judgeReport();
    r.rows = r.rows.map((x) => ({ ...x, you: x.id === 'view' }));
    expect(yourColumnSentence(r)).toMatch(
      /matches none of the roles Shutter installs, so your sign-in has a role of its own\.$/,
    );
  });

  it("says the roles' columns are not recorded yet, and when they will be", () => {
    expect(yourColumnSentence({ read: 'none', rows: [] })).toMatch(
      /not recorded on this instance yet: the production's next start records them\.$/,
    );
  });
});

describe('the words', () => {
  it('has words for every row and a head for the four sign-in roles, and keeps "live" for the second layer', () => {
    expect(Object.keys(ACCESS_ROW_WORDS)).toEqual([
      'view',
      'approve',
      'scenarios',
      'liveAgents',
      'configure',
      'inbox',
      'guide',
      'trace',
      'publisher',
    ]);
    expect(ACCESS_COLUMNS.map((c) => c.role)).toEqual([
      'Shutter_Demo',
      'Shutter_Judge',
      'Shutter_Operator',
      'Shutter_Approver',
    ]);
    const words = [
      ...Object.values(ACCESS_ROW_WORDS),
      ...ACCESS_COLUMNS.map((c) => c.label),
      JUDGES_SENTENCE,
    ].join(' ');
    expect(words).not.toMatch(/\blive\b/i);
    expect(rowWords('liveAgents')).toMatch(/spends the model budget/);
    expect(rowWords('somethingNew')).toBe('somethingNew');
  });

  it("writes a row's needs as alternatives", () => {
    expect(needsWords([['Shutter_Operate:U']])).toBe('Shutter_Operate:U');
    expect(needsWords([['Shutter_Portal:U'], ['Shutter_Operate:U', '%Ens_Portal:U']])).toBe(
      'Shutter_Portal:U, or Shutter_Operate:U and %Ens_Portal:U',
    );
    expect(needsWords([])).toBe('nothing');
  });
});
