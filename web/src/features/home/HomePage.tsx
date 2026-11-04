import { Anchor, Badge, Button, Card, Group, SimpleGrid, Stack, Text, Title } from '@mantine/core';
import { IconHome2 } from '@tabler/icons-react';
import type { CSSProperties } from 'react';
import { Link } from 'react-router';
import { scenariosHidden } from '@/api/can';
import { useCan, useHealth } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { Term } from '@/components/Term';
import { TRIAL, trialHref } from '@/env/mode';
import { hueVar } from '@/lib/hues';
import { SECTIONS, useNeedAPerson, type SectionItem } from '@/features/shell/sections';

/**
 * Where the app opens: what Shutter does, where to start, what needs a person now, and what each section is for. It only
 * points: every fact here is a section's own, and the sections come from the list the navigation is drawn from. The lead is
 * Scenarios' sentence, because its fold starts closed and this is the first thing anyone reads.
 */
export default function HomePage() {
  return (
    <Stack gap="lg">
      <PageHeader
        title="Home"
        icon={IconHome2}
        hue="cyan"
        lead={
          <>
            When an <Term term="hl7-transfer">HL7 transfer</Term> fails, Shutter works out what is true and
            fixes it only when it is safe.
          </>
        }
      />
      <FirstStep />
      {SECTIONS.map(({ group, about, items }) => (
        <Stack key={group} gap="xs" component="section" aria-labelledby={`home-${group}`}>
          <Group gap="xs" align="baseline" wrap="wrap">
            <Title order={2} id={`home-${group}`}>
              {group}
            </Title>
            <Text c="dimmed" size="sm">
              {about}
            </Text>
          </Group>
          {/* Three across only when they fill the row, so four sections make two rows of two and none stands alone */}
          <SimpleGrid cols={{ base: 1, sm: 2, lg: items.length === 3 ? 3 : 2 }} spacing="sm">
            {items.map((item) => (
              <SectionCard key={item.to} item={item} />
            ))}
          </SimpleGrid>
        </Stack>
      ))}
    </Stack>
  );
}

/**
 * The way in for someone new. The public demo's role cannot run scenarios, since its hospital plays them by itself, so it
 * starts from the cases already there; everyone else starts from S8, the case the agents are there for.
 */
function FirstStep() {
  const can = useCan();
  const hidden = scenariosHidden(can);
  return (
    <Card padding="md" component="section" aria-labelledby="home-first-step" data-tour="home-first-step">
      <Stack gap="xs" align="flex-start">
        <Title order={2} id="home-first-step">
          New here?
        </Title>
        <Text maw="68ch">
          {hidden
            ? "This hospital's failures are already in Cases. Open one to see the evidence, the plan and who decided."
            : 'Scenarios replay known failures, so you can follow one from the failed message to the verified fix. Start with S8, where a plain resend would move a patient back to the wrong ward.'}
        </Text>
        <Group gap="xs">
          <Button component={Link} to={hidden ? '/cases' : '/scenarios'} mih={44}>
            {hidden ? 'Open the cases' : 'Open the scenarios'}
          </Button>
          {TRIAL ? (
            <Anchor href={trialHref('#/scenarios', { tour: true })} size="sm">
              Take the guided tour
            </Anchor>
          ) : null}
        </Group>
      </Stack>
    </Card>
  );
}

/** One section: a link to it, what it is for, and for two of them the one fact worth knowing before opening it. */
function SectionCard({ item }: { item: SectionItem }) {
  const I = item.icon;
  return (
    <Card
      component={Link}
      to={item.to}
      padding="md"
      className="home-card"
      style={{ '--mark-hue': hueVar(item.hue) } as CSSProperties}
    >
      <Group gap="sm" wrap="nowrap" align="flex-start">
        <span className="identity-mark page-icon home-card-mark" aria-hidden>
          <I size={20} stroke={1.8} />
        </span>
        <Stack gap={4} style={{ minWidth: 0 }}>
          <Group gap="xs" wrap="wrap">
            <Title order={3} size="h4">
              {item.label}
            </Title>
            {item.to === '/cases' ? <NeedAPerson /> : null}
            {item.to === '/health' ? <ProductionState /> : null}
          </Group>
          <Text size="sm">{item.about}</Text>
        </Stack>
      </Group>
    </Card>
  );
}

/** Nothing at 0 or while it loads, as the navigation's own count. */
function NeedAPerson() {
  const n = useNeedAPerson();
  if (!n) return null;
  return (
    <Badge size="sm" color="yellow" variant="light">
      {n} {n === 1 ? 'needs' : 'need'} a person
    </Badge>
  );
}

/** Whether the production runs, once the instance has said. The Health page has the rest. */
function ProductionState() {
  const state = useHealth().data?.production_state;
  if (typeof state !== 'string') return null;
  const running = state === 'running';
  return (
    <Badge size="sm" color={running ? 'green' : 'yellow'} variant="light">
      {running ? 'Production running' : 'Production not running'}
    </Badge>
  );
}
