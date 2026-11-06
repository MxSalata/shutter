import { Alert, Button, Fieldset, Group, SimpleGrid, Stack, Text } from '@mantine/core';
import { IconPlus, IconTrash } from '@tabler/icons-react';
import { useState, type ChangeEvent } from 'react';
import type { SiteProfile, SiteTeam } from '@/api/types';
import { Section } from '@/components/Section';
import { TechDetail } from '@/components/TechDetail';
import { Checkbox, NativeSelect, NumberInput, Radio, Switch, TextInput } from './controls';
import { useEditable } from './editable';
import { IANA_ZONE, ZONE_LABELS, newTeam, parseList } from './profile';
import { Question, QuestionDetails } from './Question';
import {
  DAY_LABELS,
  DETAIL_LABELS,
  REMINDER_DEFAULTS,
  reminderPreview,
  type Reminders,
} from './reminderPreview';

type Problem = { path: string; message: string } | null;
type SetDraft = (fn: (d: SiteProfile) => void) => void;

const OFFSET = /^[+-](0[0-9]|1[0-4]):[0-5][0-9]$/;

/**
 * A list typed as text ("a@x.nhs.uk, b@x.nhs.uk"). What was typed is kept while it still reads as the stored list, so
 * a trailing comma or space survives the next render; a list changed elsewhere (discarded edits) shows as stored.
 */
function ListInput({
  id,
  label,
  description,
  value,
  onList,
  error,
}: {
  id: string;
  label: string;
  description?: string;
  value: string[];
  onList: (list: string[]) => void;
  error?: string;
}) {
  const [raw, setRaw] = useState(value.join(', '));
  const shown = JSON.stringify(parseList(raw)) === JSON.stringify(value) ? raw : value.join(', ');
  return (
    <TextInput
      id={id}
      label={label}
      description={description}
      value={shown}
      onChange={(e) => {
        const v = e.currentTarget.value;
        setRaw(v);
        onList(parseList(v));
      }}
      error={error}
    />
  );
}

function TeamFields({
  t,
  i,
  receivers,
  problem,
  update,
  remove,
}: {
  t: SiteTeam;
  i: number;
  receivers: string[];
  problem: Problem;
  update: (fn: (t: SiteTeam) => void) => void;
  remove: () => void;
}) {
  // An error on one copy or one receiver of the list belongs to the list's control
  const err = (key: string) =>
    problem && problem.path.replace(/\[\d+\]$/, '') === `teams[${i}].${key}` ? problem.message : undefined;
  const id = (key: string) => `site-teams-${i}-${key}`;
  const editable = useEditable();
  const named = t.receivers ?? [];
  const unknown = named.filter((r) => !receivers.includes(r));
  return (
    <Fieldset legend={`Team ${i + 1}: ${t.name || 'new'}`}>
      <Stack gap="sm">
        <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm">
          <TextInput
            id={id('id')}
            label="Short id"
            description="Unique, for the record: pas, integration"
            value={t.id}
            onChange={(e) => {
              const v = e.currentTarget.value;
              update((x) => {
                x.id = v;
              });
            }}
            error={err('id')}
          />
          <TextInput
            id={id('name')}
            label="Team"
            description="As the email greets them"
            value={t.name}
            onChange={(e) => {
              const v = e.currentTarget.value;
              update((x) => {
                x.name = v;
              });
            }}
            error={err('name')}
          />
          <TextInput
            id={id('mailbox')}
            label="Mailbox"
            description="A shared mailbox, not a person's"
            value={t.mailbox}
            onChange={(e) => {
              const v = e.currentTarget.value;
              update((x) => {
                x.mailbox = v;
              });
            }}
            error={err('mailbox')}
          />
        </SimpleGrid>
        <ListInput
          id={id('cc')}
          label="Copies"
          description="Other mailboxes, separated by commas"
          value={t.cc ?? []}
          onList={(list) =>
            update((x) => {
              x.cc = list;
            })
          }
          error={err('cc')}
        />
        <ListInput
          id={id('sources')}
          label="Sending applications whose merges it decides"
          description="MSH-3, such as PAS, separated by commas: a merge from them comes to this team first"
          value={t.sources ?? []}
          onList={(list) =>
            update((x) => {
              x.sources = list;
            })
          }
          error={err('sources')}
        />
        <Checkbox.Group
          id={id('receivers')}
          label="The receivers whose data this team corrects"
          description="A case goes to the team that names its receiver, else to the first team"
          value={named}
          onChange={(v) =>
            update((x) => {
              // Names the page doesn't know (a receiver since removed) stay as stored, after the known ones
              x.receivers = [...receivers.filter((r) => v.includes(r)), ...unknown];
            })
          }
          error={err('receivers')}
        >
          <Group gap="md" mt={6}>
            {receivers.map((r, j) => (
              <Checkbox
                key={`${r}-${j}`}
                value={r}
                label={r || `Receiver ${j + 1} (unnamed)`}
                disabled={!r}
              />
            ))}
            {unknown.map((r) => (
              <Checkbox key={`kept-${r}`} value={r} label={`Kept as stored: ${r}`} disabled />
            ))}
          </Group>
        </Checkbox.Group>
        <Group>
          <Button
            variant="subtle"
            color="red"
            size="xs"
            leftSection={<IconTrash size={14} />}
            disabled={!editable}
            onClick={remove}
          >
            Remove {t.name || 'this team'}
          </Button>
        </Group>
      </Stack>
    </Fieldset>
  );
}

