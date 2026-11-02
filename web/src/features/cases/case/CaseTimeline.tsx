import { Card, Group, Stack, Text, Timeline, Title } from '@mantine/core';
import { IconPlayerPlay } from '@tabler/icons-react';
import { useParams } from 'react-router';
import type { CaseEvent } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { stateColour } from '@/components/StateBadge';
import { StatusBadge } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Timestamp } from '@/components/Timestamp';
import { humanize, plural } from '@/lib/format';
import { eventRounds } from './derive';
import { auditText, planRationales } from './timeline';

/** Events other than a state change: neutral records and notes, information for a release or a write, red for an error. */
const KIND_COLOURS: Record<string, string> = {
  artifact: 'gray',
  note: 'gray',
  error: 'red',
  approval: 'blue',
  execution: 'blue',
};

/** An event's text: whole, or its own words and "Rationale as in the plan" with the repeated text one click away. */
function EventText({ text, rationales }: { text: string; rationales: string[] }) {
  const { lead, rationale } = auditText(text, rationales);
  if (!rationale) return <Text size="sm">{lead}</Text>;
  return (
    <Stack gap={2}>
      <Text size="sm">{`${lead ? `${lead}. ` : ''}Rationale as in the plan.`}</Text>
      <TechDetail kind="explain" label="The plan's rationale">
        <Text size="sm" maw="68ch">
          {rationale}
        </Text>
      </TechDetail>
    </Stack>
  );
}

function RoundTimeline({ events, rationales }: { events: CaseEvent[]; rationales: string[] }) {
  return (
    <Timeline bulletSize={12} lineWidth={2} active={events.length}>
      {events.map((e) => (
        <Timeline.Item
          key={e.seq}
          color={e.kind === 'state' ? stateColour(e.toState) : (KIND_COLOURS[e.kind] ?? 'gray')}
          title={
            <Group gap="xs" wrap="wrap">
              <Text size="sm" fw={600}>
                {e.kind === 'state'
                  ? humanize(e.toState)
                  : humanize(e.kind === 'artifact' ? 'record' : e.kind)}
              </Text>
              {/* An event the trial's mock plays from the recording after an approval made in the trial */}
              {e.replayed ? (
                <StatusBadge
                  tone="neutral"
                  label="Replayed"
                  hint="Played from the recording in the trial: it did not happen in this browser"
                  icon={IconPlayerPlay}
                />
              ) : null}
            </Group>
          }
        >
          <Group gap={4} wrap="wrap">
            {/* The time alone today; with its date on any other day */}
            <Timestamp iso={e.at} short size="xs" c="dimmed" />
            {e.actor && e.actor !== 'system' ? (
              <Text size="xs" c="dimmed">
                {`· ${e.actor}`}
              </Text>
            ) : null}
          </Group>
          <EventText text={e.text} rationales={rationales} />
        </Timeline.Item>
      ))}
    </Timeline>
  );
}

/**
 * The case's audit trail in timestamp order, grouped by round with the current round first. Each time carries its
 * date unless it is today's; an event that only repeats a plan's rationale says so and keeps the text one click away;
 * the events the trial plays from the recording after an approval carry a "Replayed" badge. The events as the API
 * sends them close the card.
 */
export function CaseTimeline({ events, caseId }: { events: CaseEvent[]; caseId?: string }) {
  const params = useParams();
  const id = caseId ?? params.caseId;
  const rounds = eventRounds(events);
  const rationales = planRationales(events);
  return (
    <Card padding="md" component="section" aria-labelledby="timeline-title">
      <Title order={2} id="timeline-title" mb="sm">
        Timeline
      </Title>
      {events.length === 0 ? (
        <Text size="sm" c="dimmed">
          No events yet.
        </Text>
      ) : rounds.length === 1 ? (
        <RoundTimeline events={events} rationales={rationales} />
      ) : (
        <Stack gap="lg">
          <Text size="md" c="dimmed" maw="68ch">
            {`${plural(rounds.length, 'round')}: the receiver or the evidence changed, so the case was planned again. The current round comes first.`}
          </Text>
          {rounds
            .map((r, i) => ({ r, n: i + 1 }))
            .reverse()
            .map(({ r, n }) => (
              <Stack key={n} gap="xs" component="section" aria-labelledby={`round-${n}-title`}>
                <Title order={3} id={`round-${n}-title`}>
                  {n === rounds.length ? `Round ${n}, current` : `Round ${n}`}
                </Title>
                <RoundTimeline events={r} rationales={rationales} />
              </Stack>
            ))}
        </Stack>
      )}
      {id && events.length ? (
        <Stack mt="md">
          <ApiSource endpoint={`GET /api/shutter/cases/${id}/events`} data={events} />
        </Stack>
      ) : null}
    </Card>
  );
}
