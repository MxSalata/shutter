import {
  Alert,
  Anchor,
  Box,
  Button,
  Card,
  Collapse,
  Fieldset,
  Group,
  List,
  SimpleGrid,
  Stack,
  Text,
} from '@mantine/core';
import { notifications } from '@mantine/notifications';
import { IconChevronDown, IconPlus, IconTrash, IconVersions } from '@tabler/icons-react';
import { useState, type ReactNode } from 'react';
import { useSearchParams } from 'react-router';
import { useQueryClient } from '@tanstack/react-query';
import { api } from '@/api/client';
import { DEMO_READ_ONLY, readOnlyDemo } from '@/api/can';
import { keys, useCan, useMe, useSaveSiteProfile, useSiteProfile, useWhatIf } from '@/api/hooks';
import type { SiteProfile, SiteProfileView, SiteReceiver, WhatIf } from '@/api/types';
import { ApiSource } from '@/components/ApiSource';
import { ErrorAlert } from '@/components/ErrorAlert';
import { KeyValueList } from '@/components/KeyValueList';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { Section } from '@/components/Section';
import { StatusBadge, StatusNotice } from '@/components/StatusBadge';
import { TechDetail } from '@/components/TechDetail';
import { Term } from '@/components/Term';
import { Timestamp } from '@/components/Timestamp';
import { byEnv, toBecomeApprover } from '@/env/copy';
import { TRIAL } from '@/env/mode';
import { CATEGORIES, CATEGORY_TEXT, categoryOf, derivedPolicy } from '@/lib/categories';
import { describeError, isApiError } from '@/lib/errors';
import { glossary } from '@/lib/glossary';
import { SITE_ICON } from '@/lib/hues';
import { NativeSelect, NumberInput, Radio, Switch, TextInput } from './controls';
import { EditableProvider } from './editable';
import { MoreQuestions } from './MoreQuestions';
import { PageIndexNav, PageIndexSelect } from './PageIndex';
import { ReceiverCards } from './ReceiverCards';
import { ReleaseMatrix } from './ReleaseMatrix';
import { Effect, Question, QuestionDetails, type KeyRow } from './Question';
import {
  KINDS,
  KIND_LABELS,
  KIND_TERMS,
  POLICY_LABELS,
  TIERS,
  TIER_HINTS,
  TIER_LABELS,
  TIER_NAMES,
  checkDraft,
  closeNeedsApprover,
  describeIncident,
  EFFECT_WORDS,
  describePath,
  describeSource,
  diffProfiles,
  fieldId,
  incidentRule,
  isShipped,
  newReceiver,
  overtakenLine,
  problemField,
  toPutBody,
} from './profile';
import { ReviewModal, type SaveProblem } from './ReviewModal';
import { SaveBar } from './SaveBar';
import { VersionsPanel } from './VersionsPanel';
import { SuggestionCard } from './SuggestionCard';
import {
  FACT_PARAM,
  SUGGEST_PARAM,
  applySuggestion,
  parseSuggestion,
  revertSuggestion,
  suggestionFromFact,
  type Applied,
  type SuggestedChange,
  type SuggestionRef,
} from './suggestion';

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

/**
 * The receiver's category, with what it means, and the history policy override behind "Advanced": the category derives
 * the policy, and an override is for a records system that keeps only the present placement, or a bed manager that
 * wants its history straight.
 */
