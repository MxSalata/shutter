import { Anchor, Button, Group, List, Stack, Text, Title } from '@mantine/core';
import { useQuery } from '@tanstack/react-query';
import { IconArrowLeft, IconPrinter } from '@tabler/icons-react';
import { useEffect, useState, type ReactNode } from 'react';
import { Link } from 'react-router';
import { api } from '@/api/client';
import { useHealth, useScenarios, useSiteEntries, useSiteProfile } from '@/api/hooks';
import type { SiteEntryItem, SiteProfile, SiteProfileView, SiteReceiver } from '@/api/types';
import { CodeChip } from '@/components/CodeChip';
import { DetailSwitch } from '@/components/DetailSwitch';
import { ErrorAlert } from '@/components/ErrorAlert';
import { PageSkeleton } from '@/components/PageSkeleton';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { TRIAL } from '@/env/mode';
import { CATEGORY_TEXT, categoryOf, historyPolicyOf } from '@/lib/categories';
import { isApiError } from '@/lib/errors';
import { humanize } from '@/lib/format';
import { CHECK_QUESTIONS, CHECK_STAGE_DEFAULT, CHECK_STAGES, UNKNOWN_BLOCKS } from '@/lib/gateChecks';
import { useTechnical } from '@/stores/appearance';
import {
  FHIR_OVERTAKEN_LINE,
  KINDS,
  KIND_LABELS,
  POLICY_SHORT,
  TIER_LABELS,
  closeNeedsApprover,
  incidentRule,
  isDemoPolicy,
  isShipped,
  overtakenLine,
} from '@/features/site-profile/profile';
import { capabilities, fhirOf } from '@/features/site-profile/receiverCapabilities';
import {
  OUT_OF_DATE,
  alternativesOf,
  decidesWords,
  entryAtReceivers,
  hasNoRecoveryApi,
  limitsFor,
  modelledReceiver,
  andWords,
  byNumber,
  patternWords,
  releaseAt,
  stampLine,
  stampOf,
  stampTime,
  type CatalogueEntry,
  type CatalogueView,
  type Stamp,
} from './model';
import './site-guide.css';

/**
 * This site's guide (the third guide, beside "How Shutter works" and "Integrating at your trust"): the site profile in
 * force, the gate's checks and the catalogue, as the install answers them at the moment the page opens, in a page the
 * browser prints to PDF. It reads; it writes and stores nothing. Each part is a sheet whose foot carries the stamp on
 * every printed page.
 */

const PARTS = [
  ['site-guide-receivers', 'Your receivers'],
  ['site-guide-settings', 'Site-wide settings'],
  ['site-guide-gate', 'The gate'],
  ['site-guide-scenarios', 'Every scenario and what Shutter does with it here'],
  ['site-guide-limits', 'Limits'],
] as const;

const useCatalogue = () =>
  useQuery({ queryKey: ['catalogue'], queryFn: () => api.get<CatalogueView>('/catalogue') });

const and = andWords;

/** A part of the guide: on paper a page of its own, with the stamp at the foot of each page it runs to. */
function Sheet({
  id,
  title,
  stamp,
  children,
}: {
  id: string;
  title?: string;
  stamp: Stamp;
  children: ReactNode;
}) {
  return (
    <table className="site-guide-sheet" role="presentation" data-part={id}>
      <tfoot>
        <tr>
          <td>
            <div className="site-guide-foot" data-testid="site-guide-foot">
              {stampLine(stamp)}
            </div>
          </td>
        </tr>
      </tfoot>
      <tbody>
        <tr>
          <td>
            <Stack gap="md" component="section" id={id} aria-labelledby={title ? `${id}-title` : undefined}>
              {title ? (
                <Title order={2} id={`${id}-title`} tabIndex={-1}>
                  {title}
                </Title>
              ) : null}
              {children}
            </Stack>
          </td>
        </tr>
      </tbody>
    </table>
  );
}

/** A Technical name beside the plain words. */
function Code({ children }: { children: ReactNode }) {
  return useTechnical() ? <CodeChip>{children}</CodeChip> : null;
}

