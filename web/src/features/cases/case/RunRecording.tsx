import { Anchor, Code, Stack, Text, Title } from '@mantine/core';
import { IconExternalLink } from '@tabler/icons-react';
import { useQuery } from '@tanstack/react-query';
import { useId } from 'react';
import { useCase, useRuns } from '@/api/hooks';
import type { AgentRun } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { TechDetail } from '@/components/TechDetail';
import { formatInt, humanize, plural } from '@/lib/format';
import { recordingUrl } from './recordingLinks';
import { RecordingUnavailable } from './RecordingUnavailable';
import { investigationRuns } from './runClock';
import { findRecording, storyOf, type RunStory } from './recordedRun';

/** The recording behind a run, read once: a recording never changes while the page is open. */
function useRecording(scenario: string | undefined, run: AgentRun | undefined) {
  return useQuery({
    queryKey: ['recording', scenario, run?.memberCode, run?.promptTokens, run?.completionTokens],
    enabled: !!scenario && !!run,
    staleTime: Infinity,
    retry: false,
    queryFn: () => findRecording(scenario!, run!),
  });
}

/** Text as recorded: its own line breaks kept, long keys wrapped inside the card, no scrolling of its own. */
function Recorded({ text }: { text: string }) {
  return (
    <Code block fz="xs" className="mono-wrap" style={{ whiteSpace: 'pre-wrap' }}>
      {text}
    </Code>
  );
}

function Label({ children }: { children: string }) {
  return (
    <Text size="xs" fw={600} c="dimmed">
      {children}
    </Text>
  );
}

/** The model's turns, each with its tool calls: the arguments it wrote and the whole result it read. */
function Turns({ story }: { story: RunStory }) {
  return (
    <Stack gap="md">
      {story.turns.map((turn, t) => (
        <Stack key={t} gap="xs">
          <Text size="sm" fw={600}>{`Model turn ${t + 1}`}</Text>
          {turn.text ? <Text size="sm">{turn.text}</Text> : null}
          {turn.calls.map((call, c) => (
            <Stack key={c} gap={4} data-tool={call.name}>
              <div>
                <CodeChip>{call.name}</CodeChip>
              </div>
              <Label>Arguments</Label>
              <Recorded text={call.args} />
              <Label>Result</Label>
              <Recorded text={call.result} />
            </Stack>
          ))}
        </Stack>
      ))}
    </Stack>
  );
}

/**
 * What a board member was sent and did, from its public recording: a line that says what the recording is and what it
 * isn't, the catalogue's advice in the request, its instructions, its request and its steps one click away, and its
 * last message. Every recorded word is shown as recorded: the recording's ids are its own, since they are the proof.
 * Only trial pages load this, in its own chunk; each recording is a chunk of its own, loaded when its panel opens.
 */
export default function RunRecording({ caseId, run }: { caseId: string; run: AgentRun }) {
  const titleId = useId();
  const scenario = useCase(caseId).data?.scenario;
  const runs = investigationRuns(useRuns(caseId, true).data);
  const recording = useRecording(scenario, run);
  // Who dissented is on the coordinator's own recording
  const plan = useRecording(scenario, runs.filter((r) => r.role === 'coordinator').at(-1));
  if (recording.isPending) {
    return (
      <Text size="sm" c="dimmed">
        Reading the recording
      </Text>
    );
  }
  if (!recording.data) return <RecordingUnavailable />;
  const { file, record } = recording.data;
  const story = storyOf(record);
  const dissents = plan.data ? storyOf(plan.data.record).dissents : [];
  const nameOf = (member: string) =>
    runs.find((r) => r.memberCode === member)?.member?.name ?? humanize(member);
  const calls = story.turns.flatMap((t) => t.calls).length;
  return (
    <section aria-labelledby={titleId} data-testid="run-recording">
      <Stack gap="sm">
        <Title order={4} id={titleId}>
          What this agent was sent and did
        </Title>
        <Text size="sm" maw="68ch" data-testid="recording-proof">
          {`Recorded live on ${story.recordedOn} as case ${story.recordedCase} on ${story.model}; no model was called now. This trial shows it as ${caseId}. `}
          <Anchor href={recordingUrl(file)} target="_blank" rel="noreferrer" underline="always" inherit>
            Its public file in fixtures/records
            <IconExternalLink size={12} aria-hidden style={{ verticalAlign: 'middle', marginLeft: 2 }} />
          </Anchor>
        </Text>
        <Text size="sm" maw="68ch" data-testid="recording-limits">
          {`This is what it read and called, not its reasoning. Its ${formatInt(story.tokensIn)} tokens in and ${formatInt(story.tokensOut)} out are for the whole run, not per call. The encounter and patient appear as tokens (${story.encounter}, ${story.patient}), as the model received them.`}
        </Text>
        {story.matches.length ? (
          <Stack gap={4} maw="68ch" data-testid="recording-catalogue">
            <Text size="sm">
              The request includes the catalogue&apos;s match and its preferred outcome, as advice:{' '}
              {story.matches.map((m, i) => (
                <span key={m.id}>
                  {i ? '; ' : ''}
                  <CodeChip>{m.id}</CodeChip> {m.title}: <CodeChip>{m.preferred}</CodeChip>
                </span>
              ))}
              .
            </Text>
            {dissents.map((d) => (
              <Text size="sm" key={d.member}>
                {`The coordinator kept ${nameOf(d.member)}'s dissent: ${d.said}`}
              </Text>
            ))}
          </Stack>
        ) : null}
        <TechDetail kind="explain" label="Its instructions">
          <Recorded text={story.instructions} />
        </TechDetail>
        <TechDetail kind="explain" label="Its request">
          <Stack gap="xs">
            <Text size="sm" maw="68ch">
              {story.question}
            </Text>
            <Label>The evidence, as sent</Label>
            <Recorded text={story.evidence} />
          </Stack>
        </TechDetail>
        <TechDetail kind="explain" label={`What it did: ${plural(calls, 'tool call')}`}>
          <Turns story={story} />
        </TechDetail>
        {story.lastMessage ? (
          <Stack gap={2} maw="68ch">
            <Label>Its last message</Label>
            <Text
              size="sm"
              pl="xs"
              style={{ borderLeft: '3px solid var(--mantine-color-default-border)' }}
              data-testid="recording-last-message"
            >
              {story.lastMessage}
            </Text>
          </Stack>
        ) : null}
      </Stack>
    </section>
  );
}
