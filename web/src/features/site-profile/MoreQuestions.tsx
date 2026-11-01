import {
  Alert,
  Button,
  Checkbox,
  Fieldset,
  Group,
  Radio,
  SimpleGrid,
  Stack,
  Switch,
  Text,
  TextInput,
} from '@mantine/core';
import { IconPlus, IconTrash } from '@tabler/icons-react';
import { useState } from 'react';
import type { SiteProfile, SiteTeam } from '@/api/types';
import { Section } from '../cases/case/Section';
import { ZONE_LABELS, newTeam, parseList } from './profile';
import { Question } from './Question';

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
  const teams = draft.teams ?? [];
  const receivers = draft.receivers.map((r) => r.name);
  const err = (path: string) =>
    problem && problem.path.replace(/\[\d+\]$/, '') === path ? problem.message : undefined;
  return (
    <Section
      id="site-escalation"
      title="Escalation"
      note="Question 9. When Shutter can't recover a case, it drafts an email from the stored case for a person to check and send: identifiers, date of birth and the event, never a name, an address or note text."
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
          description="Every team mailbox and copy, and every address typed into an escalation, must be in one of these or a subdomain (nhs.net takes trust.nhs.net); empty allows none: a team mailbox needs a domain first"
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
    </Section>
  );
}

function Feed({ draft, setDraft, problem }: { draft: SiteProfile; setDraft: SetDraft; problem: Problem }) {
  const zone = draft.feed?.time_zone;
  // Not answered, one of the named zones, or an offset (an empty one is the offset field being cleared to retype)
  const choice = zone === undefined ? '' : zone in ZONE_LABELS ? zone : 'offset';
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
      note="Question 10. HL7 times that carry no offset (EVN-2, EVN-6, MSH-7, PV1-44) are read in this zone, and the gate orders and supersedes by them."
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
            description="GMT in winter, BST in summer; an event time within an hour of a clock change can't be ordered safely, and the gate leaves it to a person"
          />
          <Radio value="UTC" label={ZONE_LABELS.UTC} description="The PAS sends UTC all year" />
          <Radio
            value="offset"
            label="A fixed offset from UTC"
            description="The same offset all year, such as +01:00"
          />
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
      <Text size="xs" c="dimmed">
        Every operation key carries the event time in UTC, so a change here gives new keys from the next
        message on: answer it before the first case, and not while cases are open.
      </Text>
    </Section>
  );
}

function Model({ draft, setDraft }: { draft: SiteProfile; setDraft: SetDraft }) {
  return (
    <Section
      id="site-model"
      title="What the model sees"
      note="Question 11. The model always gets tokens for the patient's identifiers (MRN-T1, ENC-T1), and never the patient's name, date of birth or address as fields."
    >
      <Question n={11} text="May the text of notes (OBX and NTE) go to the model?" acts />
      <Switch
        id="site-model_content-free_text"
        label="Send note text to the model"
        description="Off: the model learns that a note is present and whether it reads like an instruction, never what it says. On: the text goes with the patient's identifiers, name and date of birth replaced by tokens, up to 500 characters (never a binary or reference value); it can still carry other people's names and clinical details"
        checked={draft.model_content?.free_text === true}
        onChange={(e) => {
          const v = e.currentTarget.checked;
          setDraft((d) => {
            d.model_content = { ...(d.model_content ?? {}), free_text: v };
          });
        }}
      />
    </Section>
  );
}

function Merges({ draft, setDraft, problem }: { draft: SiteProfile; setDraft: SetDraft; problem: Problem }) {
  return (
    <Section
      id="site-merges-section"
      title="Merges"
      note="Question 12. An ADT^A40 merge changes which record a patient's history belongs to. By default Shutter never sends one: the case goes to the team whose sending applications name the merge's source."
    >
      <Question n={12} text="May Shutter ever send a merge (A40)?" acts />
      <Switch
        id="site-merges"
        label="Merges may be sent to receivers that take them"
        description="Off (the default): every merge is withheld and goes to a person. On: a merge goes, gated and verified, only to a receiver whose entry takes merges"
        checked={draft.merges === 'allowed'}
        onChange={(e) => {
          const v = e.currentTarget.checked;
          setDraft((d) => {
            d.merges = v ? 'allowed' : 'forbidden';
          });
        }}
        error={problem?.path === 'merges' ? problem.message : undefined}
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
      note="Question 13. Without its schema, IRIS still reads a message by segment position and delivers it, so the receiver can get values read from the wrong place. The risk is the interface, not one message."
    >
      <Question
        n={13}
        text="Should Shutter hold the feed when a message arrives whose HL7 schema is not loaded here, until the schema is imported?"
        acts
      />
      <Switch
        id="site-feed-prevent_failures"
        label="Hold messages whose schema is not loaded"
        description="Off (the default): such a message is delivered as today, and Shutter steps in only when a delivery fails. On: each one is held as a case and nothing is sent; once the schema is imported and the inbound item's category set, the held cases are checked again and sent under the site's policy. A message that fails validation against a schema that is loaded is never held"
        checked={draft.feed?.prevent_failures === true}
        onChange={(e) => {
          const v = e.currentTarget.checked;
          setDraft((d) => {
            d.feed = { ...(d.feed ?? {}), prevent_failures: v };
          });
        }}
        error={problem?.path === 'feed.prevent_failures' ? problem.message : undefined}
      />
    </Section>
  );
}

/**
 * Questions 9 to 13: escalation teams and mail, the feed's time zone, note text for the model, merges, and whether the
 * feed is held while a schema is missing.
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
    </>
  );
}