function Cover({ stamp, view }: { stamp: Stamp; view: SiteProfileView }) {
  const rows: [string, string][] = [
    ['Site profile', `Version ${stamp.profileVersion}, ${stamp.saved}`],
    ['Catalogue', stamp.catalogueVersion || 'not read'],
    ['Gate policy', stamp.gatePolicy || 'not read'],
    ['Release', stamp.release || 'not read'],
    ['Exported', stamp.exportedAt],
  ];
  return (
    <Stack gap="md">
      <Stack gap={4}>
        <Text className="overline" m={0}>
          {stamp.trial ? 'Trial (sample data)' : 'Shutter'}
        </Text>
        <Title order={1} id="site-guide-title">
          This site&apos;s guide
        </Title>
        <Text size="lg" className="site-guide-prose">
          What Shutter does at this site, case by case, from the answers in force when this guide was made.
        </Text>
      </Stack>
      {stamp.trial ? (
        <StatusNotice tone="info" title="Sample data">
          <Text size="md">
            The trial&apos;s recorded demo hospital: made-up receivers and answers, not a trust&apos;s.
          </Text>
        </StatusNotice>
      ) : null}
      <div className="site-guide-block" data-testid="site-guide-stamp">
        <dl style={{ margin: 0 }}>
          {rows.map(([k, v]) => (
            <div
              key={k}
              style={{ display: 'flex', gap: 'var(--mantine-spacing-sm)', alignItems: 'baseline' }}
            >
              <Text component="dt" size="sm" fw={600} w={110} style={{ flexShrink: 0 }}>
                {k}
              </Text>
              <Text component="dd" size="sm" m={0} className="site-guide-stamp-value">
                {v}
              </Text>
            </div>
          ))}
        </dl>
        <Text size="sm" mt="xs">
          {OUT_OF_DATE}
        </Text>
      </div>
      <Stack gap={4}>
        <Text fw={600}>In this guide</Text>
        <List size="md" type="ordered">
          {PARTS.map(([id, title]) => (
            <List.Item key={id}>
              <Anchor href={`#${id}`} onClick={(e) => jump(e, id)}>
                {title}
              </Anchor>
            </List.Item>
          ))}
        </List>
      </Stack>
      <Text size="sm" c="dimmed" className="site-guide-prose">
        {view.source === 'api'
          ? 'Configuration and words only: no case, message or patient appears here.'
          : `The ${isDemoPolicy(view.source) ? "demo's" : 'shipped'} answers are in force: nobody has saved this site's own yet. Configuration and words only: no case, message or patient appears here.`}
      </Text>
    </Stack>
  );
}

/** The page uses hash routing: an in-page link scrolls to its part instead of changing the route. */
function jump(e: React.MouseEvent, id: string) {
  e.preventDefault();
  const el = document.getElementById(id);
  el?.scrollIntoView();
  el?.querySelector<HTMLElement>('h2')?.focus();
}

function Lines({ label, items }: { label: string; items: ReactNode[] }) {
  if (!items.length) return null;
  return (
    <Stack gap={2}>
      <Text size="sm" fw={600}>
        {label}
      </Text>
      <List size="sm" spacing={2}>
        {items.map((x, i) => (
          <List.Item key={i}>{x}</List.Item>
        ))}
      </List>
    </Stack>
  );
}

