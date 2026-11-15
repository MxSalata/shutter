import { Alert, Anchor, Button, Card, Group, Stack, Tabs, Text, Title } from '@mantine/core';
import { useMediaQuery } from '@mantine/hooks';
import { IconPlus } from '@tabler/icons-react';
import { useEffect, useRef, useState, type ReactNode } from 'react';
import { Link, useBlocker, useNavigate, useSearchParams } from 'react-router';
import { saveLocked } from '@/api/saveLocked';
import { isAnswering, useCan, useMe, useSetupTurn, useSiteProfile } from '@/api/hooks';
import type { SetupTurnView, SiteProfileView } from '@/api/types';
import { ConfirmModal } from '@/components/ConfirmModal';
import { ErrorAlert } from '@/components/ErrorAlert';
import { KeyValueList } from '@/components/KeyValueList';
import { LockedNote } from '@/components/LockedSave';
import { PageHeader } from '@/components/PageHeader';
import { PageSkeleton } from '@/components/PageSkeleton';
import { StatusNotice } from '@/components/StatusBadge';
import { Timestamp } from '@/components/Timestamp';
import { TRIAL } from '@/env/mode';
import { usePageAccess } from '@/features/assistant/access';
import { ASK_HERE_EVENT, ASSISTANT_WIDE_QUERY } from '@/features/assistant/panel';
import { LiveUnavailableNotice } from '@/components/LiveUnavailableNotice';
import { describeError, isApiError } from '@/lib/errors';
import { plural } from '@/lib/format';
import { SITE_ICON } from '@/lib/hues';
import { checkDraft, describePath, isDemoPolicy, isShipped, problemField } from '../profile';
import { SaveBar } from '../SaveBar';
import { ASK_HERE_ID, cardTitleId, focusLater } from './cards';
import { TYPED_NOTE, draftingLine, useDrafting, type Drafting } from './drafting';
import { questionOfKey, type QuestionId } from './fields';
import { AskHere, SetupConversation } from './SetupConversation';
import { SetupDraftPane } from './SetupDraftPane';
import {
  changesOf,
  inForce,
  isDirty,
  progress,
  receiverOf,
  reviewStop,
  useSetup,
  type ReviewStop,
} from './setupStore';
import './setup.css';

/** The header's lead, one sentence: with the controls, and in the person's own words where Ask Shutter can read them. */
const LEAD =
  'Answer each question about a receiver with its control; nothing is saved until an approver reviews and saves.';
const LEAD_TYPED =
  'Answer each question about a receiver with its control, or in your own words where a question offers it.';

/** What stopped the last review, and the draft it was about: a later change to the draft clears it. */
type Stopped = { revision: number; stop?: ReviewStop; other?: { path: string; message: string } };

/** The four facts of the page's state, each in words. */
function StatusBand({ view, drafting }: { view: SiteProfileView; drafting: Drafting }) {
  const can = useCan();
  const access = usePageAccess();
  const locked = saveLocked(can);
  const shipped = isShipped(view.source);
  const enabled = view.profile.recovery?.mode === 'enabled';
  const explains =
    access.open && access.free
      ? 'Explains each question, live with the Explain agent.'
      : access.trial
        ? 'Explains each question in writing. Its suggested questions have sample answers.'
        : `Explains each question in writing. ${access.short}`;
  // What it does with a typed answer, in each state: said plainly, with no promise about what reaches the model
  const reads =
    drafting.state === 'on'
      ? 'It reads an answer typed in your own words and drafts the description, kind and tier for you to review.'
      : drafting.state === 'off'
        ? 'It does not read typed answers: that is switched off in the site profile.'
        : drafting.state === 'trial'
          ? 'It does not read typed answers in the trial.'
          : 'It cannot read typed answers now. The controls work without it.';
  return (
    <Card withBorder padding="md" component="section" aria-label="Where this page stands">
      <KeyValueList
        rows={[
          [
            'The profile in force',
            <Text size="sm" key="p">
              {shipped ? (
                `${isDemoPolicy(view.source) ? "Demo's answers" : 'Shipped answers'}, version ${view.version}. `
              ) : (
                <>
                  Version {view.version}, saved by {view.updatedBy || 'Setup'} on{' '}
                  <Timestamp iso={view.updatedAt} span inherit />.{' '}
                </>
              )}
              {enabled ? 'Recovery is enabled.' : 'Shadow mode: Shutter investigates and sends nothing.'}
            </Text>,
          ],
          ['Ask Shutter here', `${explains} ${reads}`],
          ...(drafting.can ? [['What you type', TYPED_NOTE] as [string, ReactNode]] : []),
          [
            'You',
            locked ? (
              <LockedNote key="l">{locked}</LockedNote>
            ) : TRIAL ? (
              'You can save. In the trial a save lasts until you reload or leave.'
            ) : (
              'You can save, through the review.'
            ),
          ],
        ]}
      />
    </Card>
  );
}