function CategoryFields({
  r,
  i,
  err,
  update,
}: {
  r: SiteReceiver;
  i: number;
  err: (key: string) => string | undefined;
  update: (fn: (r: SiteReceiver) => void) => void;
}) {
  const id = (key: string) => `site-receivers-${i}-${key}`;
  const category = categoryOf(r);
  const known = !r.category || (CATEGORIES as string[]).includes(String(r.category));
  const [shown, setAdvanced] = useState(!!r.history_policy);
  // A problem with the override opens it, so the alert's link reaches the field
  const advanced = shown || !!err('history_policy');
  const text = CATEGORY_TEXT[category];
  const derived = derivedPolicy(category);
  const policyKnown = !r.history_policy || ['current', 'correct'].includes(String(r.history_policy));
  return (
    <Stack gap={6}>
      <NativeSelect
        id={id('category')}
        label={`Category of ${r.name || 'this receiver'}`}
        description={r.category ? undefined : 'Not answered: read as current state, as before categories'}
        value={r.category ? String(r.category) : ''}
        onChange={(e) => {
          const v = e.currentTarget.value;
          update((x) => {
            if (v) x.category = v;
            else delete x.category;
          });
        }}
        data={[
          ...(!known ? [{ value: String(r.category), label: `Kept as stored: ${String(r.category)}` }] : []),
          ...(!r.category ? [{ value: '', label: 'Not answered: current state' }] : []),
          ...CATEGORIES.map((c) => ({
            value: c,
            label: `${CATEGORY_TEXT[c].label}: ${CATEGORY_TEXT[c].gist.toLowerCase()}${CATEGORY_TEXT[c].modelled ? '' : ' (not modelled yet)'}`,
          })),
        ]}
        error={err('category')}
      />
      <Text size="sm" id={id('category-meaning')}>
        {text.examples}. {overtakenLine(category, derived)}
      </Text>
      <Group>
        <Button
          variant="subtle"
          size="compact-sm"
          color="gray"
          onClick={() => setAdvanced((a) => !a)}
          aria-expanded={advanced}
          aria-controls={id('advanced')}
          leftSection={
            <IconChevronDown
              size={14}
              aria-hidden
              style={{ transform: advanced ? 'rotate(180deg)' : undefined, transition: 'transform 150ms' }}
            />
          }
        >
          Advanced: its history policy
        </Button>
      </Group>
      {advanced ? (
        <div id={id('advanced')}>
          <NativeSelect
            id={id('history_policy')}
            label="When a failure at it has been overtaken"
            description="The category decides this. Set it here only when this system differs from its kind."
            value={r.history_policy ? String(r.history_policy) : ''}
            onChange={(e) => {
              const v = e.currentTarget.value;
              update((x) => {
                if (v) x.history_policy = v;
                else delete x.history_policy;
              });
            }}
            data={[
              ...(!policyKnown
                ? [{ value: String(r.history_policy), label: `Kept as stored: ${String(r.history_policy)}` }]
                : []),
              {
                value: '',
                label: `From its category: ${derived === 'correct' ? 'correct the history by hand' : 'keep what is current'}`,
              },
              { value: 'current', label: 'Keep what is current: close with no write' },
              { value: 'correct', label: 'Correct the history: escalate with the steps named' },
            ]}
            error={err('history_policy')}
          />
        </div>
      ) : (
        <div id={id('advanced')} hidden />
      )}
    </Stack>
  );
}