function Teams({ draft, setDraft, problem }: { draft: SiteProfile; setDraft: SetDraft; problem: Problem }) {
  const editable = useEditable();
  const teams = draft.teams ?? [];
  const receivers = draft.receivers.map((r) => r.name);
  const err = (path: string) =>
    problem && problem.path.replace(/\[\d+\]$/, '') === path ? problem.message : undefined;
  return (
    <Section
      id="site-escalation"
      title="Escalation"
      note="When Shutter can't recover a case, it drafts an email for a person to check and send."
    >
      <Question
        n={9}
        text="Who corrects a receiver's data by hand when Shutter can't, and where does their email go?"
        acts
      />
      {teams.length === 0 ? (
        <Alert color="gray" variant="light">
          No team yet. The person escalating a case then types the address, and the draft is addressed to{' '}
          {draft.approvers?.escalation ? `"${draft.approvers.escalation}"` : 'nobody in particular'}.
        </Alert>
      ) : null}
      {teams.map((t, i) => (
        <TeamFields
          key={i}
          t={t}
          i={i}
          receivers={receivers}
          problem={problem}
          update={(fn) => setDraft((d) => fn(d.teams![i]))}
          remove={() =>
            setDraft((d) => {
              d.teams!.splice(i, 1);
            })
          }
        />
      ))}
      <Group>
        <Button
          variant="light"
          size="xs"
          leftSection={<IconPlus size={14} />}
          disabled={!editable}
          onClick={() =>
            setDraft((d) => {
              d.teams = [...(d.teams ?? []), newTeam()];
            })
          }
        >
          Add a team
        </Button>
      </Group>
      <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
        <ListInput
          id="site-mail-allowed_domains"
          label="Mail domains allowed for the teams"
          description="Every team mailbox and every address typed into an escalation must be in one of these or a subdomain."
          value={draft.mail?.allowed_domains ?? []}
          onList={(list) =>
            setDraft((d) => {
              d.mail = { ...(d.mail ?? {}), allowed_domains: list };
              if (!list.length) delete d.mail.allowed_domains;
            })
          }
          error={err('mail.allowed_domains')}
        />
        <TextInput
          id="site-mail-from"
          label="Sent from"
          description="The sender of the emails; when empty, the Escalation Mail operation's From setting in the production"
          value={draft.mail?.from ?? ''}
          onChange={(e) => {
            const v = e.currentTarget.value;
            setDraft((d) => {
              d.mail = { ...(d.mail ?? {}), from: v };
              if (!v) delete d.mail.from;
            });
          }}
          error={err('mail.from')}
        />
      </SimpleGrid>
      <QuestionDetails
        keys={[
          [
            'teams',
            teams.length ? teams.map((t) => t.id) : undefined,
            'no team: the person escalating types the address',
          ],
          ['mail.allowed_domains', draft.mail?.allowed_domains, 'none allowed'],
          ['mail.from', draft.mail?.from, "the Escalation Mail operation's From setting"],
        ]}
        more="The draft is built from the stored case: identifiers, date of birth and the event, never a name, an address or note text. A domain also allows its subdomains (nhs.net takes trust.nhs.net). With none listed no address is allowed, so a team mailbox needs a domain first."
      />
    </Section>
  );
}

