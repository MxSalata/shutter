import type { Mode, Scenario, ScenarioStep } from '@/api/types';

/**
 * What a scenario's small diagram draws, read from the scenario itself: its steps, left to right, then the end its
 * `expected` gives in the mode. Nothing here is written per scenario, so a scenario that changes changes its diagram.
 * The end is what the scenario should end in, never what a run did: a recorded run can differ (S8 in Rules only wrote),
 * and the row's latest case says that. The words are the row's: a resend is conditional, and an escalation writes nothing.
 */
export type DiagramNode =
  | {
      kind: 'message';
      /** The HL7 event, as an engineer reads it: "A02". */
      event: string;
      /** The same in plain words: "Move". */
      plain: string;
      /** How many in a row. */
      count: number;
      mark?: 'fails' | 'withheld';
      /** A message from another source, or about another encounter, with the words under it. */
      aside?: 'source' | 'encounter';
    }
  | { kind: 'messages'; total: number; failed: number }
  | { kind: 'fault'; caption: string; words: string }
  | { kind: 'person'; caption: string; words: string };

export type EndKind = 'write' | 'writes' | 'none' | 'person';

export interface DiagramEnd {
  kind: EndKind;
  /** The writes it should make, conditional ones, never made before the gate. */
  writes: number;
  label: string;
  caption?: string;
  words: string;
}

export interface Diagram {
  nodes: DiagramNode[];
  end: DiagramEnd;
  /** The same in words, for a screen reader. */
  label: string;
}

/** More messages than this are counted, not drawn: S11 plays seventeen, and the picture would say less. */
const MOST_DRAWN = 6;

const PLAIN_EVENTS: Record<string, string> = {
  A01: 'Admit',
  A02: 'Move',
  A03: 'Discharge',
  A04: 'Register',
  A08: 'Update',
  A12: 'Cancel',
  A40: 'Merge',
};

/** What each fault of the scenario player does at the receiver, in the fewest words that are still true. */
const FAULTS: Record<string, { caption: string; words: string }> = {
  fail_before_accept: { caption: 'down', words: 'the receiver is down' },
  commit_drop_response: { caption: 'reply lost', words: 'the receiver commits, then its reply is lost' },
  misleading_duplicate_error: {
    caption: 'false error',
    words: 'the receiver answers with a misleading error',
  },
  delay_response: { caption: 'slow', words: 'the receiver is slow to answer' },
};

const eventOf = (step: ScenarioStep) => /(A\d{2})\.hl7$/i.exec(step.file ?? '')?.[1]?.toUpperCase();

/**
 * Only S8's summary says another source sent a message, and the steps carry no source (the sender is in the file's MSH-3,
 * which the app never reads). A test checks this reading against every fixture's MSH-3, so the two can't drift apart.
 */
const otherSourceAfterFailure = (s: Pick<Scenario, 'summary'>) =>
  /\bthe bed manager's own transfer\b/.test(s.summary ?? '');

function nodesOf(s: Pick<Scenario, 'summary' | 'steps' | 'expected'>): DiagramNode[] {
  const steps = s.steps ?? [];
  const sent = steps.filter((step) => step.file);
  if (sent.length > MOST_DRAWN) {
    const faults = steps.filter((step) => step.fault && step.fault !== 'off');
    const first = FAULTS[faults[0]?.fault ?? ''];
    const failed = sent.filter((step) => step.expect === 'delivery_fails').length;
    return [
      ...(first
        ? [
            {
              kind: 'fault' as const,
              caption: faults.length > 1 ? `${first.caption} ×${faults.length}` : first.caption,
              words: faults.length > 1 ? `${first.words}, ${faults.length} times` : first.words,
            },
          ]
        : []),
      { kind: 'messages', total: sent.length, failed },
    ];
  }
  const nodes: DiagramNode[] = [];
  const otherSource = otherSourceAfterFailure(s);
  let failedYet = false;
  for (const step of steps) {
    if (step.file) {
      const event = eventOf(step) ?? 'HL7';
      const mark =
        step.expect === 'delivery_fails' ? 'fails' : step.expect === 'withheld' ? 'withheld' : undefined;
      const aside =
        step.expect === 'indexed' && s.expected?.other_encounter
          ? 'encounter'
          : otherSource && failedYet && !mark
            ? 'source'
            : undefined;
      if (mark === 'fails') failedYet = true;
      const last = nodes[nodes.length - 1];
      if (last?.kind === 'message' && last.event === event && last.mark === mark && last.aside === aside)
        last.count += 1;
      else
        nodes.push({
          kind: 'message',
          event,
          plain: PLAIN_EVENTS[event] ?? event,
          count: 1,
          ...(mark ? { mark } : {}),
          ...(aside ? { aside } : {}),
        });
    } else if (step.fault && step.fault !== 'off') {
      const known = FAULTS[step.fault] ?? { caption: 'fault', words: 'the receiver misbehaves' };
      const receivers = step.receivers?.length ?? 0;
      nodes.push(
        receivers > 1
          ? {
              kind: 'fault',
              caption: `${receivers} ${known.caption}`,
              words: `${receivers} receivers: ${known.words}`,
            }
          : { kind: 'fault', ...known },
      );
    } else if (step.capabilities?.conditional_writes === false) {
      nodes.push({
        kind: 'fault',
        caption: 'no guard',
        words: 'the receiver stops taking conditional writes',
      });
    } else if (step.manual) {
      nodes.push({
        kind: 'person',
        caption: 'by hand',
        words: 'a person changes the record at the receiver by hand',
      });
    }
  }
  return nodes;
}