/** The start: add a receiver, or choose one of the profile's; the site-wide answers stay on the Site profile page. */
function StartList({ onOpen }: { onOpen: (rid: string) => void }) {
  const s = useSetup();
  if (!s.draft) return null;
  const rows = s.rids
    .map((rid, i) => ({ rid, r: s.draft!.receivers[i], added: !!s.added[rid] }))
    .sort((a, b) => Number(b.added) - Number(a.added));
  return (
    <Card withBorder padding="md" component="section" aria-labelledby="setup-start-title">
      <Stack gap="sm">
        <Title order={2} size="h3" id="setup-start-title">
          Choose a receiver
        </Title>
        <Group>
          <Button leftSection={<IconPlus size={16} aria-hidden />} onClick={() => onOpen(s.addReceiver())}>
            Add a receiver
          </Button>
        </Group>
        <ul className="setup-list" aria-label="The receivers in this draft">
          {rows.map(({ rid, r, added }) => {
            const name = r.name.trim() || 'New receiver, not named yet';
            const p = progress(s, rid);
            return (
              <li key={rid}>
                <Group justify="space-between" gap="sm" wrap="wrap">
                  <Text size="md" style={{ flex: '1 1 200px', minWidth: 0, overflowWrap: 'anywhere' }}>
                    <Text span fw={600} inherit>
                      {name}
                    </Text>
                    {added ? `: draft, ${p.answered} of ${p.total} answered` : ': in force'}
                  </Text>
                  <Button size="xs" variant="default" aria-label={`Open ${name}`} onClick={() => onOpen(rid)}>
                    Open
                  </Button>
                </Group>
              </li>
            );
          })}
        </ul>
        <Text size="sm">
          Site-wide answers (approvals, incidents, teams, mail, the feed and recovery mode) are on the{' '}
          <Anchor component={Link} to="/site-profile" inherit underline="always">
            Site profile page
          </Anchor>
          .
        </Text>
      </Stack>
    </Card>
  );
}

/** One pane of the workspace, named by its heading from the wide breakpoint and by its tab below it. */
function Pane({
  title,
  id,
  wide,
  children,
}: {
  title: string;
  id: string;
  wide: boolean;
  children: ReactNode;
}) {
  return wide ? (
    <Stack gap="md" component="section" aria-labelledby={id} className="setup-pane">
      <Title order={2} size="h3" id={id}>
        {title}
      </Title>
      {children}
    </Stack>
  ) : (
    <div className="setup-pane">{children}</div>
  );
}