/** One receiver: what it is, what Shutter may and will never do there, who approves, and what an outage does. */
function Receiver({ r, profile }: { r: SiteReceiver; profile: SiteProfile }) {
  const category = categoryOf(r);
  const text = CATEGORY_TEXT[category];
  const fhir = fhirOf(r);
  const noApi = hasNoRecoveryApi(r);
  const caps = fhir || noApi || category === 'orders_results' ? [] : capabilities(r, false);
  const takes = caps.filter((c) => c.yes);
  const cannot = caps.filter((c) => !c.yes);
  const may: ReactNode[] = [
    `${text.gist}.`,
    fhir ? FHIR_OVERTAKEN_LINE : overtakenLine(category, historyPolicyOf(r, profile)),
  ];
  const never: ReactNode[] = [];
  if (noApi) {
    may.push('A case here is investigated and goes to a person with its findings.');
    never.push('It is never resent from the case: this receiver has no recovery API that Shutter reads.');
  } else if (fhir) {
    may.push(
      fhir.recovery_enabled === true
        ? 'One ward move on an existing Encounter, after a person approves it.'
        : 'Recovery is off for it: Shutter reads it and sends nothing until the site turns recovery on.',
    );
    may.push(`Its ward map has ${Array.isArray(fhir.location_map) ? fhir.location_map.length : 0} wards.`);
    never.push('Only a person releases its update, whatever the tier.');
  } else if (category !== 'orders_results') {
    may.push(`It takes ${takes.length ? and(takes.map((c) => c.short)) : 'nothing declared'}.`);
    may.push(
      <>
        A write is released by{' '}
        {KINDS.map(
          (k) =>
            `${POLICY_SHORT[releaseAt(profile, r, k)] ?? releaseAt(profile, r, k)} for ${KIND_LABELS[k]}`,
        ).join('; ')}
        . <Code>{`policy.${r.tier}`}</Code>
      </>,
    );
    never.push(
      "It never sends anything but the case's own operation, unchanged, after the gate and a dry run.",
    );
    for (const c of cannot) never.push(<>It cannot take {c.long}.</>);
  }
  if (!fhir && r.cancels !== true && category !== 'orders_results')
    never.push(
      'Shutter never sends it a cancel: the case goes to a person, who corrects the receiver by hand.',
    );
  if (!fhir && category !== 'orders_results' && !(r.merges === true && profile.merges === 'allowed'))
    never.push('Shutter never sends it a merge: a merge goes to a person.');
  const teams = (profile.teams ?? []).filter((t) => (t.receivers ?? []).includes(r.name)).map((t) => t.name);
  const own = Array.isArray(r.approvers)
    ? (r.approvers as unknown[]).filter((x) => typeof x === 'string')
    : [];
  const approves = [
    `${profile.approvers?.role || 'A person with the approver role'} approve${profile.approvers?.role ? '' : 's'} its writes${own.length ? `, named for it: ${and(own as string[])}` : ''}.`,
    `When nobody is available: ${profile.approvers?.escalation || 'not answered'}.`,
    teams.length ? `A case Shutter can't recover goes to ${and(teams)}.` : null,
  ].filter(Boolean) as string[];
  const watch = r.watch as { item?: string } | undefined;
  const outage = watch
    ? [
        `Shutter watches ${typeof watch.item === 'string' ? watch.item : 'its item'} in the engine and opens one outage while its listener is down, with the failed messages listed.`,
        r.engine_resend === true
          ? "After one approval the engine sends again the outage's messages that never arrived, settled by the receiver's declared duplicate handling."
          : 'Shutter resends nothing for an outage here: the engine retries as configured.',
      ]
    : [`Shutter does not watch it for outages. ${incidentRule(profile)}`];
  return (
    <div className="site-guide-block" data-testid={`site-guide-receiver-${r.name}`}>
      <Stack gap="sm">
        <Stack gap={0}>
          <Title order={3}>{r.name || 'An unnamed receiver'}</Title>
          <Text size="sm" c="dimmed">
            {r.system || 'What it does is not answered'}
          </Text>
        </Stack>
        <Text size="sm">
          {text.label}
          {fhir ? ', a FHIR R4 server' : ''}, tier {TIER_LABELS[String(r.tier)] ?? r.tier}.{' '}
          <Code>{category}</Code> <Code>{`tier ${r.tier}`}</Code>
        </Text>
        <Lines label="What Shutter may do here" items={may} />
        <Lines label="What it will never do here" items={never} />
        <Lines label="Who approves" items={approves} />
        <Lines label="In an outage" items={outage} />
      </Stack>
    </div>
  );
}

