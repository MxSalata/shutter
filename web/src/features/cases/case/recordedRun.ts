import type { AgentRun } from '@/api/types';
import { asArray, asObject, pretty } from '@/lib/json';

/** A scenario's recorded run, as `fixtures/records` keeps it. */
export interface RunRecord {
  memberCode: string;
  correlationKey: string;
  model: string;
  recordedAt: string;
  response: {
    prompt_tokens: number;
    completion_tokens: number;
    result?: unknown;
  };
  /** The AI Hub transcript, as JSON text. */
  transcript: unknown;
}

interface Message {
  role: string;
  content?: string | null;
  tool_call_id?: string;
  tool_calls?: { id: string; name: string; arguments: unknown }[] | null;
}

/** One model call: what it wrote beside its tool calls, if anything, and each call with its result, as recorded. */
export interface ModelTurn {
  text: string;
  calls: { name: string; args: string; result: string }[];
}

/** What a recording holds, in the order the panel tells it. Nothing here is written by the app. */
export interface RunStory {
  /** The day it was recorded, in UTC, as the record's stamp says it. */
  recordedOn: string;
  recordedCase: string;
  model: string;
  tokensIn: number;
  tokensOut: number;
  instructions: string;
  /** The request's words before its evidence block. */
  question: string;
  /** The evidence block as sent, indented. */
  evidence: string;
  /** The encounter and patient as the model received them. */
  encounter: string;
  patient: string;
  /** The catalogue's matches in the evidence, each with its preferred outcome. */
  matches: { id: string; title: string; preferred: string }[];
  turns: ModelTurn[];
  /** The closing message, after its last tool call. */
  lastMessage: string;
  /** A coordinator's record: each dissent it kept. */
  dissents: { member: string; said: string }[];
}

/**
 * The recordings a page can load, each its own chunk, fetched only when a panel asks for it. S21 to S25 stay out of
 * the build: the trial has no board run on them (`recordedRun.test.ts` fails if that changes).
 */
const FILES = import.meta.glob<RunRecord>(
  [
    '../../../../../fixtures/records/scenario-*.json',
    '!../../../../../fixtures/records/scenario-S2[1-5]*.json',
  ],
  { import: 'default' },
);

const fileName = (path: string) => path.slice(path.lastIndexOf('/') + 1);

/** A scenario's recordings for one member, by the file's name. */
export function candidates(scenario: string, member: string): string[] {
  return Object.keys(FILES).filter((path) => {
    const name = fileName(path);
    return name.startsWith(`scenario-${scenario}-`) && name.includes(`-${member}-`);
  });
}

/**
 * The one recording behind a run: its scenario's and member's records with the run's own token counts. No match, or
 * more than one, is no recording: the panel then says so rather than show another run's.
 */
export async function findRecording(
  scenario: string,
  run: Pick<AgentRun, 'memberCode' | 'promptTokens' | 'completionTokens'>,
): Promise<{ file: string; record: RunRecord } | null> {
  const loaded = await Promise.all(
    candidates(scenario, run.memberCode).map(async (path) => ({
      file: fileName(path),
      record: await FILES[path](),
    })),
  );
  const found = loaded.filter(
    ({ record }) =>
      record.response.prompt_tokens === Number(run.promptTokens) &&
      record.response.completion_tokens === Number(run.completionTokens),
  );
  return found.length === 1 ? found[0] : null;
}

const EVIDENCE = /<evidence-[^>]*>\s*([\s\S]*?)\s*<\/evidence-[^>]*>/;

/** A recording's transcript, read for the panel: arguments and results indented, nothing rewritten or left out. */
export function storyOf(record: RunRecord): RunStory {
  const transcript = asObject(record.transcript) ?? {};
  const messages = asArray<Message>(transcript.messages);
  const request = String(messages.find((m) => m.role === 'user')?.content ?? '');
  const block = EVIDENCE.exec(request);
  const evidence = asObject(asObject(block?.[1])?.evidence) ?? {};
  const operation = asObject(evidence.operation) ?? {};
  const results = new Map(messages.filter((m) => m.role === 'tool').map((m) => [m.tool_call_id, m.content]));
  const said = messages.filter((m) => m.role === 'assistant');
  const last = said.at(-1);
  const closing = last && !last.tool_calls?.length ? last : undefined;
  return {
    recordedOn: new Date(record.recordedAt).toLocaleDateString('en-GB', {
      day: 'numeric',
      month: 'short',
      year: 'numeric',
      timeZone: 'UTC',
    }),
    recordedCase: record.correlationKey,
    model: record.model,
    tokensIn: record.response.prompt_tokens,
    tokensOut: record.response.completion_tokens,
    instructions: String(transcript.base_system_prompt ?? ''),
    question: (block ? request.slice(0, block.index) : request).trim(),
    evidence: block ? pretty(block[1]) : '',
    encounter: String(operation.encounter_id ?? ''),
    patient: String(operation.patient_id ?? ''),
    matches: asArray<Record<string, unknown>>(asObject(evidence.catalogue)?.matches).map((m) => ({
      id: String(m.id ?? ''),
      title: String(m.title ?? ''),
      preferred: String(asObject(m.preferred)?.outcome ?? ''),
    })),
    turns: said
      .filter((m) => m !== closing)
      .map((m) => ({
        text: m.content ?? '',
        calls: (m.tool_calls ?? []).map((c) => ({
          name: c.name,
          args: pretty(c.arguments),
          result: pretty(results.get(c.id)),
        })),
      })),
    lastMessage: closing?.content ?? '',
    dissents: asArray<Record<string, unknown>>(asObject(record.response.result)?.disagreements).map((d) => ({
      member: String(d.member ?? ''),
      said: String(d.said ?? ''),
    })),
  };
}