function Setup({ view, drafting }: { view: SiteProfileView; drafting: Drafting }) {
  const s = useSetup();
  const open = s.open;
  useEffect(() => open(view), [open, view]);
  const can = useCan();
  const locked = saveLocked(can);
  const navigate = useNavigate();
  const wide = useMediaQuery(ASSISTANT_WIDE_QUERY, false, { getInitialValueInEffect: false });
  const [tab, setTab] = useState<string>('conversation');
  const [openId, setOpenId] = useState<QuestionId | null>(null);
  const [askOpen, setAskOpen] = useState(false);
  const [stopped, setStopped] = useState<Stopped | null>(null);
  const [discarding, setDiscarding] = useState(false);
  const shown = stopped && stopped.revision === s.revision ? stopped : null;

  // A link from the Site profile page names a receiver: the workspace opens on it, and the address forgets it
  const [search, setSearch] = useSearchParams();
  const wanted = search.get('receiver');
  const { draft, rids, focusOn } = s;
  useEffect(() => {
    if (wanted === null || !draft) return;
    const i = draft.receivers.findIndex((r) => r.name === wanted);
    if (i >= 0) focusOn(rids[i]);
    setSearch(
      (prev) => {
        const params = new URLSearchParams(prev);
        params.delete('receiver');
        return params;
      },
      { replace: true, preventScrollReset: true },
    );
  }, [wanted, draft, rids, focusOn, setSearch]);

  // The header's Ask Shutter button: on this page it goes to Ask Shutter in the conversation, and opens no panel
  useEffect(() => {
    const here = () => {
      setTab('conversation');
      setAskOpen(true);
      focusLater(ASK_HERE_ID);
    };
    window.addEventListener(ASK_HERE_EVENT, here);
    return () => window.removeEventListener(ASK_HERE_EVENT, here);
  }, []);

  // The turn Ask Shutter is reading, looked at every 2 s until it is answered or refused; what comes back enters the
  // draft only through the store's own re-check (settle)
  const pendingId = s.pending?.turnId;
  const turn = useSetupTurn(pendingId);
  const { settle } = s;
  useEffect(() => {
    if (!pendingId) return;
    if (turn.data && turn.data.turnId === pendingId && !isAnswering(turn.data.state)) settle(turn.data);
    else if (turn.isError)
      settle({
        turnId: pendingId,
        state: 'failed',
        error: `the answer could not be read (${describeError(turn.error)})`,
        turn: null,
      } as SetupTurnView);
  }, [pendingId, turn.data, turn.isError, turn.error, settle]);

  // Leaving with changes: asked once. The hand-over to the review is not a leave
  const dirty = isDirty(s);
  const handing = useRef(false);
  const asked = useRef(false);
  const blocker = useBlocker(
    ({ currentLocation, nextLocation }) =>
      dirty && !handing.current && !asked.current && nextLocation.pathname !== currentLocation.pathname,
  );

  if (!s.draft || !s.base) return <PageSkeleton label="Loading the site profile…" />;
  const changes = changesOf(s);
  const focus = s.focus && receiverOf(s, s.focus) ? s.focus : null;
  const r = focus ? receiverOf(s, focus)! : null;

  /** To a question's card: its receiver in the workspace, the conversation in view, the card open and in focus. */
  const goTo = (rid: string, q: QuestionId) => {
    s.focusOn(rid);
    setTab('conversation');
    setOpenId(q);
    focusLater(cardTitleId(q));
  };

  const review = () => {
    const state = useSetup.getState();
    const stop = reviewStop(state);
    if (stop) {
      setStopped({ revision: state.revision, stop });
      return goTo(stop.rid, stop.question);
    }
    const found = checkDraft(state.draft!);
    if (found) {
      const p = problemField(found) ?? { path: '', message: found };
      const m = /^receivers\[(\d+)\]\.(\w+)/.exec(p.path);
      const q = m ? questionOfKey(m[2]) : undefined;
      if (m && q) {
        const at = { rid: state.rids[Number(m[1])], question: q.id, message: p.message };
        setStopped({ revision: state.revision, stop: at });
        return goTo(at.rid, at.question);
      }
      return setStopped({ revision: state.revision, other: p });
    }
    // The existing review and save, on the Site profile page: its dialog opens at once on this draft
    handing.current = true;
    state.handOver();
    void navigate('/site-profile');
  };

  const problemAlert = shown ? (
    <Alert color="red" variant="light" role="alert" title="Check this answer">
      {shown.stop ? (
        <Anchor
          component="button"
          type="button"
          size="sm"
          onClick={() => goTo(shown.stop!.rid, shown.stop!.question)}
        >
          {shown.stop.message}
        </Anchor>
      ) : (
        <Text size="sm">
          {shown.other!.path ? `${describePath(shown.other!.path)}: ` : ''}
          {shown.other!.message}. This answer is on the{' '}
          <Anchor component={Link} to="/site-profile" inherit underline="always">
            Site profile page
          </Anchor>
          .
        </Text>
      )}
    </Alert>
  ) : null;

  const conversation = focus ? (
    <SetupConversation
      key={focus}
      rid={focus}
      openId={openId}
      setOpenId={setOpenId}
      stop={shown?.stop ?? null}
      drafting={drafting}
      onReview={review}
      onAnother={() => {
        setOpenId(null);
        s.focusOn(null);
        focusLater('setup-start-title');
      }}
      onDiscard={() => setDiscarding(true)}
      foot={<AskHere open={askOpen} setOpen={setAskOpen} />}
    />
  ) : null;
  const draftPane = focus ? <SetupDraftPane rid={focus} onEdit={(q) => goTo(focus, q)} /> : null;
  const p = focus ? progress(s, focus) : null;

  return (
    <Stack gap="lg">
      <StatusBand view={s.base} drafting={drafting} />
      {drafting.notice ? <LiveUnavailableNotice state={drafting.notice} /> : null}
      {s.moved ? (
        <StatusNotice tone="attention" title="The stored profile has changed">
          Version {view.version} was saved while this draft was being made from version {s.base.version}.
          Discard the draft to start from the answers now in force: a draft made from an older version cannot
          be saved.
        </StatusNotice>
      ) : null}
      {!focus || !r ? (
        <>
          <StartList
            onOpen={(rid) => {
              setOpenId(null);
              s.focusOn(rid);
              setTab('conversation');
            }}
          />
          <AskHere open={askOpen} setOpen={setAskOpen} />
        </>
      ) : (
        <Stack gap="md" component="section" aria-label={`Setting up ${r.name.trim() || 'a new receiver'}`}>
          <Group justify="space-between" gap="sm" wrap="wrap">
            <Text size="md" style={{ flex: '1 1 220px', minWidth: 0, overflowWrap: 'anywhere' }}>
              <Text span fw={600} inherit>
                {r.name.trim() || 'New receiver, not named yet'}
              </Text>
              {inForce(s, focus) ? ': in force' : `: draft, ${p!.answered} of ${p!.total} answered`}
            </Text>
            <Group gap="xs">
              {!inForce(s, focus) ? (
                <Button size="xs" variant="subtle" color="red" onClick={() => s.removeAdded(focus)}>
                  Remove from the draft
                </Button>
              ) : null}
              <Button
                size="xs"
                variant="default"
                onClick={() => {
                  setOpenId(null);
                  s.focusOn(null);
                }}
              >
                All receivers
              </Button>
            </Group>
          </Group>
          {wide ? (
            <div className="setup-panes">
              <Pane title="Conversation" id="setup-conversation-title" wide>
                {conversation}
              </Pane>
              <Pane title="Draft" id="setup-draft-title" wide>
                {draftPane}
              </Pane>
            </div>
          ) : (
            <Tabs value={tab} onChange={(v) => setTab(v ?? 'conversation')} keepMounted>
              <Tabs.List aria-label="The conversation and the draft">
                <Tabs.Tab value="conversation">Conversation</Tabs.Tab>
                <Tabs.Tab value="draft">
                  Draft{changes.length ? ` (${plural(changes.length, 'change')})` : ''}
                </Tabs.Tab>
              </Tabs.List>
              <Tabs.Panel value="conversation" pt="md">
                <Pane title="Conversation" id="setup-conversation-title" wide={false}>
                  {conversation}
                </Pane>
              </Tabs.Panel>
              <Tabs.Panel value="draft" pt="md">
                <Pane title="Draft" id="setup-draft-title" wide={false}>
                  {draftPane}
                </Pane>
              </Tabs.Panel>
            </Tabs>
          )}
        </Stack>
      )}
      {!dirty ? problemAlert : null}
      {dirty ? (
        <SaveBar
          count={changes.length}
          onReview={review}
          onDiscard={() => setDiscarding(true)}
          discardLabel="Discard the draft"
          reviewLabel="Review and save…"
          alert={problemAlert}
          note={
            locked ? (
              <LockedNote>{locked}</LockedNote>
            ) : TRIAL ? (
              <Text size="sm" c="dimmed">
                A save lasts until you reload or leave.
              </Text>
            ) : null
          }
        />
      ) : null}
      {discarding ? (
        <ConfirmModal opened chip={false} title="Discard this draft?" onClose={() => setDiscarding(false)}>
          <Stack gap="md">
            <Text size="md">Nothing has been saved, and nothing will be.</Text>
            <Group justify="flex-end" gap="sm">
              <Button variant="default" onClick={() => setDiscarding(false)}>
                Keep the draft
              </Button>
              <Button
                color="red"
                onClick={() => {
                  setDiscarding(false);
                  setOpenId(null);
                  setStopped(null);
                  s.discard();
                }}
              >
                Discard the draft
              </Button>
            </Group>
          </Stack>
        </ConfirmModal>
      ) : null}
      {blocker.state === 'blocked' ? (
        <ConfirmModal opened chip={false} title="Leave Set up the site?" onClose={() => blocker.reset()}>
          <Stack gap="md">
            <Text size="md">
              The draft is not saved. It stays in this tab until you reload or sign out, and nothing is stored
              until an approver reviews and saves it.
            </Text>
            <Group justify="flex-end" gap="sm">
              <Button variant="default" onClick={() => blocker.reset()}>
                Stay
              </Button>
              <Button
                onClick={() => {
                  asked.current = true;
                  blocker.proceed();
                }}
              >
                Leave
              </Button>
            </Group>
          </Stack>
        </ConfirmModal>
      ) : null}
    </Stack>
  );
}

/**
 * Set up the site: one receiver at a time, as a checklist of questions answered with the page's own controls, with the
 * profile building up beside it. Nothing is stored from here: the draft lives in this tab, and "Review and save…" hands
 * it to the Site profile page's review and its save.
 */
export default function SetupPage() {
  const view = useSiteProfile();
  const me = useMe();
  // Whether Ask Shutter reads typed answers here is the stored profile's own switch, then the reader's rights
  const drafting = useDrafting(view.data ?? null);
  return (
    <>
      <PageHeader
        title="Set up the site"
        icon={SITE_ICON}
        hue="teal"
        lead={drafting.can ? LEAD_TYPED : LEAD}
        meta={
          view.data && !me.isPending ? (
            <Text size="sm" c="dimmed" data-testid="setup-ask-shutter-does">
              {draftingLine(drafting)}
            </Text>
          ) : null
        }
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
      {view.data && !me.isPending ? <Setup view={view.data} drafting={drafting} /> : null}
    </>
  );
}
