import {
  Alert,
  Anchor,
  Button,
  Card,
  Fieldset,
  Group,
  NativeSelect,
  NumberInput,
  Radio,
  SimpleGrid,
  Stack,
  Switch,
  Text,
  TextInput,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconPlus, IconTrash } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';
import { useQueryClient } from '@tanstack/react-query';
import { api } from '@/api/client';
import { keys, useMe, useSaveSiteProfile, useSiteProfile } from '@/api/hooks';
import type { SiteProfile, SiteProfileView, SiteReceiver } from '@/api/types';
import { ErrorAlert } from '@/components/ErrorAlert';
import { KeyValueList } from '@/components/KeyValueList';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Timestamp } from '@/components/Timestamp';
import { DEMO } from '@/demo';
import { describeError, isApiError } from '@/lib/errors';
import { humanize } from '@/lib/format';
import { Section } from '../cases/case/Section';
import { MoreQuestions } from './MoreQuestions';
import { PolicySummary } from './PolicySummary';
import { Effect, Question } from './Question';
import {
  KINDS,
  KIND_LABELS,
  POLICY_LABELS,
  TIERS,
  TIER_HINTS,
  TIER_LABELS,
  checkDraft,
  describeIncident,
  describePath,
  describeSource,
  diffProfiles,
  fieldId,
  isShipped,
  newReceiver,
  problemField,
  toPutBody,
} from './profile';
import { ReviewModal, type SaveProblem } from './ReviewModal';
import { VersionsPanel } from './VersionsPanel';

/** A choice between known values; a stored value the page doesn't know is shown and kept, never replaced silently. */
function Choice({
  id,
  label,
  value,
  options,
  onChange,
  error,
}: {
  id: string;
  label: string;
  value: string | undefined;
  options: [string, string, string?][];
  onChange: (v: string) => void;
  error?: string;
}) {
  const known = options.some(([v]) => v === value);
  return (
    <Radio.Group id={id} label={label} value={value ?? ''} onChange={onChange} error={error}>
      <Stack gap={6} mt={4}>
        {options.map(([v, l, d]) => (
          <Radio key={v} value={v} label={l} description={d} />
        ))}
        {value && !known ? <Radio value={value} label={`Kept as stored: ${value}`} disabled /> : null}
      </Stack>
    </Radio.Group>
  );
}

type Problem = { path: string; message: string } | null;

function ReceiverFields({
  r,
  i,
  only,
  problem,
  update,
  remove,
}: {
  r: SiteReceiver;
  i: number;
  only: boolean;
  problem: Problem;
  update: (fn: (r: SiteReceiver) => void) => void;
  remove: () => void;
}) {
  const err = (key: string) => (problem?.path === `receivers[${i}].${key}` ? problem.message : undefined);
  const id = (key: string) => `site-receivers-${i}-${key}`;
  // As the core reads them: no api means the ward's paths, and no features means every feature is assumed
  const declared = r.features
    ? Object.entries(r.features)
        .filter(([, on]) => on)
        .map(([k]) => humanize(k).toLowerCase())
        .join(', ') || 'none'
    : 'all assumed (none declared)';
  const endpoints = `Endpoints: ${r.api ? `at ${r.api.base ?? 'the ward\u2019s base'}` : 'the ward\u2019s defaults'}; features: ${declared}`;
  return (
    <Fieldset legend={`Receiver ${i + 1}: ${r.name || 'new'}`}>
      <Stack gap="sm">
        <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
          <TextInput
            id={id('name')}
            label="Production item"
            description="The business operation's name in the production, exactly"
            value={r.name}
            onChange={(e) => {
              const v = e.currentTarget.value;
              update((x) => {
                x.name = v;
              });
            }}
            error={err('name')}
          />
          <TextInput
            id={id('system')}
            label="What it does in the hospital's workflow"
            value={r.system ?? ''}
            onChange={(e) => {
              const v = e.currentTarget.value;
              update((x) => {
                x.system = v;
              });
            }}
            error={err('system')}
          />
        </SimpleGrid>
        <Question n={2} text="Its tier" acts />
        <Choice
          id={id('tier')}
          label={`Tier of ${r.name || 'this receiver'}`}
          value={String(r.tier)}
          options={TIERS.map((t) => [t, TIER_LABELS[t], TIER_HINTS[t]])}
          onChange={(v) =>
            update((x) => {
              x.tier = Number(v);
            })
          }
          error={err('tier')}
        />
        <Question n={3} text="Does it apply messages in arrival order or by event time?" acts={false} />
        <Choice
          id={id('applies')}
          label={`${r.name || 'This receiver'} applies messages`}
          value={r.applies}
          options={[
            [
              'arrival_order',
              'In arrival order',
              'A late message moves the record backwards: the ward does this',
            ],
            ['event_time', 'By event time', 'The receiver orders by the time the event happened'],
          ]}
          onChange={(v) =>
            update((x) => {
              x.applies = v;
            })
          }
          error={err('applies')}
        />
        <Question
          n={4}
          text="Does it take a resend with its original MSH-7, or need a fresh one?"
          acts={false}
        />
        <Choice
          id={id('resend_timestamp')}
          label={`A resend to ${r.name || 'this receiver'} carries`}
          value={r.resend_timestamp}
          options={[
            ['original', 'Its original MSH-7'],
            ['fresh', 'A fresh MSH-7'],
          ]}
          onChange={(v) =>
            update((x) => {
              x.resend_timestamp = v;
            })
          }
          error={err('resend_timestamp')}
        />
        <Question n={5} text="Does it accept cancels (A11, A12, A13)?" acts={false} />
        <Switch
          id={id('cancels')}
          label={`${r.name || 'This receiver'} accepts cancels`}
          description="On record for reviewers and the board: Shutter does not send cancels yet"
          checked={r.cancels === true}
          onChange={(e) => {
            const v = e.currentTarget.checked;
            update((x) => {
              x.cancels = v;
            });
          }}
          error={err('cancels')}
        />
        <Text size="xs" c="dimmed">
          {endpoints}. Kept as they are when you save.
        </Text>
        <Group>
          <Button
            variant="subtle"
            color="red"
            size="xs"
            leftSection={<IconTrash size={14} />}
            disabled={only}
            onClick={remove}
          >
            Remove {r.name || 'this receiver'}
          </Button>
        </Group>
      </Stack>
    </Fieldset>
  );
}

