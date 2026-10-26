import { Badge, Button, Card, Code, List, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import { IconAdjustments } from '@tabler/icons-react';
import { Link } from 'react-router';
import { useWhatIf } from '@/api/hooks';
import type { WhatIf, WhatIfFact } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { humanize } from '@/lib/format';
import { disposition as dispositionStatus } from '@/lib/status';
import { fieldLabel, suggestionHref, valueLabel } from '@/features/site-profile/suggestion';

export const WHATIF_ID = 'ask-whatif';

/** A disposition in words, lower case inside a sentence. */
const dispositionWords = (d: string | undefined) => (d ? dispositionStatus(d).label.toLowerCase() : '');

/** The catalogue's outcomes in words; another code is shown humanized. */
const OUTCOME_WORDS: Record<string, string> = {
  none: 'nothing to send',
  escalate: 'escalate to a person',
  resend: 'resend',
  reconcile: 'reconcile',
  correct_history: 'correct the history',
};
const outcomeWords = (o: string) => OUTCOME_WORDS[o] ?? humanize(o).toLowerCase();

/** Today: the entry the case matched and what it gave, from the facts, never from an answer's text. */
function todayText(w: WhatIf): string {
  if (!w.entry) return 'The case matched no catalogue entry.';
  const disposition = dispositionWords(w.disposition);
  return `The case matched catalogue entry ${w.entry}, whose outcome here is ${outcomeWords(w.outcome)}${disposition ? `; the plan proposed ${disposition}` : ''}.`;
}

/**
 * Today for one fact: a catalogue alternative's fact turns on the entry the case matched, so it says what that entry gave;
 * a policy fact (a tier's approval policy, a receiver's cancels or merges) states the setting's value now instead.
 */
function factToday(w: WhatIf, f: WhatIfFact, setting: string, from: string): string {
  return f.kind === 'policy' ? `${setting} is ${from}.` : todayText(w);
}

/** Under the other value: the alternative the catalogue gives, and what the case would have done. */
function alternativeText(w: WhatIf, f: WhatIfFact): string {
  const a = f.kind === 'policy' ? undefined : f.alternative;
  if (!a) return f.would;
  const disposition = dispositionWords(a.disposition);
  return `Entry ${w.entry}'s alternative applies: ${outcomeWords(a.outcome)}${disposition ? `, proposed as ${disposition}` : ''}. ${f.would}`;
}

function Fact({
  caseId,
  w,
  f,
  named,
}: {
  caseId: string;
  w: WhatIf;
  f: WhatIfFact;
  /** The board's answer names this fact as its suggested change. */
  named: boolean;
}) {
  const setting = fieldLabel(f.field, f.receiver);
  const c = f.suggested_change;
  const now = valueLabel(f.field, f.current);
  const from = valueLabel(c.field, c.from);
  const to = valueLabel(c.field, c.to);
  const titleId = `${WHATIF_ID}-${f.id}`;
  return (
    <Stack gap="sm" component="section" aria-labelledby={titleId}>
      <Stack gap={2}>
        <Title order={4} fz="sm" id={titleId}>
          {f.id}: {setting}
        </Title>
        <Text size="sm">
          Site profile setting <Code>{f.field}</Code>
          {f.receiver ? ` of ${f.receiver}` : ''} is now {now}.
        </Text>
      </Stack>
      <SimpleGrid cols={{ base: 1, xs: 2 }} spacing="sm">
        <Card withBorder padding="sm">
          <Text fw={600} size="sm">
            Today
          </Text>
          <Text size="sm">{factToday(w, f, setting, now)}</Text>
        </Card>
        <Card withBorder padding="sm">
          <Text fw={600} size="sm">
            If it were {to}
          </Text>
          <Text size="sm">{alternativeText(w, f)}</Text>
        </Card>
      </SimpleGrid>
      {f.alternative?.when ? (
        <Text size="xs" c="dimmed">
          The catalogue&apos;s condition for it: <Code>{f.alternative.when}</Code>
        </Text>
      ) : null}
      <Stack gap={6}>
        <Badge color="yellow" variant="light" w="fit-content" style={{ textTransform: 'none' }}>
          Your decision
        </Badge>
        <Text size="sm">
          Suggested change: set {setting.charAt(0).toLowerCase() + setting.slice(1)} from {from} to {to}.
          {named ? ' The board names this change in its answer above.' : ''}
        </Text>
        {c.why ? <Text size="sm">{c.why}</Text> : null}
        {c.affects.length ? (
          <>
            <Text size="sm">It would apply to:</Text>
            <List size="sm" spacing={2}>
              {c.affects.map((a) => (
                <List.Item key={a}>{a}</List.Item>
              ))}
            </List>
          </>
        ) : null}
      </Stack>
      {!c.valid ? (
        <StatusNotice tone="attention" title="This change would not be accepted">
          {c.problem || 'The site profile would refuse it.'} No draft is offered.
        </StatusNotice>
      ) : c.stale ? (
        <StatusNotice tone="attention" title="The profile has changed since">
          The site profile no longer holds {from} for this setting, so this change would not apply as it
          stands. Ask again to read the facts against the current profile.
        </StatusNotice>
      ) : (
        <Stack gap={6}>
          <Button
            component={Link}
            to={suggestionHref({ caseId, fact: f.id })}
            leftSection={<IconAdjustments size={16} aria-hidden />}
            w="fit-content"
            aria-describedby={`${titleId}-note`}
          >
            Open in Site profile
          </Button>
          <Text size="xs" c="dimmed" id={`${titleId}-note`}>
            Opens a pre-filled draft. An approver reviews it and saves it. Nothing changes until then, and
            earlier approvals stay tied to the version they were made under.
          </Text>
        </Stack>
      )}
    </Stack>
  );
}

/**
 * The What-if card: the site profile setting this case's outcome turns on, what the case did with today's value and
 * what it would have done under the other, and the change as a draft for the Site profile page. Every word of it comes
 * from GET /cases/{id}/whatif, computed without a model, so it reads the same with no key.
 */
export function WhatIfCard({ caseId, named }: { caseId: string; named?: string }) {
  const whatif = useWhatIf(caseId);
  if (whatif.isPending) return null;
  if (whatif.isError)
    return (
      <ErrorAlert
        error={whatif.error}
        title="The What-if facts could not be read"
        onRetry={() => void whatif.refetch()}
      />
    );
  const w = whatif.data;
  if (!w) return null;
  return (
    <Card
      padding="md"
      withBorder
      component="section"
      id={WHATIF_ID}
      aria-labelledby={`${WHATIF_ID}-title`}
      className="ask-whatif"
    >
      <Stack gap="md">
        <Stack gap={4}>
          <Title order={3} fz="md" id={`${WHATIF_ID}-title`} tabIndex={-1}>
            What if: the setting behind this outcome
          </Title>
          {w.profile_version !== undefined ? (
            <Text size="xs" c="dimmed">
              Worked out from the case&apos;s evidence and site profile version {w.profile_version}, without a
              model.
            </Text>
          ) : null}
        </Stack>
        {w.facts.length ? (
          w.facts.map((f) => <Fact key={f.id} caseId={caseId} w={w} f={f} named={named === f.id} />)
        ) : (
          <Stack gap={6}>
            <StatusBadge tone="neutral" label="No setting changes this outcome" w="fit-content" />
            <Text size="sm">
              {todayText(w)}{' '}
              {w.entry
                ? `Catalogue entry ${w.entry} has no alternative that a site profile setting selects, so the outcome does not turn on the profile.`
                : 'So the outcome does not turn on the profile.'}
            </Text>
          </Stack>
        )}
      </Stack>
    </Card>
  );
}