function Feed({ draft, setDraft, problem }: { draft: SiteProfile; setDraft: SetDraft; problem: Problem }) {
  const zone = draft.feed?.time_zone;
  // Not answered, one of the named zones, another IANA zone kept as stored (the page offers no list of them, and the
  // server knows which it has), or an offset (an empty one is the offset field being cleared to retype)
  const choice = zone === undefined ? '' : zone in ZONE_LABELS || IANA_ZONE.test(zone) ? zone : 'offset';
  const stored = choice !== '' && choice !== 'offset' && !(choice in ZONE_LABELS);
  // The field shows the draft's own value; this only remembers the last offset for coming back to it from UTC or UK time
  const [lastOffset, setLastOffset] = useState(choice === 'offset' && zone ? zone : '+01:00');
  const setZone = (z: string) =>
    setDraft((d) => {
      d.feed = { ...(d.feed ?? {}), time_zone: z };
    });
  const error = problem?.path === 'feed.time_zone' ? problem.message : undefined;
  return (
    <Section
      id="site-feed"
      title="Feed"
      note="HL7 times that carry no offset (EVN-2, EVN-6, MSH-7, PV1-44) are read in this zone; the gate orders and supersedes by them."
    >
      <Question n={10} text="In which time zone does the PAS send times without an offset?" acts />
      <Radio.Group
        id="site-feed-time_zone"
        label="The PAS's times are"
        value={choice}
        onChange={(v) => setZone(v === 'offset' ? lastOffset : v)}
        error={error}
      >
        <Stack gap={6} mt={4}>
          <Radio
            value="Europe/London"
            label={ZONE_LABELS['Europe/London']}
            description="GMT in winter, BST in summer"
          />
          <Radio value="UTC" label={ZONE_LABELS.UTC} description="The PAS sends UTC all year" />
          <Radio
            value="offset"
            label="A fixed offset from UTC"
            description="The same offset all year, such as +01:00"
          />
          {stored ? (
            <Radio
              value={choice}
              label={`Kept as stored: ${choice}`}
              description="An IANA zone name the server knows"
              disabled
            />
          ) : null}
        </Stack>
      </Radio.Group>
      {choice === 'offset' ? (
        <TextInput
          id="site-feed-offset"
          label="Offset"
          description="+hh:mm or -hh:mm, up to 14:00"
          value={zone ?? ''}
          onChange={(e) => {
            const v = e.currentTarget.value;
            if (OFFSET.test(v)) setLastOffset(v);
            setZone(v);
          }}
          error={!OFFSET.test(zone ?? '') ? 'Write it as +01:00 or -03:30' : undefined}
          maw={220}
        />
      ) : null}
      {choice === '' ? (
        <Text size="sm" c="dimmed">
          Not answered: Shutter reads these times as UTC, as it did before the question existed.
        </Text>
      ) : null}
      <QuestionDetails
        keys={[['feed.time_zone', zone, 'UTC']]}
        more="An event time within an hour of a clock change can't be ordered safely, and the gate leaves it to a person. Every operation key carries the event time in UTC, so a change here gives new keys from the next message on: answer it before the first case, and not while cases are open."
      />
    </Section>
  );
}

function Model({ draft, setDraft }: { draft: SiteProfile; setDraft: SetDraft }) {
  return (
    <Section
      id="site-model"
      title="What the model sees"
      note="The model always gets tokens for the patient's identifiers, and never the patient's name, date of birth or address as fields."
    >
      <Question n={11} text="May the text of notes (OBX and NTE) go to the model?" acts />
      <Switch
        id="site-model_content-free_text"
        label="Send note text to the model"
        description="Off: the model learns that a note is present and whether it reads like an instruction, never what it says."
        checked={draft.model_content?.free_text === true}
        onChange={(e) => {
          const v = e.currentTarget.checked;
          setDraft((d) => {
            d.model_content = { ...(d.model_content ?? {}), free_text: v };
          });
        }}
      />
      <QuestionDetails
        keys={[['model_content.free_text', draft.model_content?.free_text, 'false']]}
        more="The tokens look like MRN-T1 and ENC-T1. On: the note text goes with the patient's identifiers, name and date of birth replaced by tokens, up to 500 characters (never a binary or reference value); it can still carry other people's names and clinical details."
      />
    </Section>
  );
}