function ReceiverFields({
  r,
  i,
  only,
  problem,
  editable,
  update,
  remove,
}: {
  r: SiteReceiver;
  i: number;
  only: boolean;
  editable: boolean;
  problem: Problem;
  update: (fn: (r: SiteReceiver) => void) => void;
  remove: () => void;
}) {
  const err = (key: string) => (problem?.path === `receivers[${i}].${key}` ? problem.message : undefined);
  const id = (key: string) => `site-receivers-${i}-${key}`;
  const at = (key: string) => `receivers[${i}].${key}`;
  const category = categoryOf(r);
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
        <Question n={2} text="What kind of system is it?" acts />
        <CategoryFields r={r} i={i} err={err} update={update} />
        <QuestionDetails
          keys={[
            [at('category'), r.category, 'current_state'],
            [at('history_policy'), r.history_policy, 'from its category'],
          ]}
          more={CATEGORY_TEXT[category].overtaken}
        />
        <Question n={3} text="Its tier" acts />
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
        <QuestionDetails
          keys={[[at('tier'), r.tier]]}
          more="The tier is how sensitive the receiver is. It picks the row of the approval table: who releases a write to it."
        />
        <Question n={4} text="Does it apply messages in arrival order or by event time?" acts={false} />
        <Choice
          id={id('applies')}
          label={`${r.name || 'This receiver'} applies messages`}
          value={r.applies}
          options={[
            [
              'arrival_order',
              'In arrival order',
              'A late message moves the record backwards: the downstream system does this',
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
        <QuestionDetails keys={[[at('applies'), r.applies]]} />
        <Question
          n={5}
          text={
            <>
              Does it take a resend with its original {i === 0 ? <Term term="msh-7">MSH-7</Term> : 'MSH-7'},
              or need a fresh one?
            </>
          }
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
        <QuestionDetails keys={[[at('resend_timestamp'), r.resend_timestamp]]} />
        <Question n={6} text="Does it accept cancels (A11, A12, A13) and merges (A40)?" acts />
        <Switch
          id={id('cancels')}
          label={`${r.name || 'This receiver'} accepts cancels`}
          description="Off: Shutter never sends it a cancel; the case goes to a person, who corrects the receiver by hand"
          checked={r.cancels === true}
          onChange={(e) => {
            const v = e.currentTarget.checked;
            update((x) => {
              x.cancels = v;
            });
          }}
          error={err('cancels')}
        />
        <Switch
          id={id('merges')}
          label={`${r.name || 'This receiver'} takes merges`}
          description="A merge also needs the site to allow merges (question 12); otherwise it goes to the PAS team"
          checked={r.merges === true}
          onChange={(e) => {
            const v = e.currentTarget.checked;
            update((x) => {
              x.merges = v;
            });
          }}
          error={err('merges')}
        />
        <QuestionDetails
          keys={[
            [at('cancels'), r.cancels, 'false'],
            [at('merges'), r.merges, 'false'],
          ]}
          more="Its endpoints and declared features are kept as they are when you save."
        />
        <Group>
          <Button
            variant="subtle"
            color="red"
            size="xs"
            leftSection={<IconTrash size={14} />}
            disabled={only || !editable}
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
  // Offered, not applied: the receivers are the longest section, and every field stays in the page when it is folded
  const [folded, setFolded] = useState(false);
  const showReceivers = !folded || /^receivers\[/.test(problem?.path ?? '');
  return (
    <EditableProvider value={editable}>
      <Stack gap="md">
        <Section
          id="site-receivers"
          title="Receivers"
          note="For each system this production feeds. The category sets what an overtaken failure does; the tier sets who releases a write."
          aside={
            <Button
              variant="subtle"
              color="gray"
              size="compact-sm"
              aria-expanded={showReceivers}
              aria-controls="site-receivers-body"
              leftSection={
                <IconChevronDown
                  size={14}
                  aria-hidden
                  style={{ transform: showReceivers ? 'rotate(180deg)' : undefined }}
                />
              }
              onClick={() => setFolded(showReceivers)}
            >
              {showReceivers ? 'Collapse the receivers' : `Show the receivers (${draft.receivers.length})`}
            </Button>
          }
        >
          <Collapse in={showReceivers} id="site-receivers-body">
            <Stack gap="sm">
              <Question n={1} text="Which receivers does this production feed, and what does each do?" acts />
              {draft.receivers.map((r, i) => (
                <ReceiverFields
                  key={i}
                  r={r}
                  i={i}
                  only={draft.receivers.length === 1}
                  editable={editable}
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
                  disabled={!editable}
                  onClick={() => setDraft((d) => void d.receivers.push(newReceiver()))}
                >
                  Add a receiver
                </Button>
              </Group>
              <QuestionDetails
                keys={[
                  ['receivers[].name', draft.receivers.map((r) => r.name)],
                  ['receivers[].system', draft.receivers.map((r) => r.system ?? '')],
                ]}
              />
            </Stack>
          </Collapse>
        </Section>
        {/* The site-wide answer is read only for a receiver with neither a category nor its own policy: shown only then */}
        {draft.history_policy !== undefined &&
        draft.receivers.some((r) => !r.category && !r.history_policy) ? (
          <Section
            id="site-history"
            title="Site-wide history policy"
            note="Read only for a receiver with no category of its own. Give each receiver its category above, and this answer is no longer read."
          >
            <Choice
              id="site-history-policy"
              label="When a failure has been overtaken, at a receiver with no category"
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
        ) : null}
        <Section
          id="site-approvals"
          tour="site-approvals"
          title="Approvals"
          note="Automatic is still gated, rehearsed and verified; only the person's approval is left out."
        >
          <Question n={7} text="How each tier's chains are approved" acts />
          {TIERS.map((tier) => (
            <Fieldset key={tier} legend={`Tier ${tier}: ${TIER_NAMES[tier]}`}>
              <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm">
                {KINDS.map((kind) => {
                  const value = draft.policy?.[tier]?.[kind] ?? '';
                  const known = value in POLICY_LABELS;
                  return (
                    <NativeSelect
                      key={kind}
                      id={`site-policy-${tier}-${kind}`}
                      label={`Tier ${tier}, ${KIND_LABELS[kind]}`}
                      description={glossary(KIND_TERMS[kind]).term}
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
          <QuestionDetails
            keys={TIERS.map((tier): KeyRow => [`policy.${tier}`, draft.policy?.[tier], 'one approval'])}
            more="Single, ordered and interleaved are the names the profile gives the three kinds of failure. A tier or kind that is not set needs one approval."
          />
          <Group gap="sm" wrap="nowrap" align="flex-start">
            <Text fw={600} size="md" style={{ flex: 1, minWidth: 0 }}>
              Who approves, and the escalation when nobody is available
            </Text>
            <Effect acts={false} />
          </Group>
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
            <TextInput
              id="site-approvers-role"
              label="Who approves"
              description="The permission itself is the Shutter_Approve resource."
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
          <QuestionDetails
            keys={[
              ['approvers.role', draft.approvers?.role],
              ['approvers.escalation', draft.approvers?.escalation],
            ]}
          />
          <Group gap="sm" wrap="nowrap" align="flex-start">
            <Text fw={600} size="md" style={{ flex: 1, minWidth: 0 }}>
              Who closes a case the team corrected by hand
            </Text>
            <Effect acts />
          </Group>
          <Switch
            id="site-approvers-close_needs_approver"
            label="Closing a case by hand needs an approver"
            description="On: only an approver marks a case handled once the team has corrected it. Off: an operator can too."
            checked={closeNeedsApprover(draft)}
            onChange={(e) => {
              const v = e.currentTarget.checked;
              setDraft((d) => {
                d.approvers = { ...(d.approvers ?? {}), close_needs_approver: v };
              });
            }}
            error={err('approvers.close_needs_approver')}
          />
          <Text size="sm">
            A case the team corrected by hand is marked handled by{' '}
            {closeNeedsApprover(draft)
              ? 'an approver only (the two-person rule)'
              : 'an operator or an approver'}
            .
          </Text>
          <QuestionDetails
            keys={[['approvers.close_needs_approver', draft.approvers?.close_needs_approver, 'false']]}
            more="On, an operator on call escalates a case and asks an approver to close it. Shutter checks the role of whoever closes the case, not that it is a second person: an approver may escalate and close the same case. Off, an operator can close it too, the one who escalated it included."
          />
        </Section>
        <Section id="site-incident" title="Incidents">
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
          <Text size="sm">{incidentRule(draft)}</Text>
          <QuestionDetails
            keys={[
              ['incident.threshold', draft.incident?.threshold, '5'],
              ['incident.window_minutes', draft.incident?.window_minutes, '10'],
              ['incident.quiet_seconds', draft.incident?.quiet_seconds, '60'],
            ]}
            more={describeIncident(draft)}
          />
        </Section>
        <MoreQuestions draft={draft} setDraft={setDraft} problem={problem} />
      </Stack>
    </EditableProvider>
  );
}

/**
 * The version in force and where it came from, then the stored settings the questions don't ask about: second-layer
 * data, open in Technical. What a reader needs in the first layer is the header's version and "Shipped answers".
 */
function OtherSettings({ profile, base }: { profile: SiteProfile; base: SiteProfileView }) {
  return (
    <TechDetail label="Version, source and other settings" kind="data">
      <Stack gap="xs">
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
                'the downstream system’s defaults'
              ),
            ]),
            ...profile.receivers
              .map((r, i): [string, ReactNode] => [
                `Receiver ${i + 1} demo namespace`,
                r.demo?.namespace
                  ? `${r.demo.namespace}: the scenario runner resets it and sets its faults there`
                  : '',
              ])
              .filter(([, v]) => v),
          ]}
        />
        <Text size="sm" c="dimmed">
          The questions don&apos;t ask about the last settings here. They are part of the stored profile and
          are sent back unchanged when you save.
        </Text>
      </Stack>
    </TechDetail>
  );
}

const clone = <T,>(x: T): T => JSON.parse(JSON.stringify(x)) as T;
const readProfile = () => api.get<SiteProfileView>('/site-profile');

/** A suggestion as the page shows it: the case and fact from the address, and the change read from the case's facts. */
interface Suggested {
  ref: SuggestionRef;
  s?: SuggestedChange;
  result: Applied;
}

/**
 * The change a case's What-if fact suggests, built from the facts GET /cases/{id}/whatif gives now, never from the
 * address: the address names only the case and the fact.
 */
function readSuggestion(
  ref: SuggestionRef,
  whatif: WhatIf | null | undefined,
  failed: boolean,
  profile: SiteProfile,
): Suggested {
  if (failed) return { ref, result: { ok: false, reason: 'unreadable' } };
  const fact = whatif?.facts.find((f) => f.id === ref.fact);
  if (!fact) return { ref, result: { ok: false, reason: 'no_fact' } };
  const s = suggestionFromFact(ref.caseId, fact);
  return { ref, s, result: applySuggestion(profile, s) };
}

function Profile({
  view,
  suggestion,
}: {
  view: SiteProfileView;
  /** The change a case suggested (`?suggest=&fact=`), read once from its facts when the page opened. */
  suggestion: Suggested | null;
}) {
  const me = useMe().data;
  const can = useCan();
  // Saving the profile is the configure resource's; the public demo's role approves but cannot configure, so it reads
  // the draft and the review of a change and finds a note where Save would be
  const editable = can.configure;
  const reading = readOnlyDemo(can);
  const client = useQueryClient();
  const save = useSaveSiteProfile();
  // A change a case's What-if card suggested (`?suggest=`): applied to the draft once, when the page opens; the
  // approver saves it through the review below, as any other change
  const [search, setSearch] = useSearchParams();
  const [suggested] = useState(suggestion);
  const [showSuggestion, setShowSuggestion] = useState(!!suggested);
  const [draft, setDraftState] = useState<SiteProfile>(() =>
    suggested?.result.ok ? suggested.result.profile : clone(view.profile),
  );
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

  /** The suggestion has been saved or set aside: it leaves the page and the address, so a reload does not bring it back. */
  const dropSuggestion = () => {
    setShowSuggestion(false);
    if (search.has(SUGGEST_PARAM) || search.has(FACT_PARAM))
      setSearch(
        (prev) => {
          const params = new URLSearchParams(prev);
          params.delete(SUGGEST_PARAM);
          params.delete(FACT_PARAM);
          return params;
        },
        { replace: true, preventScrollReset: true },
      );
  };

  const done = (v: SiteProfileView) => {
    dropSuggestion();
    reseed(v);
    setReviewing(0);
    notifications.show({
      color: 'blue',
      title: `Version ${v.version} saved`,
      message: byEnv({
        live: 'Shutter decides by it from now on, open cases that have not reached their approval included.',
        trial: 'Saved in the trial. It lasts until you reload or leave.',
      }),
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
  // Something to say about the answer a review refused: in the save bar while it shows, else on its own
  const problemAlert = problem ? (
    <Alert color="red" variant="light" role="alert" title="Check this answer">
      {problem.path ? (
        <Anchor component="button" type="button" size="sm" onClick={() => focusField(problem.path)}>
          {describePath(problem.path)}: {problem.message}
        </Anchor>
      ) : (
        problem.message
      )}
    </Alert>
  ) : null;
  return (
    <>
      <PageHeader
        title="Site profile"
        icon={SITE_ICON}
        hue="teal"
        status={
          <Group gap={6}>
            <StatusBadge tone="neutral" icon={IconVersions} label={`Version ${base.version}`} />
            {shipped ? <StatusBadge tone="info" label="Shipped answers" /> : null}
          </Group>
        }
        lead={
          <>
            This hospital&apos;s answers: they decide what Shutter may do at each{' '}
            <Term term="receiver">receiver</Term>.
          </>
        }
        details={<HeaderDetails />}
        meta={
          !shipped && base.updatedAt ? (
            <Text size="sm" c="dimmed">
              Saved <Timestamp iso={base.updatedAt} span inherit /> by {base.updatedBy || 'Setup'}
            </Text>
          ) : null
        }
      />
      <Stack gap="lg">
        {suggested && showSuggestion ? (
          <SuggestionCard
            caseId={suggested.ref.caseId}
            s={suggested.s}
            result={suggested.result}
            version={base.version}
            editable={editable}
            reviewOnly={reading}
            onReview={review}
            onDiscard={() => {
              // Only the suggested field goes back to the stored value: other edits in the draft stay
              const s = suggested.s;
              if (suggested.result.ok && s) {
                setProblem(null);
                setDraftState((prev) => revertSuggestion(prev, base.profile, s));
              }
              dropSuggestion();
            }}
          />
        ) : null}
        {shipped ? (
          <StatusNotice tone="info" title="Shutter is running on the shipped answers">
            <Stack gap="xs">
              <Text size="md" data-testid={reading && !dirty ? 'demo-read-only' : undefined}>
                They are defaults, not this site&apos;s choices.{' '}
                {editable
                  ? 'Check the questions below, then confirm or change them and save.'
                  : reading
                    ? `${DEMO_READ_ONLY}.`
                    : 'An approver answers them.'}
              </Text>
              {editable && !dirty ? (
                <>
                  <Group>
                    <Button onClick={review}>Confirm these answers…</Button>
                  </Group>
                  {TRIAL ? <Text size="sm">A save lasts until you reload or leave.</Text> : null}
                </>
              ) : null}
            </Stack>
          </StatusNotice>
        ) : null}
        <Stack gap="md" component="section" aria-labelledby="site-policy-title">
          <Text component="h2" id="site-policy-title" className="overline" m={0}>
            What this site&apos;s policy does
          </Text>
          <ReceiverCards profile={draft} />
          <Card withBorder padding="md">
            <ReleaseMatrix profile={draft} />
          </Card>
        </Stack>
        <Box component="section" aria-labelledby="site-answers-title">
          <Group align="flex-start" wrap="nowrap" gap="lg">
            <Stack gap="md" style={{ flex: 1, minWidth: 0 }}>
              <Text component="h2" id="site-answers-title" className="overline" m={0}>
                The answers
              </Text>
              <PageIndexSelect />
              <ul
                aria-label="What the icons mean"
                style={{
                  listStyle: 'none',
                  margin: 0,
                  padding: 0,
                  display: 'flex',
                  flexWrap: 'wrap',
                  gap: 16,
                }}
              >
                {([true, false] as const).map((acts) => (
                  <li key={String(acts)} style={{ display: 'flex', alignItems: 'center', gap: 6 }}>
                    <Effect acts={acts} decorative />
                    <Text span size="sm">
                      {acts ? EFFECT_WORDS.acts : EFFECT_WORDS.record}
                    </Text>
                  </li>
                ))}
              </ul>
              <ProfileForm draft={draft} setDraft={setDraft} problem={problem} editable={editable} />
              <VersionsPanel current={base.version} />
              <OtherSettings profile={draft} base={base} />
            </Stack>
            <PageIndexNav />
          </Group>
        </Box>
        {reading && !dirty && !shipped ? (
          <Text size="sm" c="dimmed" data-testid="demo-read-only">
            {DEMO_READ_ONLY}.
          </Text>
        ) : null}
        {!editable && !reading ? (
          <Text size="sm" c="dimmed">
            {`Changing the answers needs the approver role: ${toBecomeApprover()}.`}
          </Text>
        ) : null}
        {!dirty ? problemAlert : null}
        <ApiSource endpoint="GET /api/shutter/site-profile" data={base} />
        {dirty && (editable || reading) ? (
          <SaveBar
            count={changes.length}
            onReview={review}
            onDiscard={editable ? () => reseed(base) : undefined}
            reviewLabel={editable ? 'Review and save…' : 'Review the changes…'}
            alert={problemAlert}
            note={
              !editable ? (
                <Text size="sm" c="dimmed" data-testid="demo-read-only">
                  {DEMO_READ_ONLY}.
                </Text>
              ) : TRIAL ? (
                <Text size="sm" c="dimmed">
                  A save lasts until you reload or leave.
                </Text>
              ) : null
            }
          />
        ) : null}
        {reviewing ? (
          <ReviewModal
            key={reviewing}
            opened
            view={base}
            changes={changes}
            body={body}
            saving={save.isPending || checking}
            readOnly={reading}
            problem={saveProblem}
            onCancel={() => setReviewing(0)}
            onSave={onSave}
            onLoadTheirs={() => void loadTheirs()}
          />
        ) : null}
      </Stack>
    </>
  );
}

/** The long expert paragraph the header used to carry, as a list of what Shutter reads from the answers. */
function HeaderDetails() {
  return (
    <Stack gap={4}>
      <Text size="sm">Shutter reads these answers for:</Text>
      <List size="sm" spacing={2}>
        <List.Item>each receiver&apos;s category and tier</List.Item>
        <List.Item>the approval each chain needs</List.Item>
        <List.Item>who may close a case by hand</List.Item>
        <List.Item>when many failures become an incident</List.Item>
        <List.Item>who an escalation goes to</List.Item>
        <List.Item>the feed&apos;s time zone</List.Item>
        <List.Item>what the model may see</List.Item>
        <List.Item>whether a merge is ever sent</List.Item>
      </List>
      <Text size="sm">Every saved version is kept.</Text>
    </Stack>
  );
}

export default function SiteProfilePage() {
  const view = useSiteProfile();
  // A change a case suggested: the address names the case and the fact, and the change is read from the case's facts
  const [search] = useSearchParams();
  const [ref] = useState(() => parseSuggestion(search));
  const whatif = useWhatIf(ref?.caseId ?? '', !!ref);
  const waiting = !!ref && whatif.isPending;
  // Who is signed in decides whether the form can be changed: wait for it, so the form never flashes disabled.
  const me = useMe();
  // Profile keeps its own copy from its first props: a background refetch never overwrites what someone is typing.
  return (
    <>
      {!view.data || me.isPending || waiting ? (
        <PageHeader
          title="Site profile"
          icon={SITE_ICON}
          hue="teal"
          lead={
            <>
              This hospital&apos;s answers: they decide what Shutter may do at each{' '}
              <Term term="receiver">receiver</Term>.
            </>
          }
        />
      ) : null}
      {view.isPending || me.isPending || waiting ? <PageSkeleton label="Loading the site profile…" /> : null}
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
      {view.data && !me.isPending && !waiting ? (
        <Profile
          view={view.data}
          suggestion={ref ? readSuggestion(ref, whatif.data, whatif.isError, view.data.profile) : null}
        />
      ) : null}
    </>
  );
}
