import type { AgentRun, ToolCall } from '@/api/types';

/**
 * Run rows for the tests of the board's run timeline: a row as the API sends it, a tool call, and a live pass with the
 * run's own clock (CONTRACTS 9, v1.35).
 */

/** A run row as the API sends it, with only what a test sets. */
export function run(over: Partial<AgentRun>): AgentRun {
  return {
    id: over.memberCode ?? 'conformance',
    role: 'specialist',
    memberCode: 'conformance',
    agentClass: '',
    mode: 'live',
    model: 'claude-opus-5-5',
    status: 'ok',
    startedAt: '',
    durationMs: 0,
    promptTokens: 0,
    completionTokens: 0,
    cacheReadTokens: 0,
    cacheCreationTokens: 0,
    iterations: 3,
    toolCallCount: 0,
    ensMessageId: '1',
    result: null,
    content: '',
    error: '',
    costUsd: 0,
    member: null,
    finding: null,
    toolCalls: [],
    snapshotId: 9,
    ...over,
  };
}

export const call = (
  seq: number,
  at: string,
  durationMs: number,
  over: Partial<ToolCall> = {},
): ToolCall => ({
  seq,
  at,
  name: 'read_evidence',
  arguments: {},
  durationMs,
  ok: true,
  resultPreview: '',
  ...over,
});

/**
 * A live pass on build 154, its times those of the S8 recording of 25 October with the milliseconds a v1.35 row
 * carries: the three specialists from 13:28:51, the coordinator once the last of them answered.
 */
export function livePass(): AgentRun[] {
  return [
    run({
      id: 53,
      memberCode: 'conformance',
      startedAt: '2026-10-25T13:28:51Z',
      startedAtMs: '2026-10-25T13:28:51.100Z',
      durationMs: 14_735,
      toolCallCount: 3,
      toolCalls: [
        call(1, '2026-10-25T13:28:55.292Z', 1),
        call(2, '2026-10-25T13:28:55.301Z', 4),
        call(3, '2026-10-25T13:29:03.437Z', 0, { name: 'SubmitFindings' }),
      ],
      llmMs: 11_200,
      toolMs: 800,
      reasoningTokens: 1_240,
    }),
    run({
      id: 54,
      memberCode: 'encounter',
      startedAt: '2026-10-25T13:28:51Z',
      startedAtMs: '2026-10-25T13:28:51.102Z',
      durationMs: 11_644,
      toolCallCount: 2,
      toolCalls: [
        call(1, '2026-10-25T13:28:55.087Z', 3),
        call(2, '2026-10-25T13:28:56.000Z', 0, {
          name: 'read_evidence',
          ok: false,
          denied: true,
          error: 'another case',
        }),
      ],
    }),
    run({
      id: 55,
      memberCode: 'impact',
      startedAt: '2026-10-25T13:28:51Z',
      startedAtMs: '2026-10-25T13:28:51.105Z',
      durationMs: 15_976,
      toolCallCount: 1,
      toolCalls: [call(1, '2026-10-25T13:28:56.458Z', 1)],
    }),
    run({
      id: 56,
      role: 'coordinator',
      memberCode: 'coordinator',
      startedAt: '2026-10-25T13:29:07Z',
      startedAtMs: '2026-10-25T13:29:07.090Z',
      durationMs: 14_921,
      toolCallCount: 1,
      toolCalls: [call(1, '2026-10-25T13:29:19.122Z', 0, { name: 'SubmitPlan' })],
    }),
  ];
}

/**
 * A recorded pass with the live pass's clock, member by member: the recording's findings, members and messages, with
 * the times a v1.35 row of a live run carries. For the tests that need a board the page draws a timeline for.
 */
export function withLiveClock(runs: AgentRun[]): AgentRun[] {
  const clock = new Map(livePass().map((r) => [r.memberCode, r]));
  return runs.map((r) => {
    const live = clock.get(r.memberCode);
    if (!live) return r;
    const { startedAt, startedAtMs, durationMs, toolCalls, toolCallCount, llmMs, toolMs, reasoningTokens } =
      live;
    return {
      ...r,
      mode: 'live',
      startedAt,
      startedAtMs,
      durationMs,
      toolCalls,
      toolCallCount,
      llmMs,
      toolMs,
      reasoningTokens,
    };
  });
}
