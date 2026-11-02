import type { LibraryMember } from '@/api/types';
import { humanize } from '@/lib/format';

/**
 * The library's members as the page lays them out: the specialists in a row, the coordinator under them, and every
 * other member (the single investigator) apart. A member is placed by its role and then its `sort`, so a site's extra
 * specialist joins the row of specialists and none is ever dropped.
 */
export interface Board {
  specialists: LibraryMember[];
  coordinators: LibraryMember[];
  others: LibraryMember[];
}

const bySort = (a: LibraryMember, b: LibraryMember) => a.sort - b.sort || a.name.localeCompare(b.name);

export function groupMembers(members: readonly LibraryMember[]): Board {
  const board: Board = { specialists: [], coordinators: [], others: [] };
  for (const m of members) {
    if (m.role === 'specialist') board.specialists.push(m);
    else if (m.role === 'coordinator') board.coordinators.push(m);
    else board.others.push(m);
  }
  board.specialists.sort(bySort);
  board.coordinators.sort(bySort);
  board.others.sort(bySort);
  return board;
}

/**
 * How many of the default board's members are on it: a specialist must be enabled and switched onto the board, the
 * coordinator is always on it when enabled. Members that never sit on the board (the single investigator) are not
 * counted either way.
 */
export function onDefaultBoard(board: Board): { on: number; of: number } {
  const specialists = board.specialists.filter((m) => m.enabled && m.inDefaultBoard).length;
  const coordinators = board.coordinators.filter((m) => m.enabled).length;
  return { on: specialists + coordinators, of: board.specialists.length + board.coordinators.length };
}

const NUMBER_WORDS = ['no', 'one', 'two', 'three', 'four', 'five', 'six', 'seven', 'eight', 'nine', 'ten'];

/** A count in words up to ten, digits after that. */
export const countWord = (n: number) => NUMBER_WORDS[n] ?? String(n);

/**
 * The page's one-sentence lead (N1, F3): the members are agents, and they run on IRIS AI Hub. The number of
 * specialists is the library's own, three until a site adds one.
 */
export function libraryLead(specialists: number): string {
  return `The agents a board is made from: ${countWord(specialists)} specialist ${
    specialists === 1 ? 'agent' : 'agents'
  } and a coordinator agent, on IRIS AI Hub.`;
}

/** What the member's role is called on its card. The coordinator's role says what it does. */
export function roleLabel(role: LibraryMember['role']): string {
  if (role === 'specialist') return 'Specialist';
  if (role === 'coordinator') return 'Proposes the plan';
  return humanize(role);
}

/** The words after "Knows:" for a member's knowledge collection. */
export function knowsWords(collection: string | undefined | null): string {
  if (!collection || collection === 'none') return 'none';
  if (collection === 'all') return 'every collection';
  return collection;
}

/** The line that stands where a specialist's "on the default board" switch is, for a member that has no such switch. */
export function boardLine(role: LibraryMember['role']): string | null {
  if (role === 'coordinator') return 'Always on the board when enabled';
  if (role === 'specialist') return null;
  return 'Used only in single investigator mode';
}
