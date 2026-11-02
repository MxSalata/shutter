import { Group, Stack, Text, VisuallyHidden } from '@mantine/core';
import { IconCheck, IconHistory, IconX } from '@tabler/icons-react';
import { CodeChip } from '@/components/CodeChip';
import { HeroBand } from '@/components/HeroBand';
import { StatusBadge } from '@/components/StatusBadge';
import { toneText } from '@/lib/tone';
import {
  agentsBadge,
  recordedAt,
  sent,
  utcMinute,
  verdictStatement,
  type Report,
  type Verdict,
} from './report';
import type { Proof } from '@/lib/proof';

/**
 * The verdict: whether the installation is ready, in one sentence, with the core checks listed under it (a failing one
 * says what to do), the production, namespace and version as chips, when the report was read (in the trial, which
 * shows a recording), and where the agents run. The agents badge is never part of the verdict.
 */
export function HealthHero({
  report,
  verdict,
  trial,
  recordedOn,
}: {
  report: Report;
  verdict: Verdict;
  trial: boolean;
  recordedOn: Proof['recordedOn'];
}) {
  const badge = agentsBadge(report, trial, recordedOn);
  const production = sent(report.shutter_production) ? report.shutter_production : report.production;
  const read = trial ? recordedAt(report.recorded) : null;
  const facts = [
    sent(production) ? <CodeChip key="production">{String(production)}</CodeChip> : null,
    sent(report.namespace) ? <CodeChip key="namespace">{String(report.namespace)}</CodeChip> : null,
    sent(report.version) ? (
      <span key="version">
        version <CodeChip>{String(report.version)}</CodeChip>
      </span>
    ) : null,
    read ? <span key="read">read {utcMinute(read)}</span> : null,
  ].filter(Boolean);
  return (
    <HeroBand
      tone={verdict.tone}
      label={verdict.word}
      statement={verdictStatement(verdict, trial)}
      statementAs="h2"
    >
      <Stack gap="sm">
        {verdict.results.length ? (
          <ul className="health-checks" role="list" aria-label="Core checks">
            {verdict.results.map((r) => (
              <li key={r.key} data-passed={r.passed}>
                {r.passed ? (
                  <IconCheck size={16} stroke={2.2} aria-hidden style={{ color: toneText('positive') }} />
                ) : (
                  <IconX size={16} stroke={2.2} aria-hidden style={{ color: toneText('blocking') }} />
                )}
                <span>
                  {r.label}
                  <VisuallyHidden>{r.passed ? ': passes' : ': fails'}</VisuallyHidden>
                </span>
                {r.todo ? <Text size="sm">{r.todo}</Text> : null}
              </li>
            ))}
          </ul>
        ) : null}
        {verdict.notSent && verdict.results.length ? (
          <Text size="sm" c="dimmed">
            {verdict.notSent === 1
              ? 'One core check was not reported, so the count leaves it out.'
              : `${verdict.notSent} core checks were not reported, so the count leaves them out.`}
          </Text>
        ) : null}
        {facts.length ? (
          <Group gap={8} wrap="wrap" fz="sm" className="health-facts">
            {facts.map((f, i) => (
              <span key={i} className="health-fact">
                {f}
              </span>
            ))}
          </Group>
        ) : null}
        {badge ? (
          <Group>
            <StatusBadge
              tone={badge.tone}
              label={badge.label}
              hint={badge.hint}
              icon={badge.kind === 'recorded' ? IconHistory : undefined}
              size="md"
            />
          </Group>
        ) : null}
      </Stack>
    </HeroBand>
  );
}