function Merges({ draft, setDraft, problem }: { draft: SiteProfile; setDraft: SetDraft; problem: Problem }) {
  return (
    <Section
      id="site-merges-section"
      title="Merges"
      note="A merge (ADT^A40) changes which record a patient's history belongs to. By default Shutter never sends one."
    >
      <Question n={12} text="May Shutter ever send a merge (A40)?" acts />
      <Switch
        id="site-merges"
        label="Merges may be sent to receivers that take them"
        description="Off (the default): every merge is withheld and goes to a person."
        checked={draft.merges === 'allowed'}
        onChange={(e) => {
          const v = e.currentTarget.checked;
          setDraft((d) => {
            d.merges = v ? 'allowed' : 'forbidden';
          });
        }}
        error={problem?.path === 'merges' ? problem.message : undefined}
      />
      <QuestionDetails
        keys={[['merges', draft.merges, 'forbidden']]}
        more="A withheld merge goes to the team whose sending applications name the merge's source. On: a merge goes, gated and verified, only to a receiver whose entry takes merges."
      />
    </Section>
  );
}

function PreventFailures({
  draft,
  setDraft,
  problem,
}: {
  draft: SiteProfile;
  setDraft: SetDraft;
  problem: Problem;
}) {
  return (
    <Section
      id="site-prevent-failures"
      title="Prevent failures"
      note="Without its schema, IRIS still reads a message by segment position and delivers it, so a receiver can get misplaced values."
    >
      <Question
        n={13}
        text="Should Shutter hold the feed when a message arrives whose HL7 schema is not loaded here, until the schema is imported?"
        acts
      />
      <Switch
        id="site-feed-prevent_failures"
        label="Hold messages whose schema is not loaded"
        description="Off (the default): such a message is delivered as today, and Shutter steps in only when a delivery fails."
        checked={draft.feed?.prevent_failures === true}
        onChange={(e) => {
          const v = e.currentTarget.checked;
          setDraft((d) => {
            d.feed = { ...(d.feed ?? {}), prevent_failures: v };
          });
        }}
        error={problem?.path === 'feed.prevent_failures' ? problem.message : undefined}
      />
      <QuestionDetails
        keys={[['feed.prevent_failures', draft.feed?.prevent_failures, 'false']]}
        more="The risk is the interface, not one message. On: each such message is held as a case and nothing is sent; once the schema is imported and the inbound item's category set, the held cases are checked again and sent under the site's policy. A message that fails validation against a schema that is loaded is never held."
      />
    </Section>
  );
}