function Settings({ profile }: { profile: SiteProfile }) {
  const enabled = profile.recovery?.mode === 'enabled';
  const takeMerges = profile.receivers.filter((r) => r.merges === true).map((r) => r.name);
  const teams = profile.teams ?? [];
  const reminders = (profile as unknown as { reminders?: { enabled?: boolean } }).reminders;
  const rows: [string, ReactNode, string][] = [
    [
      'Recovery',
      enabled
        ? 'Enabled: within the gate and the policy, Shutter may rehearse and write to a receiver with a recovery API.'
        : 'Shadow mode: Shutter investigates and records what it would propose, and sends no rehearsal, recovery write, resend preview or outage resend.',
      'recovery.mode',
    ],
    [
      'The stop switch',
      'An emergency stop is apart from this: Stop Shutter recovery, in Settings, latches at once and outlives a restart. While it is on, nothing is written.',
      'recovery-control',
    ],
    [
      'Merges',
      profile.merges === 'allowed'
        ? `A merge may go, gated and verified, only to a receiver whose entry takes merges: ${takeMerges.length ? and(takeMerges) : 'none here'}.`
        : 'Shutter never sends a merge (A40): every merge is withheld and goes to a person.',
      'merges',
    ],
    [
      'What reaches a model',
      `The model always gets tokens for the patient's identifiers, never the name, date of birth or address. ${
        profile.model_content?.free_text === true
          ? 'Note text (OBX and NTE) goes too, with those replaced by tokens, up to 500 characters.'
          : 'Note text never goes: the model learns only that a note is present.'
      }`,
      'model_content.free_text',
    ],
    [
      'Notifications',
      [
        teams.length
          ? `Escalations go to ${and(teams.map((t) => t.name))}.`
          : 'No team is named for escalations.',
        enabled || profile.notifications?.shadow_delivery === 'enabled'
          ? 'Escalation emails are sent.'
          : 'In shadow mode no escalation email is sent.',
        reminders?.enabled === true
          ? 'A scheduled reminder mail goes when a case that needs a person stays open.'
          : 'No reminder mail is set for cases left open.',
      ].join(' '),
      'teams, notifications, reminders',
    ],
    [
      'Closing by hand',
      `A case the team corrected by hand is marked handled by ${closeNeedsApprover(profile) ? 'an approver only' : 'an operator or an approver'}.`,
      'approvers.close_needs_approver',
    ],
    ['Incidents', incidentRule(profile), 'incident'],
    [
      'Unconditional resends',
      profile.unconditional_resend === 'allowed'
        ? 'Allowed, never automatically: a person approves each.'
        : 'Never: a resend always names the receiver version it expects.',
      'unconditional_resend',
    ],
    [
      'Authoritative source',
      profile.authoritative_source
        ? `${profile.authoritative_source}: when two systems move a patient at the same time, its movement stands.`
        : 'None named: when two systems move a patient at the same time, the board or a person decides.',
      'authoritative_source',
    ],
  ];
  return (
    <Stack gap="sm">
      {rows.map(([k, v, key]) => (
        <Stack key={k} gap={2} className="site-guide-prose">
          <Text fw={600}>
            {k} <Code>{key}</Code>
          </Text>
          <Text size="md">{v}</Text>
        </Stack>
      ))}
    </Stack>
  );
}

function Gate({ policy }: { policy: string }) {
  return (
    <Stack gap="sm">
      <Text size="md" className="site-guide-prose">
        The gate is code with no model in it. It runs for every plan at the proposal, and for a write again at
        the dispatch, after the release and a fresh read of the receiver. Each check answers pass, block or
        unknown. <strong>{UNKNOWN_BLOCKS}</strong> Every decision is stored with its checks and the
        gate&apos;s policy version
        {policy ? ` (${policy})` : ''}.
      </Text>
      <table className="site-guide-checks" aria-label="The gate's twelve checks">
        <thead>
          <tr>
            <th scope="col">Check</th>
            <th scope="col">The question it answers</th>
            <th scope="col">When it decides</th>
          </tr>
        </thead>
        <tbody>
          {Object.entries(CHECK_QUESTIONS).map(([name, question]) => (
            <tr key={name}>
              <th scope="row">
                <Text size="sm" fw={600} span>
                  {humanize(name)}
                </Text>{' '}
                <Code>{name}</Code>
              </th>
              <td>
                <Text size="sm">{question}</Text>
              </td>
              <td>
                <Text size="sm">{CHECK_STAGES[name] ?? CHECK_STAGE_DEFAULT}</Text>
              </td>
            </tr>
          ))}
        </tbody>
      </table>
    </Stack>
  );
}