const humanWord = (disposition: string | undefined) =>
  disposition === 'superseded' || disposition === 'reconcile' ? disposition : undefined;

const writesEnd = (n: number, inAll: boolean): DiagramEnd => ({
  kind: n === 1 ? 'write' : 'writes',
  writes: n,
  label: `${n} write${n === 1 ? '' : 's'}`,
  caption: 'conditional',
  words: `${n === 1 ? 'one conditional write' : `${n} conditional writes`}${inAll ? ' in all' : ''}`,
});

/** The end the scenario expects in the mode, by the same fields the row's "What should happen" reads. */
export function endOf(s: Pick<Scenario, 'expected'>, mode: Mode): DiagramEnd {
  const e = { ...s.expected, ...s.expected.by_mode?.[mode] };
  const none = (caption: string | undefined, words: string): DiagramEnd => ({
    kind: 'none',
    writes: 0,
    label: 'No write',
    ...(caption ? { caption } : {}),
    words,
  });
  if (e.incident && e.encounters?.length) {
    const n = e.encounters.reduce((sum, x) => sum + (x.writes || 0), 0);
    return n ? writesEnd(n, true) : none(undefined, 'nothing written');
  }
  if (e.by_receiver) {
    const receivers = Object.values(e.by_receiver);
    const n = receivers.filter((x) => x.write).length;
    if (n) return writesEnd(n, true);
    const people = receivers.filter((x) => x.disposition === 'escalate').length;
    if (people === receivers.length)
      return {
        kind: 'person',
        writes: 0,
        label: 'Person decides',
        caption: 'no write',
        words: 'a person decides, nothing written',
      };
    return none(
      people ? `${people === 1 ? 'one' : people} to a person` : undefined,
      `nothing written at any of ${receivers.length} receivers${people ? `; ${people === 1 ? 'one goes' : `${people} go`} to a person` : ''}`,
    );
  }
  const stopped = !!e.blocked_by;
  if (e.write) return writesEnd(1, false);
  if (e.disposition === 'escalate')
    return {
      kind: 'person',
      writes: 0,
      label: 'Person decides',
      caption: stopped ? 'no write, stopped' : 'no write',
      words: `a person decides, nothing written${stopped ? `, stopped on ${e.blocked_by}` : ''}`,
    };
  const word = humanWord(e.disposition);
  return none(
    stopped ? 'stopped' : word,
    `nothing written${word ? `, ${word}` : ''}${stopped ? `, stopped on ${e.blocked_by}` : ''}`,
  );
}

function wordsOf(node: DiagramNode, technical: boolean): string {
  switch (node.kind) {
    case 'messages':
      return `${node.total} messages, ${node.failed} of them fail`;
    case 'fault':
    case 'person':
      return node.words;
    case 'message': {
      const name = technical ? node.event : node.plain.toLowerCase();
      const many = node.count > 1 ? `${node.count} × ` : '';
      const sent =
        node.mark === 'fails' ? 'fails' : node.mark === 'withheld' ? 'is withheld' : 'is delivered';
      const aside =
        node.aside === 'source'
          ? ', from another source, the bed manager'
          : node.aside === 'encounter'
            ? ', for another encounter'
            : '';
      return `${many}${name}${aside} ${node.count > 1 ? sent.replace('fails', 'fail').replace('is ', 'are ') : sent}`;
    }
  }
}

/**
 * A scenario's diagram in the mode, or null when it has nothing to draw from (an older server's list). `technical`
 * names messages by their HL7 events, as the row's own "HL7 events" line does; Plain by what they do.
 */
export function scenarioDiagram(
  s: Pick<Scenario, 'id' | 'summary' | 'steps' | 'expected'>,
  mode: Mode,
  technical = false,
): Diagram | null {
  if (!s.expected || !s.steps?.length) return null;
  const nodes = nodesOf(s);
  if (!nodes.length) return null;
  const end = endOf(s, mode);
  return {
    nodes,
    end,
    label: `${s.id} in a diagram: ${nodes.map((n) => wordsOf(n, technical)).join('; ')}. It should end: ${end.words}.`,
  };
}