function CaseReminders({
  draft,
  setDraft,
  problem,
}: {
  draft: SiteProfile;
  setDraft: SetDraft;
  problem: Problem;
}) {
  const r = draft.reminders;
  const set = (fn: (x: Reminders) => void) =>
    setDraft((d) => {
      d.reminders = { ...(d.reminders ?? {}) };
      fn(d.reminders);
    });
  const err = (key: string) =>
    problem && problem.path.replace(/\[\d+\]$/, '') === `reminders.${key}` ? problem.message : undefined;
  const preview = reminderPreview(r);
  const text = (key: 'officer_name' | 'officer_address' | 'window_start' | 'window_end' | 'sign_in_url') => ({
    id: `site-reminders-${key}`,
    error: err(key),
    onChange: (e: ChangeEvent<HTMLInputElement>) => {
      const v = e.currentTarget.value;
      set((x) => {
        if (v) x[key] = v;
        else delete x[key];
      });
    },
  });
  const hours = (key: 'team_hours' | 'officer_hours') => ({
    id: `site-reminders-${key}`,
    min: 1,
    max: 720,
    allowDecimal: false,
    value: r?.[key] ?? REMINDER_DEFAULTS[key],
    error: err(key),
    onChange: (v: string | number) =>
      set((x) => {
        if (typeof v === 'number') x[key] = v;
      }),
  });
  return (
    <Section
      id="site-reminders"
      title="Reminders"
      note="A scheduled mail when a case that needs a person stays open. It writes to no receiver, calls no model and changes no case."
    >
      <Question n={14} text="Should anyone be reminded of cases left open?" acts />
      <Switch
        id="site-reminders-enabled"
        label="Send reminders for cases left open"
        description="Off (the default). On: the receiver's team first, then a named clinical officer, in the feed's time zone."
        checked={r?.enabled === true}
        onChange={(e) => {
          const v = e.currentTarget.checked;
          set((x) => {
            x.enabled = v;
          });
        }}
        error={err('enabled')}
      />
      {r?.enabled ? (
        <Stack gap="sm">
          <SimpleGrid cols={{ base: 1, sm: 2 }} spacing="sm">
            <NumberInput label="Team, after hours open" {...hours('team_hours')} />
            <NumberInput label="Officer, after hours open" {...hours('officer_hours')} />
            <TextInput label="Clinical officer" value={r.officer_name ?? ''} {...text('officer_name')} />
            <TextInput
              label="Officer's address"
              description="In an allowed mail domain"
              value={r.officer_address ?? ''}
              {...text('officer_address')}
            />
            <TextInput
              label="Window opens"
              type="time"
              value={r.window_start ?? REMINDER_DEFAULTS.window_start}
              {...text('window_start')}
            />
            <TextInput
              label="Window closes"
              type="time"
              value={r.window_end ?? REMINDER_DEFAULTS.window_end}
              {...text('window_end')}
            />
          </SimpleGrid>
          <Checkbox.Group
            id="site-reminders-days"
            label="Days"
            value={[...(r.days ?? REMINDER_DEFAULTS.days)]}
            onChange={(v) =>
              set((x) => {
                x.days = Object.keys(DAY_LABELS).filter((d) => v.includes(d));
              })
            }
            error={err('days')}
          >
            <Group gap="sm" mt={4}>
              {Object.entries(DAY_LABELS).map(([d, label]) => (
                <Checkbox key={d} value={d} label={label} />
              ))}
            </Group>
          </Checkbox.Group>
          <NativeSelect
            id="site-reminders-patient_detail"
            label="Patient detail in the mail"
            description="This mail goes out with nobody reviewing it. What it carries is your site's information governance decision."
            value={r.patient_detail ?? REMINDER_DEFAULTS.patient_detail}
            data={Object.entries(DETAIL_LABELS).map(([value, label]) => ({ value, label }))}
            onChange={(e) => {
              const v = e.currentTarget.value;
              set((x) => {
                x.patient_detail = v;
              });
            }}
            error={err('patient_detail')}
          />
          <TextInput
            label="Sign-in address"
            description="The link in the mail, such as https://shutter.example.nhs.uk/shutter/"
            value={r.sign_in_url ?? ''}
            {...text('sign_in_url')}
          />
        </Stack>
      ) : null}
      <TechDetail label="Preview with made-up patients" kind="explain">
        <Stack gap={4}>
          <Text size="sm">Nothing is sent from here.</Text>
          <Text size="sm" fw={600}>
            {preview.subject}
          </Text>
          <Text size="sm" style={{ whiteSpace: 'pre-line' }}>
            {preview.body}
          </Text>
        </Stack>
      </TechDetail>
      <QuestionDetails
        keys={[['reminders.enabled', r?.enabled, 'false']]}
        more="Cases awaiting approval, blocked, escalated or failed, abandoned ones aside. Each is reminded once per threshold. Nothing goes outside the window, so a case left overnight is in the first mail of the morning, and at most one mail an hour goes to anyone. Bank holidays aren't known. Never a full name, date of birth, address or NHS number. A failed send goes again at the next run."
      />
    </Section>
  );
}

/**
 * Questions 9 to 13: escalation teams and mail, the feed's time zone, note text for the model, merges, whether the
 * feed is held while a schema is missing; question 14: reminders for cases left open.
 */
export function MoreQuestions({
  draft,
  setDraft,
  problem,
}: {
  draft: SiteProfile;
  setDraft: SetDraft;
  problem: Problem;
}) {
  return (
    <>
      <Teams draft={draft} setDraft={setDraft} problem={problem} />
      <Feed draft={draft} setDraft={setDraft} problem={problem} />
      <Model draft={draft} setDraft={setDraft} />
      <Merges draft={draft} setDraft={setDraft} problem={problem} />
      <PreventFailures draft={draft} setDraft={setDraft} problem={problem} />
      <CaseReminders draft={draft} setDraft={setDraft} problem={problem} />
    </>
  );
}