function Scenario({
  e,
  profile,
  titles,
  own,
}: {
  e: CatalogueEntry;
  profile: SiteProfile;
  titles: Map<string, string>;
  own?: SiteEntryItem;
}) {
  const site = e.origin === 'site';
  const at = site ? [] : entryAtReceivers(e, profile);
  const alternatives = site ? [] : alternativesOf(e);
  const shown = (e.scenarios ?? []).map((s) => (titles.get(s) ? `${s} (${titles.get(s)})` : s));
  return (
    <div className="site-guide-block" data-testid={`site-guide-entry-${e.id}`}>
      <Stack gap="xs">
        <Group gap="xs" wrap="wrap">
          <Title order={3}>{`${e.id}: ${e.title}`}</Title>
          {site ? <StatusBadge tone="info" label="This site's own" /> : null}
        </Group>
        <Text size="sm">
          {site ? `${e.sentence || patternWords(e.pattern)}.` : `${patternWords(e.pattern)}.`}
        </Text>
        <Text size="sm">
          Who decides here: {decidesWords(e.decides)}. <Code>{`decides: ${e.decides}`}</Code>
        </Text>
        {site ? (
          <>
            <Text size="sm">
              Shutter sends and closes nothing: the case goes to a person with these instructions.
            </Text>
            <Text size="sm" fw={600}>
              {e.instructions || 'No instructions written.'}
            </Text>
            {e.preferred?.why ? <Text size="sm">Why: {e.preferred.why}</Text> : null}
            <Text size="sm" c="dimmed">
              {own?.approvedBy
                ? `Version ${e.version}, approved by ${own.approvedBy}${own.approvedAt ? `, ${stampTime(own.approvedAt)}` : ''}.`
                : `Version ${e.version}; who approved it was not read.`}
              {e.team ? ` Team: ${(profile.teams ?? []).find((t) => t.id === e.team)?.name ?? e.team}.` : ''}
            </Text>
          </>
        ) : (
          <>
            {e.atReceivers ? null : (
              <Text size="sm">
                This install&apos;s answer does not say what it settles on at each receiver.
              </Text>
            )}
            {at.map((g) => (
              <Stack key={g.receivers.join()} gap={0}>
                <Text size="sm" fw={600}>
                  At {and(g.receivers)}
                </Text>
                {g.lines.map((l) => (
                  <Text key={l} size="sm">
                    {l}
                  </Text>
                ))}
              </Stack>
            ))}
            {alternatives.length ? <Lines label="Its alternatives" items={alternatives} /> : null}
            <Text size="sm" c="dimmed">
              {shown.length
                ? `Shown in the scenario${shown.length > 1 ? 's' : ''} ${and(shown)}.`
                : 'No shipped scenario shows it.'}
            </Text>
          </>
        )}
        <Code>{`pattern ${JSON.stringify(e.pattern ?? {})}`}</Code>
      </Stack>
    </div>
  );
}

function Scenarios({
  catalogue,
  profile,
  titles,
  entries,
}: {
  catalogue: CatalogueView;
  profile: SiteProfile;
  titles: Map<string, string>;
  entries: SiteEntryItem[];
}) {
  const others = profile.receivers.filter((r) => !modelledReceiver(r));
  const orders = others.filter((r) => !fhirOf(r)).map((r) => r.name);
  const fhir = others.filter((r) => fhirOf(r)).map((r) => r.name);
  return (
    <Stack gap="sm">
      <Text size="md" className="site-guide-prose">
        Each entry is a failure Shutter knows. When one alone matches a case, it settles as below at this
        site; when several match, the board decides, and a pattern no entry knows goes to a person.
        {catalogue.site.length
          ? ` This site's own entries answer first, after a death on the message: a case one matches goes to a person.`
          : ''}
      </Text>
      {profile.recovery?.mode !== 'enabled' ? (
        <Text size="md" className="site-guide-prose">
          While recovery is in shadow mode, nothing below is sent: Shutter records what it would propose.
        </Text>
      ) : null}
      {orders.length ? (
        <Text size="md" className="site-guide-prose">
          {`At ${and(orders)}, every case goes to a person with its findings, whatever the entry.`}
        </Text>
      ) : null}
      {fhir.length ? (
        <Text size="md" className="site-guide-prose">
          {`At ${and(fhir)}, the FHIR gate judges each case, and only a person releases an update.`}
        </Text>
      ) : null}
      {catalogue.siteError ? (
        <StatusNotice tone="blocking" title="An entry of this site's can't be read">
          <Text size="md">Until it is fixed, every case goes to a person. {catalogue.siteError}</Text>
        </StatusNotice>
      ) : null}
      {catalogue.site.length ? (
        <Title order={3} fz="lg">
          This site&apos;s own entries
        </Title>
      ) : null}
      {[...catalogue.site].sort(byNumber).map((e) => (
        <Scenario
          key={e.id}
          e={e}
          profile={profile}
          titles={titles}
          own={entries.find((x) => x.id === e.id)}
        />
      ))}
      <Title order={3} fz="lg">
        The shipped entries
      </Title>
      {[...catalogue.shipped].sort(byNumber).map((e) => (
        <Scenario key={e.id} e={e} profile={profile} titles={titles} />
      ))}
    </Stack>
  );
}

