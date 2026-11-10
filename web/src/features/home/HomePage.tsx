import {
  Anchor,
  Badge,
  Button,
  Card,
  Group,
  SimpleGrid,
  Stack,
  Text,
  Title,
  VisuallyHidden,
} from '@mantine/core';
import { IconExternalLink, IconHome2 } from '@tabler/icons-react';
import type { CSSProperties } from 'react';
import { Link } from 'react-router';
import { scenariosHidden } from '@/api/can';
import { useCan, useCasesOnce, useHealth } from '@/api/hooks';
import { PageHeader } from '@/components/PageHeader';
import { Term } from '@/components/Term';
import { TRIAL, trialHref } from '@/env/mode';
import { PORTAL_SIGN_IN } from '@/lib/hospital';
import { hueVar } from '@/lib/hues';
import {
  PORTAL_PAGE,
  useNeedAPerson,
  usePortalPage,
  useSections,
  type SectionItem,
} from '@/features/shell/sections';

/**
 * Where the app opens: what Shutter does, where to start, what needs a person now, and what each section is for. It only
 * points: every fact here is a section's own, and the sections come from the list the navigation is drawn from. The lead is
 * Scenarios' sentence, because its fold starts closed and this is the first thing anyone reads; it is one short line
 * from a laptop up, so it takes the page's width and not the measure a long lead needs.
 */
export default function HomePage() {
  const hidden = scenariosHidden(useCan());
  // The same list as the navigation's, so the engineer's group appears in both under Technical, or in neither
  const sections = useSections();
  return (
    <Stack gap="lg">
      <PageHeader
        title="Home"
        icon={IconHome2}
        hue="cyan"
        leadMaw="none"
        lead={
          <>
            Shutter resends a failed <Term term="hl7">HL7 delivery</Term> only when its checks pass. Otherwise
            it stops and names the patient.
          </>
        }
      />
      <FirstStep />
      <PortalCard />
      {sections.map(({ group, about, aboutLookOnly, items }) => (
        <Stack key={group} gap="xs" component="section" aria-labelledby={`home-${group}`}>
          <Group gap="xs" align="baseline" wrap="wrap">
            <Title order={2} id={`home-${group}`}>
              {group}
            </Title>
            <Text c="dimmed" size="sm">
              {(hidden && aboutLookOnly) || about}
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
 * starts from the cases already there; everyone else starts from S2, which shows the whole path, and then S8, the case the agents are there for.
 */
function FirstStep() {
  const can = useCan();
  // A site install plays no scenarios for anyone (the Scenarios page says so): its way in is its own cases
  const playerOff = useHealth().data?.demo === false;
  const hidden = scenariosHidden(can) || playerOff;
  return (
    <Card padding="md" component="section" aria-labelledby="home-first-step" data-tour="home-first-step">
      <Stack gap="xs" align="flex-start">
        <Title order={2} id="home-first-step">
          New here?
        </Title>
        <Text maw="68ch">
          {playerOff
            ? 'A failed delivery your productions forward becomes a case. Open one to see the evidence, the plan and who decided.'
            : hidden
              ? "This hospital's failures are already in Cases. Open one to see the evidence, the plan and who decided."
              : "Scenarios replay known failures: AI Hub agents propose a plan, and a deterministic gate decides whether it may write. Start with S2, then S8, where a plain resend would write over the bed manager's ward with every check passed."}
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
        {hidden && !playerOff ? <CasesToOpen /> : null}
      </Stack>
    </Card>
  );
}

/**
 * For the role that can't run scenarios, the two cases that show most, each only while it exists: S8, whose agents
 * disagreed, and a plan waiting for approval, S2's by preference since it is the plainest.
 */
function CasesToOpen() {
  const can = useCan();
  const s8 = useCasesOnce({ scenario: 'S8', limit: 100 }).data?.items.find((c) => c.scenario === 'S8');
  const heldS2 = useCasesOnce({ state: 'awaiting_approval', scenario: 'S2', limit: 1 }, can.approve).data;
  const heldAny = useCasesOnce(
    { state: 'awaiting_approval', limit: 1 },
    can.approve && heldS2?.items.length === 0,
  ).data;
  const waiting = heldS2?.items[0] ?? heldAny?.items[0];
  if (!s8 && !waiting) return null;
  return (
    <Stack gap={4} data-testid="home-cases-to-open">
      {s8 ? (
        <Anchor component={Link} to={`/cases/${encodeURIComponent(s8.caseId)}`} size="sm">
          See the agents disagree: {s8.caseId}
        </Anchor>
      ) : null}
      {waiting ? (
        <Anchor component={Link} to={`/cases/${encodeURIComponent(waiting.caseId)}`} size="sm">
          Approve a fix yourself: {waiting.caseId}
        </Anchor>
      ) : null}
    </Stack>
  );
}

/** The demo's page inside IRIS, on an instance that has it, and the one place that says what the online demo asks first. */
function PortalCard() {
  const shown = usePortalPage();
  if (!shown) return null;
  const I = PORTAL_PAGE.icon;
  return (
    <Card
      component="a"
      href={PORTAL_PAGE.href}
      target="_blank"
      rel="noreferrer"
      padding="md"
      className="home-card"
      data-testid="home-portal-card"
      style={{ '--mark-hue': hueVar(PORTAL_PAGE.hue) } as CSSProperties}
    >
      <Group gap="sm" wrap="nowrap" align="flex-start">
        <span className="identity-mark page-icon home-card-mark" aria-hidden>
          <I size={20} stroke={1.8} />
        </span>
        <Stack gap={4} style={{ minWidth: 0 }}>
          <Title order={2} size="h4">
            {PORTAL_PAGE.label} <IconExternalLink size={14} aria-hidden style={{ verticalAlign: 'middle' }} />
            <VisuallyHidden>(opens in a new tab)</VisuallyHidden>
          </Title>
          <Text size="sm">{PORTAL_PAGE.about}</Text>
          <Text size="sm" c="dimmed">
            Online demo: Cloudflare sign-in first ({PORTAL_SIGN_IN}).
          </Text>
        </Stack>
      </Group>
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

/** Whether the production runs, once the instance has said; the trial's is a recording's, so it says so. The Health page has the rest. */
function ProductionState() {
  const state = useHealth().data?.production_state;
  if (typeof state !== 'string') return null;
  const running = state === 'running';
  if (TRIAL)
    return (
      <Badge size="sm" color="gray" variant="light">
        {running ? 'Running when recorded' : 'Not running when recorded'}
      </Badge>
    );
  return (
    <Badge size="sm" color={running ? 'green' : 'yellow'} variant="light">
      {running ? 'Production running' : 'Production not running'}
    </Badge>
  );
}