function ProfileForm({
  draft,
  setDraft,
  problem,
  editable,
}: {
  draft: SiteProfile;
  setDraft: (fn: (d: SiteProfile) => void) => void;
  problem: Problem;
  editable: boolean;
}) {
  const err = (path: string) => (problem?.path === path ? problem.message : undefined);
  const num = (v: string | number) => (v === '' ? (undefined as unknown as number) : Number(v));
  return (
    <Fieldset disabled={!editable} variant="unstyled">
      <Stack gap="md">
        <Section
          id="site-receivers"
          title="Receivers"
          note="Questions 1 to 5, for each system this production feeds. The tier picks the row of the approval table below."
        >
          <Question n={1} text="Which receivers does this production feed, and what does each do?" acts />
          {draft.receivers.map((r, i) => (
            <ReceiverFields
              key={i}
              r={r}
              i={i}
              only={draft.receivers.length === 1}
              problem={problem}
              update={(fn) => setDraft((d) => fn(d.receivers[i]))}
              remove={() => setDraft((d) => void d.receivers.splice(i, 1))}
            />
          ))}
          <Group>
            <Button
              variant="light"
              size="xs"
              leftSection={<IconPlus size={14} />}
              onClick={() => setDraft((d) => void d.receivers.push(newReceiver()))}
            >
              Add a receiver
            </Button>
          </Group>
        </Section>
        <Section id="site-history" title="History" note="Question 6.">
          <Question n={6} text="The site's history policy" acts />
          <Choice
            id="site-history-policy"
            label="When a failure has been overtaken"
            value={draft.history_policy}
            options={[
              [
                'current',
                'Keep what is current',
                'Resend only what is still true; earlier events that were overtaken stay as they are',
              ],
              [
                'correct',
                'Correct history',
                'Allows the catalogue’s alternatives that cancel and replay; they always go to a person with the steps named',
              ],
            ]}
            onChange={(v) =>
              setDraft((d) => {
                d.history_policy = v;
              })
            }
            error={err('history_policy')}
          />
        </Section>
        <Section
          id="site-approvals"
          title="Approvals"
          note="Question 7. Automatic is still gated, rehearsed and verified; only the person's approval is left out."
        >
          <Question n={7} text="How each tier\u2019s chains are approved" acts />
          {TIERS.map((tier) => (
            <Fieldset key={tier} legend={`Tier ${TIER_LABELS[tier]}`}>
              <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm">
                {KINDS.map((kind) => {
                  const value = draft.policy?.[tier]?.[kind] ?? '';
                  const known = value in POLICY_LABELS;
                  return (
                    <NativeSelect
                      key={kind}
                      id={`site-policy-${tier}-${kind}`}
                      label={`Tier ${tier}, ${KIND_LABELS[kind]}`}
                      value={value}
                      onChange={(e) => {
                        const v = e.currentTarget.value;
                        setDraft((d) => {
                          d.policy[tier] = { ...(d.policy[tier] ?? {}), [kind]: v };
                        });
                      }}
                      data={[
                        ...(value && !known ? [{ value, label: `Kept as stored: ${value}` }] : []),
                        ...(!value ? [{ value: '', label: 'Not set: one approval' }] : []),
                        ...Object.entries(POLICY_LABELS).map(([v, l]) => ({ value: v, label: l })),
                      ]}
                      error={err(`policy.${tier}.${kind}`)}
                    />
                  );
                })}
              </SimpleGrid>
            </Fieldset>
          ))}
          <Group gap="xs" wrap="wrap">
            <Text fw={600} size="sm">
              Who approves, and the escalation when nobody is available
            </Text>
            <Effect acts={false} />
          </Group>
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
            <TextInput
              id="site-approvers-role"
              label="Who approves"
              description="On record: nothing reads it yet. The permission itself is the Shutter_Approve resource"
              value={draft.approvers?.role ?? ''}
              onChange={(e) => {
                const v = e.currentTarget.value;
                setDraft((d) => {
                  d.approvers = { ...(d.approvers ?? {}), role: v };
                });
              }}
            />
            <TextInput
              id="site-approvers-escalation"
              label="When nobody is available"
              value={draft.approvers?.escalation ?? ''}
              onChange={(e) => {
                const v = e.currentTarget.value;
                setDraft((d) => {
                  d.approvers = { ...(d.approvers ?? {}), escalation: v };
                });
              }}
            />
          </SimpleGrid>
        </Section>
        <Section id="site-incident" title="Incidents" note="Question 8.">
          <Question n={8} text="When do many failures to one receiver become one incident?" acts />
          <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm">
            <NumberInput
              id="site-incident-threshold"
              label="Failures"
              min={1}
              allowDecimal={false}
              clampBehavior="none"
              value={draft.incident?.threshold ?? ''}
              onChange={(v) =>
                setDraft((d) => {
                  d.incident = { ...(d.incident ?? {}), threshold: num(v) };
                })
              }
              error={err('incident.threshold')}
            />
            <NumberInput
              id="site-incident-window_minutes"
              label="Within (minutes)"
              min={1}
              allowDecimal={false}
              clampBehavior="none"
              value={draft.incident?.window_minutes ?? ''}
              onChange={(v) =>
                setDraft((d) => {
                  d.incident = { ...(d.incident ?? {}), window_minutes: num(v) };
                })
              }
              error={err('incident.window_minutes')}
            />
            <NumberInput
              id="site-incident-quiet_seconds"
              label="Intake closes after quiet (seconds)"
              min={0}
              allowDecimal={false}
              clampBehavior="none"
              value={draft.incident?.quiet_seconds ?? ''}
              onChange={(v) =>
                setDraft((d) => {
                  d.incident = { ...(d.incident ?? {}), quiet_seconds: num(v) };
                })
              }
              error={err('incident.quiet_seconds')}
            />
          </SimpleGrid>
          <Text size="sm">{describeIncident(draft)}</Text>
        </Section>
        <MoreQuestions draft={draft} setDraft={setDraft} problem={problem} />
      </Stack>
    </Fieldset>
  );
}

