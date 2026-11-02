import { Anchor, Badge, Group, Text, VisuallyHidden } from '@mantine/core';
import { IconUser } from '@tabler/icons-react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import type { LiveStorm } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { StatusBadge } from '@/components/StatusBadge';
import { INCIDENT_STATES } from '@/features/incidents/describe';
import { humanize } from '@/lib/format';
import { usePrefersReducedMotion } from '@/lib/motion';
import { useDetail } from '@/stores/appearance';
import { patientWards, stormPatients, stormView, type StepStatus, type StormStep } from './view';
import './storm.css';

/** What each dot means, said to a screen reader before the step's words (the dots are decoration). */
const STATUS_WORDS: Record<StepStatus, string> = {
  done: 'Passed',
  current: 'Now',
  pending: 'Not yet',
  skipped: 'Not reached',
  // The last step's words say it: "Done: ...", "Stopped: ..."
  finished: '',
  stopped: '',
};

/** A count of the times the current step changed since the strip appeared: the dot pulses on each (none at first). */
function useStepPulse(current: number): number {
  const [pulse, setPulse] = useState(0);
  const seen = useRef(current);
  useEffect(() => {
    if (current !== seen.current) setPulse((n) => n + 1);
    seen.current = current;
  }, [current]);
  return pulse;
}

/** Step 3's words: the incident as a link, with its state beside it. */
function IncidentWords({ step, state }: { step: StormStep; state: string | null | undefined }) {
  const meaning = state ? INCIDENT_STATES[state] : undefined;
  return (
    <>
      Grouped into incident{' '}
      {/* Underlined: in the current step the words are as bold as the link, so colour alone would tell it apart */}
      <Anchor
        component={Link}
        to={`/incidents/${encodeURIComponent(step.incidentId ?? '')}`}
        fw={600}
        underline="always"
        inherit
        style={{ whiteSpace: 'nowrap' }}
      >
        {step.incidentId}
      </Anchor>
      {state ? (
        <>
          {' '}
          <StatusBadge size="xs" {...(meaning ?? { tone: 'neutral', label: humanize(state) })} />
        </>
      ) : null}
    </>
  );
}

/**
 * "Break the feed"'s progress strip (DESIGN.md, after-restyle B7): the storm's five steps, each a dot and its words,
 * the current one marked (`aria-current="step"`) and named in the step line above them, the only part a screen reader
 * hears as it changes (`aria-live="polite"`); then the storm's four patients as tokens with their wards, never their
 * names. The current dot pulses three times when the step changes, never under reduced motion.
 */
export function StormStrip({
  storm,
  heading,
  place = 'banner',
}: {
  storm: LiveStorm;
  /** The strip's title, on a page that gives it a section of its own. */
  heading?: ReactNode;
  /** Under the banner's line (a rule above it), or in a page's own card. */
  place?: 'banner' | 'page';
}) {
  const view = stormView(storm);
  const technical = useDetail() === 'technical';
  const reduced = usePrefersReducedMotion();
  const pulse = useStepPulse(view.current);
  const patients = stormPatients(storm);
  return (
    <div className="storm-strip" data-testid="storm-strip" data-state={storm.state} data-place={place}>
      {heading ? (
        <Group gap="xs" wrap="wrap" align="center" mb={6}>
          {heading}
          {technical ? <CodeChip>{storm.stormId}</CodeChip> : null}
        </Group>
      ) : null}
      <Group gap="xs" wrap="wrap" align="center">
        <StatusBadge tone={view.status.tone} label={view.status.label} />
        <Text size="sm" fw={600} aria-live="polite" data-testid="storm-line">
          {view.line}
        </Text>
        {!heading && technical ? <CodeChip>{storm.stormId}</CodeChip> : null}
      </Group>
      <ol className="storm-steps" aria-label="The storm's steps">
        {view.steps.map((step, i) => {
          const now = i === view.current;
          const hidden =
            step.status === 'skipped' && step.key === 'incident' && storm.state !== 'failed'
              ? ''
              : STATUS_WORDS[step.status];
          return (
            <li
              key={step.key}
              className="storm-step"
              data-status={step.status}
              aria-current={now ? 'step' : undefined}
            >
              <span
                className="storm-dot"
                aria-hidden
                key={now ? `now-${pulse}` : 'dot'}
                data-pulse={now && pulse > 0 && !reduced ? true : undefined}
              />
              <Text size="sm" component="span" className="storm-words">
                {hidden ? <VisuallyHidden>{hidden}: </VisuallyHidden> : null}
                {step.key === 'incident' && step.incidentId ? (
                  <IncidentWords step={step} state={storm.incidentState} />
                ) : (
                  step.words
                )}
                {step.detail ? (
                  <Text size="xs" component="span" className="storm-detail">
                    {step.detail}
                  </Text>
                ) : null}
              </Text>
            </li>
          );
        })}
      </ol>
      {patients.length ? (
        <ul className="storm-patients" aria-label="The storm's patients">
          {patients.map((p, i) => (
            <li key={p.encounterId || `${p.mrn}-${i}`}>
              <Badge
                variant="outline"
                color="gray"
                size="md"
                className="storm-patient"
                leftSection={<IconUser size={12} aria-hidden />}
              >
                {patientWards(p)}
              </Badge>
              {technical && p.encounterId ? <CodeChip>{p.encounterId}</CodeChip> : null}
            </li>
          ))}
        </ul>
      ) : null}
    </div>
  );
}