function Limits({ profile }: { profile: SiteProfile }) {
  return (
    <Stack gap="sm" className="site-guide-prose">
      <List size="md" spacing="xs">
        {limitsFor(profile).map((l) => (
          <List.Item key={l.title}>
            <Text span fw={600}>
              {l.title}.
            </Text>{' '}
            {l.text}
          </List.Item>
        ))}
      </List>
      <Text size="md">
        The full list, with each limit&apos;s effect, what a site can do about it and its status, is in the
        release&apos;s docs/readme/limits.md.
      </Text>
    </Stack>
  );
}

function Toolbar() {
  return (
    <Group className="site-guide-toolbar" justify="space-between" wrap="wrap" gap="sm" mb="lg">
      <Button
        component={Link}
        to="/site-profile"
        variant="subtle"
        leftSection={<IconArrowLeft size={16} aria-hidden />}
      >
        Site profile
      </Button>
      <Group gap="sm">
        <DetailSwitch />
        <Button leftSection={<IconPrinter size={16} aria-hidden />} onClick={() => window.print()}>
          Print or save as PDF
        </Button>
      </Group>
    </Group>
  );
}

export default function SiteGuidePage() {
  const profile = useSiteProfile();
  const catalogue = useCatalogue();
  const health = useHealth();
  const entries = useSiteEntries();
  const scenarios = useScenarios();
  // The moment of export: fixed when the page opens, so every page of the PDF carries the same stamp
  const [now] = useState(() => new Date());
  useEffect(() => {
    const before = document.title;
    document.title = "This site's guide · Shutter";
    return () => {
      document.title = before;
    };
  }, []);
  const failed = [profile, catalogue, health].find((q) => q.isError);
  const ready = profile.data && catalogue.data && health.data && !entries.isPending && !scenarios.isPending;
  const titles = new Map((scenarios.data?.scenarios ?? []).map((s) => [s.id, s.title]));
  return (
    <div className="site-guide">
      <Toolbar />
      <main aria-labelledby="site-guide-title">
        {failed ? (
          <>
            <Title order={1} id="site-guide-title" mb="md">
              This site&apos;s guide
            </Title>
            <ErrorAlert
              error={failed.error}
              title={
                isApiError(failed.error) && failed.error.status === 403
                  ? 'This guide needs the operator or approver role'
                  : 'What the guide is made from could not be read'
              }
              onRetry={() => void failed.refetch()}
            />
          </>
        ) : !ready ? (
          <PageSkeleton label="Reading the site profile, the gate and the catalogue…" />
        ) : (
          <Guide
            view={profile.data!}
            catalogue={catalogue.data!}
            health={health.data! as Record<string, unknown>}
            titles={titles}
            entries={entries.data?.items ?? []}
            now={now}
          />
        )}
      </main>
    </div>
  );
}

function Guide({
  view,
  catalogue,
  health,
  titles,
  entries,
  now,
}: {
  view: SiteProfileView;
  catalogue: CatalogueView;
  health: Record<string, unknown>;
  titles: Map<string, string>;
  entries: SiteEntryItem[];
  now: Date;
}) {
  const profile = view.profile;
  const stamp = stampOf({
    view,
    catalogue,
    health,
    now,
    trial: TRIAL,
    shippedWords: isShipped(view.source)
      ? isDemoPolicy(view.source)
        ? "the demo's answers"
        : 'the shipped answers'
      : '',
  });
  return (
    <>
      <Sheet id="site-guide-cover" stamp={stamp}>
        <Cover stamp={stamp} view={view} />
      </Sheet>
      <Sheet id={PARTS[0][0]} title={PARTS[0][1]} stamp={stamp}>
        {profile.receivers.map((r, i) => (
          <Receiver key={`${r.name}-${i}`} r={r} profile={profile} />
        ))}
      </Sheet>
      <Sheet id={PARTS[1][0]} title={PARTS[1][1]} stamp={stamp}>
        <Settings profile={profile} />
      </Sheet>
      <Sheet id={PARTS[2][0]} title={PARTS[2][1]} stamp={stamp}>
        <Gate policy={stamp.gatePolicy} />
      </Sheet>
      <Sheet id={PARTS[3][0]} title={PARTS[3][1]} stamp={stamp}>
        <Scenarios catalogue={catalogue} profile={profile} titles={titles} entries={entries} />
      </Sheet>
      <Sheet id={PARTS[4][0]} title={PARTS[4][1]} stamp={stamp}>
        <Limits profile={profile} />
      </Sheet>
    </>
  );
}