function OtherSettings({ profile }: { profile: SiteProfile }) {
  return (
    <Card padding="md">
      <Stack gap="xs">
        <Text fw={600}>Other settings, kept as they are</Text>
        <Text size="sm" c="dimmed">
          The questions don&apos;t ask about these. They are part of the stored profile and are sent back
          unchanged when you save.
        </Text>
        <KeyValueList
          rows={[
            ['Authoritative source', profile.authoritative_source || 'none named'],
            ['Unconditional resends', profile.unconditional_resend || 'not set'],
            ...profile.receivers.map((r, i): [string, ReactNode] => [
              `Receiver ${i + 1} endpoints`,
              r.api ? (
                <Text key={i} size="sm" className="mono-wrap">
                  {Object.entries(r.api)
                    .map(([k, v]) => `${k} ${v}`)
                    .join(' · ')}
                </Text>
              ) : (
                'the ward’s defaults'
              ),
            ]),
          ]}
        />
      </Stack>
    </Card>
  );
}

const clone = <T,>(x: T): T => JSON.parse(JSON.stringify(x)) as T;
const readProfile = () => api.get<SiteProfileView>('/site-profile');

function Profile({ view }: { view: SiteProfileView }) {
  const me = useMe().data;
  const editable = !!me?.approver;
  const client = useQueryClient();
  const save = useSaveSiteProfile();
  const [draft, setDraftState] = useState<SiteProfile>(() => clone(view.profile));
  const [base, setBase] = useState<SiteProfileView>(view);
  const [problem, setProblem] = useState<Problem>(null);
  const [reviewing, setReviewing] = useState(0);
  const [saveProblem, setSaveProblem] = useState<SaveProblem>(null);

  const [checking, setChecking] = useState(false);

  const setDraft = (fn: (d: SiteProfile) => void) => {
    // An answer changed: the problem shown was about the answers as they were
    setProblem(null);
    setDraftState((prev) => {
      const next = clone(prev);
      fn(next);
      return next;
    });
  };
  const reseed = (v: SiteProfileView) => {
    setBase(v);
    setDraftState(clone(v.profile));
    setProblem(null);
  };
  const changes = diffProfiles(base.profile, draft);
  const shipped = isShipped(base.source);
  const body = toPutBody(draft, base.version);

  // A radio question's id names its label (Mantine keeps the group's own id off the page): focus its chosen radio
  const focusField = (path: string) =>
    window.setTimeout(() => {
      const id = fieldId(path);
      // A zone problem with the offset field open belongs to that field, not to the choice above it
      const el =
        (path === 'feed.time_zone' ? document.getElementById('site-feed-offset') : null) ??
        document.getElementById(id) ??
        document.querySelector<HTMLElement>(`[aria-labelledby="${id}-label"]`) ??
        document.getElementById(`${id}-label`)?.parentElement;
      const target =
        el instanceof HTMLInputElement || el instanceof HTMLSelectElement
          ? el
          : (el?.querySelector<HTMLElement>('input:checked') ?? el?.querySelector<HTMLElement>('input'));
      target?.focus();
    }, 0);

  const review = () => {
    const found = checkDraft(draft);
    const p = found ? problemField(found) : null;
    if (found) {
      setProblem(p ?? { path: '', message: found });
      if (p) focusField(p.path);
      return;
    }
    setProblem(null);
    setSaveProblem(null);
    setReviewing((n) => n + 1);
  };

  const readStored = async () => {
    try {
      return await client.fetchQuery({ queryKey: keys.siteProfile, staleTime: 0, queryFn: readProfile });
    } catch {
      return undefined;
    }
  };

  const savedAsOurs = (v: SiteProfileView | undefined) =>
    !!v &&
    v.version === base.version + 1 &&
    v.updatedBy === me?.username &&
    diffProfiles(v.profile, draft).length === 0;

  const done = (v: SiteProfileView) => {
    reseed(v);
    setReviewing(0);
    notifications.show({
      color: 'teal',
      title: `Version ${v.version} saved`,
      message: 'Shutter decides by it from now on, open cases that have not reached their approval included.',
    });
  };

  const onSave = () => {
    save.mutate(body, {
      onSuccess: done,
      onError: async (e) => {
        const status = isApiError(e) ? e.status : 0;
        const stale = isApiError(e) && e.code === 'stale_version';
        // A stale answer, a dropped connection or a gateway error can each hide our own save that went through:
        // count it saved only when the stored profile is ours, exactly the next version and the same answers.
        if (stale || status === 0 || status >= 500) {
          setChecking(true);
          const v = await readStored();
          setChecking(false);
          if (savedAsOurs(v)) return done(v!);
          if (stale) {
            // Keep the edits and move them onto the version now stored: the next review compares with it
            if (v) setBase(v);
            const sent = (isApiError(e) ? e.body : null) as { currentVersion?: number } | null;
            setSaveProblem({ kind: 'stale', currentVersion: v?.version ?? sent?.currentVersion ?? null });
            return;
          }
          setSaveProblem({
            kind: 'error',
            message:
              v === undefined
                ? `The answer was lost (${describeError(e)}), and the stored profile could not be read to check whether this save went through. Reload the page before saving again.`
                : describeError(e),
          });
          return;
        }
        const p = status === 400 ? problemField(isApiError(e) ? e.message : '') : null;
        if (p && fieldId(p.path)) {
          setReviewing(0);
          setProblem(p);
          focusField(p.path);
          return;
        }
        setSaveProblem({ kind: 'error', message: describeError(e) });
      },
    });
  };

  const loadTheirs = async () => {
    const v = await readStored();
    reseed(v ?? base);
    setReviewing(0);
  };

  const dirty = changes.length > 0;
  const canReview = dirty || shipped;
  return (
    <Stack gap="md">
      <Card padding="md">
        <Stack gap="sm">
          <KeyValueList
            rows={[
              ['Version', String(base.version)],
              ['Source', describeSource(base.source)],
              [
                'Saved',
                base.updatedAt ? (
                  <Group key="s" gap={6}>
                    <Timestamp iso={base.updatedAt} />
                    <Text size="sm">by {base.updatedBy || 'Setup'}</Text>
                  </Group>
                ) : (
                  ''
                ),
              ],
              ['Catalogue entries', String(base.catalogueEntries ?? '')],
            ]}
          />
          {shipped ? (
            <Alert color="blue" variant="light" title="Shutter is running on the shipped answers">
              Check the eleven questions below and save them, changed or not, so Shutter acts as this site
              does.
              {editable ? '' : ' An approver answers them.'}
            </Alert>
          ) : null}
          {DEMO ? (
            <Text size="xs" c="dimmed">
              In the online demo a save lasts until the page is reloaded.
            </Text>
          ) : null}
        </Stack>
      </Card>
      <Card padding="md">
        <PolicySummary profile={draft} />
      </Card>
      <ProfileForm draft={draft} setDraft={setDraft} problem={problem} editable={editable} />
      {problem ? (
        <Alert color="red" variant="light" role="alert" title="Check this answer">
          {problem.path ? (
            <Anchor component="button" type="button" size="sm" onClick={() => focusField(problem.path)}>
              {describePath(problem.path)}: {problem.message}
            </Anchor>
          ) : (
            problem.message
          )}
        </Alert>
      ) : null}
      {editable ? (
        <Group gap="sm">
          <Button color="teal" onClick={review} disabled={!canReview}>
            {dirty ? 'Review and save…' : 'Confirm these answers…'}
          </Button>
          <Button variant="default" disabled={!dirty} onClick={() => reseed(base)}>
            Discard changes
          </Button>
          {!canReview ? (
            <Text size="sm" c="dimmed">
              Nothing has changed since version {base.version}.
            </Text>
          ) : null}
        </Group>
      ) : (
        <Text size="sm" c="dimmed">
          Changing the answers needs the approver role: sign in as approver.
        </Text>
      )}
      <OtherSettings profile={draft} />
      <VersionsPanel current={base.version} />
      {reviewing ? (
        <ReviewModal
          key={reviewing}
          opened
          view={base}
          changes={changes}
          body={body}
          saving={save.isPending || checking}
          problem={saveProblem}
          onCancel={() => setReviewing(0)}
          onSave={onSave}
          onLoadTheirs={() => void loadTheirs()}
        />
      ) : null}
    </Stack>
  );
}

export default function SiteProfilePage() {
  const view = useSiteProfile();
  // Who is signed in decides whether the form can be changed: wait for it, so the form never flashes disabled.
  const me = useMe();
  // Profile keeps its own copy from its first props: a background refetch never overwrites what someone is typing.
  return (
    <>
      <PageHeader
        title="Site profile"
        subtitle="The site's answers to the induction questions. Shutter reads them for each receiver's tier, the approval each chain needs, when many failures become an incident, who an escalation goes to, the feed's time zone and what the model may see. Every saved version is kept."
      />
      {view.isPending || me.isPending ? <PageSkeleton label="Loading the site profile…" /> : null}
      {view.isError ? (
        <ErrorAlert
          error={view.error}
          title={
            isApiError(view.error) && view.error.status === 403
              ? 'Reading the site profile needs the operator or approver role'
              : 'The site profile could not be read'
          }
          onRetry={() => void view.refetch()}
        />
      ) : null}
      {view.data && !me.isPending ? <Profile view={view.data} /> : null}
    </>
  );
}
