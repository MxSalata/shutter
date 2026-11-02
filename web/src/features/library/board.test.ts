import { describe, expect, it } from 'vitest';
import type { LibraryMember } from '@/api/types';
import fixtures from '@/mocks/fixtures.json';
import {
  boardLine,
  countWord,
  groupMembers,
  knowsWords,
  libraryLead,
  onDefaultBoard,
  roleLabel,
} from './board';

const library = fixtures.library as unknown as LibraryMember[];
const member = (over: Partial<LibraryMember>): LibraryMember => ({ ...library[0]!, ...over });

describe('groupMembers', () => {
  it('puts the specialists in a row, the coordinator under them and the single investigator apart', () => {
    const board = groupMembers(library);
    expect(board.specialists.map((m) => m.code)).toEqual(['conformance', 'encounter', 'impact']);
    expect(board.coordinators.map((m) => m.code)).toEqual(['coordinator']);
    expect(board.others.map((m) => m.code)).toEqual(['generalist']);
  });

  it('orders a row by its sort whatever order the server sends, and drops no member', () => {
    const extra = member({ code: 'privacy', name: 'Privacy', sort: 25 });
    const board = groupMembers([library[4]!, library[2]!, extra, library[3]!, library[1]!, library[0]!]);
    expect(board.specialists.map((m) => m.code)).toEqual(['conformance', 'encounter', 'privacy', 'impact']);
    expect(board.specialists.length + board.coordinators.length + board.others.length).toBe(6);
  });
});

describe('onDefaultBoard', () => {
  it('counts the specialists that are enabled and switched on, and the coordinator when it is enabled', () => {
    expect(onDefaultBoard(groupMembers(library))).toEqual({ on: 4, of: 4 });
    const some = library.map((m) =>
      m.code === 'encounter'
        ? { ...m, inDefaultBoard: false }
        : m.code === 'impact'
          ? { ...m, enabled: false }
          : m,
    );
    expect(onDefaultBoard(groupMembers(some))).toEqual({ on: 2, of: 4 });
    const noCoordinator = library.map((m) => (m.code === 'coordinator' ? { ...m, enabled: false } : m));
    expect(onDefaultBoard(groupMembers(noCoordinator))).toEqual({ on: 3, of: 4 });
  });

  it('does not count the single investigator either way', () => {
    const on = library.map((m) => (m.code === 'generalist' ? { ...m, inDefaultBoard: true } : m));
    expect(onDefaultBoard(groupMembers(on))).toEqual({ on: 4, of: 4 });
  });
});

describe('libraryLead', () => {
  it('says three specialist agents and a coordinator agent, on IRIS AI Hub', () => {
    expect(libraryLead(3)).toBe(
      'The agents a board is made from: three specialist agents and a coordinator agent, on IRIS AI Hub.',
    );
  });

  it("follows the library's own count of specialists", () => {
    expect(libraryLead(1)).toContain('one specialist agent and');
    expect(libraryLead(4)).toContain('four specialist agents and');
    expect(libraryLead(12)).toContain('12 specialist agents and');
    expect(countWord(0)).toBe('no');
  });
});

describe('the words on a card', () => {
  it('names the role in words, with the coordinator by what it does', () => {
    expect(roleLabel('specialist')).toBe('Specialist');
    expect(roleLabel('coordinator')).toBe('Proposes the plan');
    expect(roleLabel('generalist')).toBe('Generalist');
  });

  it('says what a member knows, in words', () => {
    expect(knowsWords('contracts')).toBe('contracts');
    expect(knowsWords('all')).toBe('every collection');
    expect(knowsWords('')).toBe('none');
    expect(knowsWords('none')).toBe('none');
  });

  it("gives the coordinator and the single investigator a line where the specialist's board switch is", () => {
    expect(boardLine('specialist')).toBeNull();
    expect(boardLine('coordinator')).toBe('Always on the board when enabled');
    expect(boardLine('generalist')).toBe('Used only in single investigator mode');
  });
});
