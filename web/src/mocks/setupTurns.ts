import type { SetupTurnBody, SetupTurnView, SiteProfile, SiteReceiver } from '@/api/types';
import { draftRefusal, checkTurn, rowAutomatic } from '@/features/site-profile/setup/proposals';

/**
 * The mock's turns of Set up the site (CONTRACTS 14.7). No model reads anything here: a typed answer is read by
 * keyword, as the core's API mimic reads one (tests/mock, Shutter.Mock.Turns.SetupTurn), and every sentence is marked
 * [mock]. The reading is then checked as the core checks it (the fields an agent may draft, their values, the quote
 * against what was typed in the conversation, the effects check, the validator on a copy), so a turn the mock gives
 * back is one the server would have accepted, and one it would refuse ends schema_failed with nothing drafted. The
 * turns are kept in memory; no profile and no draft is stored.
 */

export const MAX_TURNS = 24;

interface Stored {
  view: SetupTurnView;
}

let turns: Record<string, Stored> = {};
let nextTurn = 1;
let nextConversation = 1;

export function resetSetupTurns(): void {
  turns = {};
  nextTurn = 1;
  nextConversation = 1;
}

const id = (prefix: string, n: number) => `${prefix}-${String(n).padStart(6, '0')}`;

export const newConversation = () => id('SC', nextConversation++);

/** The turns of a conversation, oldest first. */
export const turnsOf = (conversation: string) =>
  Object.values(turns)
    .map((t) => t.view)
    .filter((v) => v.conversation === conversation);

export const turnById = (turnId: string): SetupTurnView | undefined => turns[turnId]?.view;

const KIND_WORDS: [string, string][] = [
  ['whiteboard', 'current_state'],
  ['bed manager', 'current_state'],
  ['porter', 'current_state'],
  ['patients are now', 'current_state'],
  ['movement history', 'history_of_record'],
  ['patient record', 'history_of_record'],
  ['warehouse', 'history_of_record'],
  ['laborator', 'orders_results'],
  ['results', 'orders_results'],
  ['orders', 'orders_results'],
];

/** The reading by keyword: what the mimic would submit for this text, before any check. */
export function readByKeyword(
  text: string,
  base: SiteProfile,
  draft: SiteProfile,
  receiver: string,
): SetupTurnBody {
  const lower = text.toLowerCase();
  const inForce = base.receivers.some((r) => r.name === receiver);
  const entry = draft.receivers.find((r) => r.name === receiver) as Record<string, unknown> | undefined;
  const proposals: SetupTurnBody['proposals'] = [];
  const read: string[] = [];
  if (lower.includes('switch recovery on')) {
    // A forged proposal: a person-only field, which the check refuses whatever the words say
    proposals.push({
      field: 'recovery.mode',
      receiver,
      to: 'enabled',
      quote: 'switch recovery on',
      from: null,
    });
  } else {
    const mine = (key: string) =>
      draftRefusal(`receivers[].${key}`, base, draft, inForce, entry as SiteReceiver | undefined) === '';
    if (mine('system')) {
      const m = /\b(?:it is|it's|this is) ((?:the |a |an )?[a-z][a-z -]{2,60})/i.exec(text);
      if (m) {
        proposals.push({
          field: 'receivers[].system',
          receiver,
          to: m[1].trim(),
          quote: m[1].trim(),
          from: null,
        });
        read.push(`what it is: ${m[1].trim()}`);
      }
    }
    if (mine('category')) {
      const hit = KIND_WORDS.find(([word]) => lower.includes(word));
      if (hit) {
        const at = lower.indexOf(hit[0]);
        proposals.push({
          field: 'receivers[].category',
          receiver,
          to: hit[1],
          quote: text.slice(at, at + hit[0].length),
          from: null,
        });
        read.push(`its kind: ${hit[1]}`);
      }
    }
    if (mine('tier')) {
      const m = /tier ([123])/i.exec(text);
      if (m && !rowAutomatic(base, m[1]) && !rowAutomatic(draft, m[1])) {
        proposals.push({ field: 'receivers[].tier', receiver, to: m[1], quote: m[0], from: null });
        read.push(`its tier: ${m[1]}`);
      }
    }
  }
  const drafted = new Set(proposals.map((p) => p.field.split('.')[1]));
  const next = ['system', 'category', 'tier', 'applies', 'resend_timestamp', 'cancels', 'merges'].find(
    (key) => !drafted.has(key) && (entry?.[key] === undefined || entry[key] === ''),
  );
  return {
    say: `[mock] ${
      read.length
        ? `Read from your words about ${receiver}: ${read.join('; ')}.`
        : `Nothing in your words about ${receiver} could be read as an answer.`
    } Deterministic, from the API mimic; no model read the answer.`,
    proposals,
    ask: next ? { field: `receivers[].${next}`, receiver } : null,
  };
}

/**
 * Opens a turn and answers it at once: the reading by keyword, checked as the core checks it, with the quote held to
 * what this person typed in the conversation.
 */
export function answerTurn(
  conversation: string,
  receiver: string,
  text: string,
  base: SiteProfile,
  draft: SiteProfile,
  baseVersion: number,
  draftRevision: number,
  askedBy: string,
  at: string,
): SetupTurnView {
  const typed = [...turnsOf(conversation).map((v) => v.text), text].map((t) =>
    t.toLowerCase().replace(/\s+/g, ' '),
  );
  const reading = readByKeyword(text, base, draft, receiver);
  const checked = checkTurn(reading, base, draft, receiver);
  const unquoted = checked.ok
    ? checked.turn.proposals.find(
        (p) => !typed.some((t) => t.includes(p.quote.toLowerCase().replace(/\s+/g, ' ').trim())),
      )
    : undefined;
  const problem = !checked.ok
    ? checked.problem
    : unquoted
      ? 'a quote is not part of what the person typed in this conversation'
      : '';
  const view: SetupTurnView = {
    turnId: id('ST', nextTurn++),
    conversation,
    receiver,
    text,
    state: problem ? 'schema_failed' : 'answered',
    baseVersion,
    draftRevision,
    askedBy,
    askedAt: at,
    answeredAt: at,
    error: problem || null,
    mode: 'live',
    model: 'mock',
    costUsd: 0,
    ensMessageId: null,
    messageLink: null,
    turn: checked.ok && !problem ? checked.turn : null,
  };
  turns[view.turnId] = { view };
  return view;
}
