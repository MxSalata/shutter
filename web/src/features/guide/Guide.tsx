import {
  ActionIcon,
  Affix,
  Badge,
  Button,
  type ButtonProps,
  Group,
  Menu,
  Modal,
  Paper,
  Radio,
  SimpleGrid,
  Stack,
  Text,
  Title,
  VisuallyHidden,
} from '@mantine/core';
import { useMediaQuery, useReducedMotion } from '@mantine/hooks';
import {
  IconArrowDown,
  IconArrowLeft,
  IconArrowRight,
  IconCheck,
  IconChevronDown,
  IconDoorExit,
  IconList,
  IconPlayerPlay,
  IconPlayerSkipForward,
  IconX,
} from '@tabler/icons-react';
import { autoUpdate, computePosition, flip, offset, shift } from '@floating-ui/react';
import { useQueryClient } from '@tanstack/react-query';
import {
  useEffect,
  useEffectEvent,
  useLayoutEffect,
  useRef,
  useState,
  type ComponentPropsWithoutRef,
  type RefObject,
} from 'react';
import { createPortal } from 'react-dom';
import { useLocation, useNavigate } from 'react-router';
import { api, newIdempotencyKey, seg } from '@/api/client';
import { keys, useCan, useCase } from '@/api/hooks';
import type { CaseDetail, CaseState, PlanView } from '@/api/types';
import { TechDetail } from '@/components/TechDetail';
import { ENV } from '@/env/mode';
import { compactBanner } from '@/trial/visit';
import { REPLAY_DONE } from '@/lib/events';
import { HOSPITAL_NAME } from '@/lib/hospital';
import { guideCard, guideTarget, useGuideDock } from '@/lib/guideDock';
import { useLeaveTrial } from '@/trial/leave';
import { onRoute, positionOf, stepsIn, welcomeDue, type GuidePosition } from './controller';
import { resolvePlace, usePlace } from './places';
import {
  CHAPTERS,
  SCOPE_FINISH,
  SCOPE_LABELS,
  SCOPE_OVERLINE,
  SCOPES,
  stepAt,
  stepForRole,
  tourMinutes,
  welcomeActions,
  type ChapterGroup,
  type GuideScope,
  type GuideStep,
} from './registry';
import {
  bringIntoFreePart,
  clearNotch,
  focusFrom,
  landOn,
  pageHeading,
  useMenuHandOver,
  waitForTarget,
} from './reveal';
import { useGuide, type GuidePhase } from './store';
import { useAssistant } from '@/features/assistant/store';

/**
 * The first-run guide, in the trial only: the welcome with its three routes, then one step at a time in an inline card
 * placed just before the section it is about (so it never covers it, and the reading and tab order are the card, then
 * the section), then the finish card. Its movements play one at a time (DESIGN.md 6.2): the card rises in; then its
 * notch nudges toward the section while the section's ring pulses; then, once the control a step invites the reader to
 * try is at least half in view, a pointer beside it and a halo on it. Nothing moves under reduced motion: everything
 * stands in its resting, pointing state at once.
 */

/** The comment an approval the tour makes for the reader carries (Next on the S2 decision step). */
export const APPROVED_FOR_YOU = "Approved for you by the trial's tour";
export { REPLAY_DONE };

const ENTRANCE_MS = 220;
const RING_MS = 1600 * 2;
const LATEST_START_MS = 5000;

/** The guide's buttons: at least 44 px high, for touch. */
function GuideButton({
  className,
  ...props
}: ButtonProps & Omit<ComponentPropsWithoutRef<'button'>, keyof ButtonProps>) {
  // A menu's target passes its own class: keep the 44 px rule's beside it
  return <Button className={className ? `guide-control ${className}` : 'guide-control'} {...props} />;
}

const tryControl = (action: string) => document.querySelector<HTMLElement>(`[data-tour-action="${action}"]`);
const visible = (el: HTMLElement | null): el is HTMLElement =>
  !!el && el.isConnected && (typeof el.checkVisibility !== 'function' || el.checkVisibility());
/** A control that is there to try: on the page, not greyed out for this role, and not already open (Ask about this case, once pressed). */
const toTry = (action: string) => {
  const el = tryControl(action);
  return visible(el) && !el.matches(':disabled') && el.getAttribute('aria-expanded') !== 'true';
};

/** The filters a list keeps in its address: choosing one during a step leaves the reader on the step's page. */
const LIST_FILTERS: Record<string, string[]> = {
  '/cases': ['state', 'outcome', 'scenario', 'page', 'open', 'resolved'],
  '/scenarios': ['mode', 'outcome'],
};

/**
 * The address's query without Ask's own `ask=1` or a list's filters: opening Ask about this case keeps the reader on the
 * step's page, so the card stays (in the dock beside Ask below 1200 px, lib/guideDock.ts).
 */
function withoutOwnParams(pathname: string, search: string): string {
  if (!search) return search;
  const q = new URLSearchParams(search);
  for (const name of ['ask', ...(LIST_FILTERS[pathname] ?? [])]) q.delete(name);
  const rest = q.toString();
  return rest ? `?${rest}` : '';
}

/** Brings a control into view and focuses it. */
function bringToHand(el: HTMLElement, reduced: boolean) {
  bringIntoFreePart(el, reduced);
  el.focus({ preventScroll: true });
}

const overline = (pos: GuidePosition, scope: GuideScope) =>
  `${SCOPE_OVERLINE[scope]} · ${pos.chapter.title}${scope !== 'quick' && pos.chapter.code ? ` (${pos.chapter.code})` : ''}`;

const sentence = (s: string) => s.charAt(0).toLowerCase() + s.slice(1);

// ---- the welcome ----

const SCOPE_WORDS: Record<GuideScope, () => string> = {
  quick: () =>
    `${SCOPES.quick.length} steps, about ${tourMinutes('quick')} min. S2, S3, then S8: a transfer delivered, one already there, a fix held back, and the proof.`,
  all: () =>
    `${SCOPES.all.length} steps in ${new Set(SCOPES.all.map((p) => p.split('/')[0])).size} chapters, about ${tourMinutes('all')} min.`,
  engineer: () =>
    `${SCOPES.engineer.length} steps, about ${tourMinutes('engineer')} min, technical detail on: the receipt, the gate's codes, what each agent cited, the message trace.`,
};

/**
 * Where the welcome's Start with S2 leads: the short route's start, as Home's own Start with S2 has it (HomePage,
 * START_S2; Guide.test holds the two to one address). The Scenarios page opens in Board mode on S2's card with its Run
 * focused, and nothing is pressed. Written here and not imported, so the trial's chunk does not come to depend on Home's.
 */
export const WELCOME_START_S2 = '/scenarios?mode=board&start=S2';

function Welcome({ initial, onStartS2 }: { initial: GuideScope; onStartS2: () => void }) {
  const can = useCan();
  const begin = useGuide((s) => s.begin);
  const notNow = useGuide((s) => s.notNow);
  const dontShowAgain = useGuide((s) => s.dontShowAgain);
  const [scope, setScope] = useState<GuideScope>(initial);
  return (
    <Stack gap="md">
      <Text fz={18}>
        When a patient movement fails to reach another system, Shutter finds out why and writes a fix only
        once its checks pass.
      </Text>
      <Text fz={15}>
        {HOSPITAL_NAME}: a demo hospital with made-up patients, recorded. {welcomeActions(can)}: each replays
        the recording, and nothing leaves this browser. A reload starts the recording afresh.
      </Text>
      <Radio.Group value={scope} onChange={(v) => setScope(v as GuideScope)} label="Choose a tour">
        <SimpleGrid cols={{ base: 1, sm: 3 }} spacing="sm" mt="xs">
          {(['quick', 'all', 'engineer'] as const).map((s) => (
            <Radio.Card key={s} value={s} className="guide-scope-card" p="sm" radius="md">
              <Group gap="sm" wrap="nowrap" align="flex-start">
                <Radio.Indicator color="grape" />
                <div>
                  <Text fw={600}>{SCOPE_LABELS[s]}</Text>
                  <Text size="sm">{SCOPE_WORDS[s]()}</Text>
                </div>
              </Group>
            </Radio.Card>
          ))}
        </SimpleGrid>
      </Radio.Group>
      <Group gap="sm" wrap="wrap">
        <GuideButton
          color="grape"
          leftSection={<IconPlayerPlay size={16} aria-hidden />}
          onClick={() => begin(scope)}
          data-autofocus
        >
          Start the tour
        </GuideButton>
        {/* The short route without the tour, for a role that may run a scenario: S2's Run is then the next choice */}
        {can.scenarios ? (
          <GuideButton variant="light" color="grape" onClick={onStartS2}>
            Start with S2
          </GuideButton>
        ) : null}
        <GuideButton variant="default" onClick={notNow}>
          Explore on my own
        </GuideButton>
      </Group>
      {can.scenarios ? (
        <Text size="sm">
          Start with S2 skips the tour: it opens the first scenario, a failed transfer recovered, with its Run
          ready. Nothing runs until you press it.
        </Text>
      ) : null}
      <div>
        <Button variant="subtle" color="gray" size="compact-sm" onClick={dontShowAgain}>
          Don&apos;t show again
        </Button>
      </div>
    </Stack>
  );
}

// ---- the movements ----

type Motion = 'waiting' | 'run' | 'rest';

/**
 * The pointer beside a control a step invites the reader to try: an arrow and "Try it", placed by Floating UI above
 * the control's start (flipped or shifted to stay on the screen), so it never covers the control or widens the page.
 * It writes its position straight to its own element as the page scrolls or resizes, with no render of its own.
 */
function TryItPointer({ control, motion }: { control: HTMLElement; motion: Motion }) {
  const ref = useRef<HTMLDivElement | null>(null);
  useEffect(() => {
    const pointer = ref.current;
    // Only where the page is laid out: jsdom (the component tests) has no layout, and no IntersectionObserver
    if (!pointer || typeof IntersectionObserver === 'undefined') return;
    const place = () =>
      void computePosition(control, pointer, {
        placement: 'top-start',
        strategy: 'absolute',
        middleware: [offset(10), flip(), shift({ padding: 8 })],
      }).then(({ x, y }) => {
        pointer.style.left = `${x}px`;
        pointer.style.top = `${y}px`;
      });
    return autoUpdate(control, pointer, place);
  }, [control]);
  return createPortal(
    <div
      ref={ref}
      style={{ position: 'absolute', left: 0, top: 0 }}
      className="guide-pointer guide-try-pointer"
      data-motion={motion}
      data-testid="guide-try-pointer"
      aria-hidden
    >
      <IconArrowDown size={16} />
      <span>Try it</span>
    </div>,
    document.body,
  );
}

/**
 * The step's movements, one at a time: the card's entrance; then the section's ring and the card's notch; then, for a
 * step that invites an action, the pointer and the control's halo, once the control is at least half in view and the
 * ring has played, or at once when the reader presses the card's chip. A movement that has not started 5 seconds after
 * the step opened appears in its resting state when its control comes into view. Under reduced motion all of them
 * stand at rest from the start.
 */
function useStepMotion(target: HTMLElement | null, action: string | undefined, reduced: boolean) {
  const [ring, setRing] = useState<Motion>('waiting');
  const [trying, setTrying] = useState<{ control: HTMLElement; motion: Motion } | null>(null);
  const started = useRef(0);

  // The ring and the notch, after the card's entrance
  useEffect(() => {
    if (!target) return;
    started.current = Date.now();
    const timer = window.setTimeout(
      () => {
        target.dataset.tourActive = 'true';
        if (reduced) target.dataset.motion = 'rest';
        setRing(reduced ? 'rest' : 'run');
      },
      reduced ? 0 : ENTRANCE_MS,
    );
    return () => {
      window.clearTimeout(timer);
      delete target.dataset.tourActive;
      delete target.dataset.motion;
      setRing('waiting');
    };
  }, [target, reduced]);

  // The try-it, once its control is in view
  useEffect(() => {
    if (!target || !action) return;
    let control: HTMLElement | null = null;
    let inView = typeof IntersectionObserver === 'undefined';
    let done = false;
    let observer: IntersectionObserver | null = null;
    const start = (motion: Motion) => {
      if (done || !control) return;
      done = true;
      control.dataset.tourTry = motion === 'run' ? 'true' : 'rest';
      setTrying({ control, motion });
    };
    // Once the reader has pressed the control, the pointer has done its work; the card's chip can bring it back
    const pressed = () => setTrying(null);
    const consider = () => {
      if (done || !control || !inView) return;
      const since = Date.now() - started.current;
      if (reduced || since >= LATEST_START_MS) start('rest');
      else if (since >= ENTRANCE_MS + RING_MS) start('run');
    };
    const find = window.setInterval(() => {
      // A control the page has taken away (the approval went through, the tab changed) leaves nothing to point at
      if (control && !control.isConnected) {
        observer?.disconnect();
        control = null;
        done = false;
        inView = typeof IntersectionObserver === 'undefined';
        setTrying(null);
      }
      if (!control) {
        const el = tryControl(action);
        if (!visible(el)) return;
        control = el;
        control.addEventListener('click', pressed);
        if (typeof IntersectionObserver !== 'undefined') {
          observer = new IntersectionObserver(
            (entries) => {
              inView = entries.some((e) => e.intersectionRatio >= 0.5);
              consider();
            },
            { threshold: 0.5 },
          );
          observer.observe(control);
        }
      }
      consider();
    }, 100);
    const press = () => {
      if (!control) control = tryControl(action);
      if (!control) return;
      bringToHand(control, reduced);
      const motion = reduced ? 'rest' : 'run';
      if (!done) start(motion);
      else setTrying({ control, motion });
    };
    pressers.set(action, press);
    return () => {
      window.clearInterval(find);
      observer?.disconnect();
      pressers.delete(action);
      if (control) {
        control.removeEventListener('click', pressed);
        delete control.dataset.tourTry;
      }
      setTrying(null);
    };
  }, [target, action, reduced]);

  return { ring, trying };
}

/** The card's try-it chip presses through here, so the pointer starts at once (useStepMotion registers it). */
const pressers = new Map<string, () => void>();

// ---- a step ----

/** Approves the held case for the reader, through the same call Approve the resend makes, when it still waits. */
async function approveForYou(caseId: string): Promise<boolean> {
  const c = await api.get<CaseDetail>(`/cases/${seg(caseId)}`);
  if (c.state !== 'awaiting_approval') return false;
  const view = await api.get<PlanView>(`/cases/${seg(caseId)}/plan`);
  await api.post(
    `/cases/${seg(caseId)}/approvals`,
    {
      decision: 'approve',
      planDigest: view.plan.digest,
      expectedVersion: c.version,
      comment: APPROVED_FOR_YOU,
    },
    { idempotencyKey: newIdempotencyKey() },
  );
  return true;
}

/** The case's id in a step's address. */
const caseInPath = (path: string | undefined) => {
  const id = /^\/cases\/([^?]+)/.exec(path ?? '')?.[1];
  return id ? decodeURIComponent(id) : undefined;
};

/** The state of the case a step's words depend on; for any other step, none, and nothing more is read. */
function useStepCaseState(step: GuideStep | undefined): CaseState | undefined {
  const place = usePlace(step);
  const id = caseInPath(place.data && 'path' in place.data ? place.data.path : undefined);
  return useCase(id ?? '', !!id && !!step?.whenCase).data?.state;
}

/**
 * The case page's replay after a trial approval, awaited by the step after it, for at most 3 seconds. Set only for an
 * approval the tour made: an approval the reader made by hand has no step waiting for it.
 */
let replay: Promise<void> | null = null;
function awaitReplay() {
  replay = new Promise<void>((resolve) => {
    const timer = window.setTimeout(resolve, 3000);
    window.addEventListener(
      REPLAY_DONE,
      () => {
        window.clearTimeout(timer);
        resolve();
      },
      { once: true },
    );
  });
}

function MoreMenu() {
  const skipChapter = useGuide((s) => s.skipChapter);
  const openChapters = useGuide((s) => s.openChapters);
  const exit = useGuide((s) => s.exit);
  const { menu, handOver } = useMenuHandOver();
  return (
    <Menu position="top" withinPortal shadow="md" {...menu}>
      <Menu.Target>
        <GuideButton variant="default" rightSection={<IconChevronDown size={16} aria-hidden />}>
          More
        </GuideButton>
      </Menu.Target>
      <Menu.Dropdown>
        <Menu.Item leftSection={<IconPlayerSkipForward size={16} aria-hidden />} onClick={skipChapter}>
          Skip chapter
        </Menu.Item>
        <Menu.Item leftSection={<IconList size={16} aria-hidden />} onClick={handOver(openChapters)}>
          Choose a chapter
        </Menu.Item>
        <Menu.Item leftSection={<IconX size={16} aria-hidden />} onClick={exit}>
          Exit guide
        </Menu.Item>
      </Menu.Dropdown>
    </Menu>
  );
}

function StepCard({
  pos,
  path,
  ring,
  notFound,
  docked,
  titleRef,
}: {
  pos: GuidePosition;
  path: string | undefined;
  ring: Motion;
  notFound: boolean;
  /** In the dock beside Ask, not before its section: no notch pointing down at it. */
  docked: boolean;
  titleRef: RefObject<HTMLHeadingElement | null>;
}) {
  const scope = useGuide((s) => s.progress.scope);
  const approvedForYou = useGuide((s) => s.approvedForYou);
  const next = useGuide((s) => s.next);
  const back = useGuide((s) => s.back);
  const exit = useGuide((s) => s.exit);
  const client = useQueryClient();
  const reduced = useReducedMotion() ?? false;
  const [busy, setBusy] = useState(false);
  const step = stepForRole(pos.step, useCan(), useStepCaseState(pos.step));
  const tryAction = step.tryIt?.action;
  const chipAction = step.chip?.action;
  const [present, setPresent] = useState<{ tryIt: boolean; chip: boolean }>({ tryIt: false, chip: false });

  // The chips show only while their control is on the page and not already open: the try-it never leads nowhere
  useEffect(() => {
    const look = () =>
      setPresent({
        tryIt: !!tryAction && toTry(tryAction),
        chip: !!chipAction && toTry(chipAction),
      });
    look();
    const timer = window.setInterval(look, 500);
    return () => window.clearInterval(timer);
  }, [tryAction, chipAction]);

  const onNext = async () => {
    // Next without trying on the S2 decision: the tour never lands on an unverified case, so it approves for you
    const caseId = caseInPath(path);
    if (step.tryIt?.action === 'approve-plan' && caseId) {
      setBusy(true);
      try {
        awaitReplay();
        const approved = await approveForYou(caseId);
        await client.invalidateQueries({ queryKey: keys.case(caseId) });
        next(approved);
      } catch {
        next();
      } finally {
        setBusy(false);
      }
      return;
    }
    next();
  };

  return (
    <Paper
      className="guide-card guide-card-enter"
      role="region"
      aria-label="Guide"
      withBorder
      shadow={docked ? 'lg' : 'sm'}
      p="md"
      maw={720}
      data-guide-card
      data-docked={docked || undefined}
      onKeyDown={(e) => {
        if (e.key === 'Escape') exit();
      }}
    >
      <Stack gap="xs">
        <Group justify="space-between" wrap="nowrap" gap="xs">
          <Text className="guide-overline">{overline(pos, scope)}</Text>
          <Group gap="xs" wrap="nowrap">
            <Text size="sm" fw={600} style={{ whiteSpace: 'nowrap' }}>
              Step {pos.n} of {pos.m}
            </Text>
            <ActionIcon variant="subtle" color="gray" size="lg" aria-label="Exit guide" onClick={exit}>
              <IconX size={18} aria-hidden />
            </ActionIcon>
          </Group>
        </Group>
        <div className="guide-progress" aria-hidden>
          <div style={{ width: `${(pos.n / pos.m) * 100}%` }} />
        </div>
        {approvedForYou === pos.path ? (
          <Group gap={6} className="guide-approved">
            <IconCheck size={16} aria-hidden />
            <Text size="sm" fw={600}>
              Approved for you, in the trial.
            </Text>
          </Group>
        ) : null}
        {notFound ? (
          <Text size="sm" c="dimmed">
            This section is not on the page just now.
          </Text>
        ) : null}
        <Title order={2} fz={22} tabIndex={-1} ref={titleRef} className="guide-title">
          {step.title}
        </Title>
        <Text fz={18} className="guide-say">
          {step.say}
        </Text>
        {step.tryIt && present.tryIt ? (
          <div>
            <Button
              color="grape"
              variant="light"
              className="guide-control guide-try-chip"
              leftSection={<IconArrowRight size={16} aria-hidden />}
              onClick={() => pressers.get(step.tryIt!.action)?.()}
            >
              {step.tryIt.text}
            </Button>
          </div>
        ) : null}
        {step.chip && present.chip ? (
          <div>
            <Button
              variant="subtle"
              color="grape"
              size="compact-sm"
              onClick={() => {
                const el = tryControl(step.chip!.action);
                if (el) bringToHand(el, reduced);
              }}
            >
              {step.chip.text}
            </Button>
          </div>
        ) : null}
        {step.detail ? (
          <TechDetail kind="data" label="Technical detail">
            <Text size="sm">{step.detail}</Text>
          </TechDetail>
        ) : null}
        <Group justify="space-between" gap="sm" wrap="wrap" mt={4}>
          <GuideButton
            variant="default"
            leftSection={<IconArrowLeft size={16} aria-hidden />}
            onClick={back}
            disabled={pos.first}
          >
            Back
          </GuideButton>
          <Group gap="sm" wrap="nowrap">
            <MoreMenu />
            <GuideButton
              color="grape"
              rightSection={
                pos.last ? <IconCheck size={16} aria-hidden /> : <IconArrowRight size={16} aria-hidden />
              }
              onClick={() => void onNext()}
              loading={busy}
            >
              {pos.last ? 'Finish' : 'Next'}
            </GuideButton>
          </Group>
        </Group>
      </Stack>
      {notFound || docked ? null : (
        <div className="guide-pointer guide-notch" data-motion={ring} aria-hidden>
          <IconArrowDown size={20} />
        </div>
      )}
    </Paper>
  );
}

/** Opens the step's page (and its story step or tab), waits for its section, and places the card just before it. */
function StepHost({ pos }: { pos: GuidePosition }) {
  const place = usePlace(pos.step);
  const navigate = useNavigate();
  const location = useLocation();
  const here = location.pathname + withoutOwnParams(location.pathname, location.search);
  // The same address again still counts: the case page reopens its story step on every visit
  // A step on the page already showing scrolls from where the last one left it, not by way of the page's top
  // A step that is not about Ask closes the Ask Shutter panel as it opens its page, so the step's section is in sight
  const askStep = pos.step.target === 'case-ask';
  const go = useEffectEvent((to: string) => {
    if (!askStep) useAssistant.getState().setOpen(false);
    navigate(to, {
      replace: here === to,
      preventScrollReset: to.split('?')[0] === location.pathname,
    });
  });
  const reduced = useReducedMotion() ?? false;
  const [host, setHost] = useState<HTMLElement | null>(null);
  const [target, setTarget] = useState<HTMLElement | null>(null);
  const [absent, setAbsent] = useState(false);
  const titleRef = useRef<HTMLHeadingElement | null>(null);
  const path = place.data && 'path' in place.data ? place.data.path : undefined;
  // A safeguard only: in the trial every place of the quick tour resolves (guide.spec.ts checks it)
  const notFound = absent || (!!place.data && 'missing' in place.data);
  const caseState = useStepCaseState(pos.step);
  const tryAction = stepForRole(pos.step, useCan(), caseState).tryIt?.action;
  const { ring, trying } = useStepMotion(target, tryAction, reduced);
  // Read when the card is placed, not a reason to place it again
  const reducedNow = useRef(reduced);
  const tryNow = useRef(tryAction);
  useEffect(() => {
    reducedNow.current = reduced;
    tryNow.current = tryAction;
  }, [reduced, tryAction]);

  useEffect(() => {
    if (path) go(path);
  }, [path]);

  // Approve the resend pressed by hand on this step: once the replay has played, the tour goes on to what it shows, so the
  // reader isn't left on a card that still says it is their turn. Next's own approval moves on by itself
  // Read from the step itself: the case resolves before the replay ends, and the words for that drop the try-it
  const approveStep = pos.step.tryIt?.action === 'approve-plan';
  useEffect(() => {
    if (!approveStep) return;
    const played = (e: Event) => {
      if (!replay && (e as CustomEvent<string>).detail === caseInPath(path)) useGuide.getState().next();
    };
    window.addEventListener(REPLAY_DONE, played);
    return () => window.removeEventListener(REPLAY_DONE, played);
  }, [approveStep, path]);

  // Reject the resend pressed by hand on this step: the page has closed up around the decision, so the tour goes on to what it
  // means and lands there, as it does after the replay of an approval. Arriving on a case rejected earlier stays put
  const stateBefore = useRef(caseState);
  useEffect(() => {
    const before = stateBefore.current;
    stateBefore.current = caseState;
    if (approveStep && before === 'awaiting_approval' && caseState === 'blocked') useGuide.getState().next();
  }, [approveStep, caseState]);

  // The page learns what the step points at before the step looks for it, so a folded section can open for it
  useEffect(() => {
    guideTarget.set(pos.step.target);
    return () => guideTarget.set(null);
  }, [pos.step.target]);

  // Only once the address is the step's: until then the page before it, with its own sections, is still showing
  const arrived = !!path && here === path;
  const placed = useRef(false);
  useEffect(() => {
    if (!arrived || placed.current) return;
    placed.current = true;
    let cancelled = false;
    let made: HTMLElement | null = null;
    let stopLanding: (() => void) | null = null;
    void (async () => {
      const section = await waitForTarget(pos.step.target);
      // A step that invites a press sits just above its control, when the role and the case still offer it
      const near =
        section && tryNow.current && pos.step.nearTry ? await waitForTarget(pos.step.nearTry, 2000) : null;
      const el = near ?? section;
      // The step after an approval waits for the case page's replay to finish, for at most 3 seconds
      if (replay) {
        await replay;
        replay = null;
      }
      if (cancelled) return;
      if (!el) {
        setAbsent(true);
        return;
      }
      // A story step opening below its heading moves the page: give its panel a moment before scrolling
      if (!reducedNow.current) await new Promise((r) => window.setTimeout(r, 250));
      if (cancelled) return;
      made = document.createElement('div');
      made.className = 'guide-host';
      made.dataset.guideHost = 'true';
      if (near) made.dataset.guideNear = 'true';
      el.insertAdjacentElement('beforebegin', made);
      setHost(made);
      setTarget(el);
      stopLanding = landOn(made, reducedNow.current);
    })();
    // Leaving the page ends the step's showing; coming back by hand does not show it again
    return () => {
      cancelled = true;
      stopLanding?.();
      made?.remove();
      if (!made) placed.current = false;
      setHost(null);
      setTarget(null);
    };
  }, [arrived, pos.step.target, pos.step.nearTry]);

  // While the card is on the page, Ask about this case opens as a sheet beside it, offering the dock it moves into
  const dock = useGuideDock();
  const docked = !!host && !!dock;
  useEffect(() => {
    if (!host) return;
    guideCard.set(true);
    return () => guideCard.set(false);
  }, [host]);

  // The card's notch points at the section without reaching its ring: measured once the card is in its host, and again
  // when the window's size changes the room the page leaves between them
  useLayoutEffect(() => {
    if (!host || docked || notFound) return;
    const clear = () => clearNotch(host);
    clear();
    window.addEventListener('resize', clear);
    return () => window.removeEventListener('resize', clear);
  }, [host, docked, notFound]);

  // Focus moves to the card's title on every step
  useEffect(() => {
    if (!host && !notFound) return;
    const timer = window.setTimeout(() => {
      if (titleRef.current) focusFrom(titleRef.current);
    }, 0);
    return () => window.clearTimeout(timer);
  }, [host, notFound]);

  const card = (
    <StepCard pos={pos} path={path} ring={ring} notFound={notFound} docked={docked} titleRef={titleRef} />
  );
  return (
    <>
      {docked && dock ? createPortal(card, dock) : host?.isConnected ? createPortal(card, host) : null}
      {!host && notFound ? (
        <Affix position={{ bottom: 16, right: 16, left: 16 }} zIndex={150}>
          {card}
        </Affix>
      ) : null}
      {/* Once Ask is open its pointer has done its work; the halo's outline stays on the button */}
      {trying && !docked ? <TryItPointer control={trying.control} motion={trying.motion} /> : null}
    </>
  );
}

// ---- the chapters, the finish and the pointer with no card ----

const GROUPS: ChapterGroup[] = ['Operate', 'Results', 'Configure'];

function Chapters() {
  const progress = useGuide((s) => s.progress);
  const choose = useGuide((s) => s.chooseChapter);
  const exit = useGuide((s) => s.exit);
  const pos = positionOf(progress);
  return (
    <Stack gap="sm">
      <Group gap="md" aria-hidden className="guide-legend">
        <Group gap={6}>
          <span className="guide-dot" data-kind="quick" />
          <Text size="sm">Quick tour</Text>
        </Group>
        <Group gap={6}>
          <span className="guide-dot" data-kind="engineer" />
          <Text size="sm">Engineers&apos; tour</Text>
        </Group>
      </Group>
      {GROUPS.map((group) => {
        const chapters = CHAPTERS.filter((c) => c.group === group && onRoute(c.id, 'all'));
        return (
          <div key={group} role="group" aria-labelledby={`guide-group-${group}`}>
            <Text id={`guide-group-${group}`} className="nav-group-label" tt="uppercase" mb={4}>
              {group}
            </Text>
            <Stack gap={4} component="ul" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
              {chapters.map((c) => {
                const done = progress.completed.includes(c.id);
                const current = pos?.chapter.id === c.id;
                const n = stepsIn(c.id, progress.scope);
                return (
                  <li key={c.id}>
                    <GuideButton
                      variant={current ? 'light' : 'default'}
                      color={current ? 'grape' : undefined}
                      fullWidth
                      justify="space-between"
                      onClick={() => choose(c.id)}
                      // Its name in words: the chapter, its steps on this route, finished, and Current
                      aria-label={`${c.title}${c.code ? ` (${c.code})` : ''} ${n === 1 ? '1 step' : `${n} steps`}${done ? ' (finished)' : ''}${current ? ' Current' : ''}`}
                      leftSection={
                        <Group gap={4} wrap="nowrap" w={22}>
                          {onRoute(c.id, 'quick') ? <span className="guide-dot" data-kind="quick" /> : null}
                          {onRoute(c.id, 'engineer') ? (
                            <span className="guide-dot" data-kind="engineer" />
                          ) : null}
                        </Group>
                      }
                      rightSection={
                        <Group gap={6} wrap="nowrap">
                          {done ? <IconCheck size={16} aria-hidden /> : null}
                          {current ? (
                            <Badge size="sm" color="grape" variant="light" style={{ textTransform: 'none' }}>
                              Current
                            </Badge>
                          ) : null}
                        </Group>
                      }
                      styles={{ label: { flex: 1, justifyContent: 'space-between', gap: 8 } }}
                    >
                      <span>
                        {c.title}
                        {c.code ? ` (${c.code})` : ''}
                      </span>
                      <Text span size="sm" c="dimmed" fw={400}>
                        {n === 1 ? '1 step' : `${n} steps`}
                      </Text>
                    </GuideButton>
                  </li>
                );
              })}
            </Stack>
          </div>
        );
      })}
      <Group>
        <GuideButton
          variant="subtle"
          color="gray"
          leftSection={<IconX size={16} aria-hidden />}
          onClick={exit}
        >
          Exit guide
        </GuideButton>
      </Group>
    </Stack>
  );
}

/**
 * The finish card, in place of the last step's card: what the route showed, and what to do next. S20 is the short
 * route's optional extra, so it is offered here and said to be optional, never a step of the quick tour. A reader who
 * may run scenarios is pointed at Run S20; one who may not (the public demo and judge roles) is taken to S20's newest
 * rules case instead, where the gate stopped the fix.
 */
function Finish() {
  const navigate = useNavigate();
  const exit = useGuide((s) => s.exit);
  const openChapters = useGuide((s) => s.openChapters);
  const point = useGuide((s) => s.point);
  const ask = useLeaveTrial((s) => s.ask);
  const can = useCan();
  const titleRef = useRef<HTMLHeadingElement | null>(null);
  const scope = useGuide((s) => s.progress.scope);
  const seeS20 = () =>
    resolvePlace({ scenario: 'S20', mode: 'rules' })
      .then((to) => navigate('path' in to ? to.path : '/scenarios'))
      .catch(() => navigate('/scenarios'))
      .finally(exit);
  const [host] = useState(() => {
    const d = document.createElement('div');
    d.className = 'guide-host';
    return d;
  });
  useEffect(() => {
    // Where the last step's card stood, before its section, when that is still on the page; else the screen's foot
    const last = stepAt(SCOPES[scope].at(-1))?.step.target;
    const el = last ? document.querySelector<HTMLElement>(`[data-tour="${last}"]`) : null;
    if (el) el.insertAdjacentElement('beforebegin', host);
    else {
      host.classList.add('guide-host-floating');
      document.body.append(host);
    }
    const timer = window.setTimeout(() => titleRef.current && focusFrom(titleRef.current), 0);
    return () => {
      window.clearTimeout(timer);
      host.remove();
    };
  }, [host, scope]);
  const card = (
    <Paper
      className="guide-card guide-card-enter"
      role="region"
      aria-label="Guide"
      withBorder
      shadow="sm"
      p="md"
      maw={720}
      onKeyDown={(e) => {
        if (e.key === 'Escape') exit();
      }}
    >
      <Stack gap="sm">
        <Title order={2} fz={22} tabIndex={-1} ref={titleRef} className="guide-title">
          That is the tour.
        </Title>
        <Text fz={18}>{SCOPE_FINISH[scope]}</Text>
        <Group gap="sm" wrap="wrap" align="center">
          {can.scenarios ? (
            <GuideButton
              color="grape"
              leftSection={<IconPlayerPlay size={16} aria-hidden />}
              onClick={() => {
                navigate('/scenarios');
                point('run-S20');
              }}
            >
              Run S20 yourself
            </GuideButton>
          ) : (
            <GuideButton
              color="grape"
              leftSection={<IconArrowRight size={16} aria-hidden />}
              onClick={seeS20}
            >
              See the gate stop a fix
            </GuideButton>
          )}
          <Text size="sm">
            {can.scenarios ? 'Optional: watch the gate stop a fix.' : 'Optional: S20, as the rules ran it.'}
          </Text>
        </Group>
        <Group gap="sm" wrap="wrap">
          <GuideButton variant="default" onClick={exit}>
            Explore on my own
          </GuideButton>
          <GuideButton
            variant="default"
            leftSection={<IconList size={16} aria-hidden />}
            onClick={openChapters}
          >
            Choose a chapter
          </GuideButton>
          {ENV.canLeave ? (
            <GuideButton
              variant="subtle"
              color="grape"
              leftSection={<IconDoorExit size={16} aria-hidden />}
              onClick={ask}
            >
              Leave trial
            </GuideButton>
          ) : null}
        </Group>
      </Stack>
    </Paper>
  );
  return createPortal(card, host);
}

/** The pointer with no card: the finish card's "Run S20 yourself" shows the control, focuses it and points at it. */
function Pointing({ action }: { action: string }) {
  const reduced = useReducedMotion() ?? false;
  const point = useGuide((s) => s.point);
  const { pathname } = useLocation();
  const [control, setControl] = useState<HTMLElement | null>(null);
  // The page the control was found on. Not the page at mount: the finish card navigates as it asks for the pointing,
  // and the router can show the new page after this has mounted
  const [at, setAt] = useState<string | null>(null);
  const path = useRef(pathname);
  useEffect(() => {
    path.current = pathname;
  }, [pathname]);
  useEffect(() => {
    let el: HTMLElement | null = null;
    const look = window.setInterval(() => {
      const found = tryControl(action);
      if (!visible(found)) return;
      window.clearInterval(look);
      el = found;
      bringToHand(found, reduced);
      found.dataset.tourTry = reduced ? 'rest' : 'true';
      setControl(found);
      setAt(path.current);
    }, 100);
    const stop = window.setTimeout(() => window.clearInterval(look), 10_000);
    return () => {
      window.clearInterval(look);
      window.clearTimeout(stop);
      if (el) delete el.dataset.tourTry;
    };
  }, [action, reduced]);
  // Going elsewhere ends the pointing
  useEffect(() => {
    if (at !== null && pathname !== at) point(null);
  }, [pathname, at, point]);
  return control ? <TryItPointer control={control} motion={reduced ? 'rest' : 'run'} /> : null;
}

// ---- the guide ----

/** One polite announcement per step change, short: the step, never the page's content. */
function useAnnouncement(phase: GuidePhase, pos: GuidePosition | undefined, approved: boolean) {
  const can = useCan();
  const caseState = useStepCaseState(pos?.step);
  const [message, setMessage] = useState('');
  const key = pos ? pos.path : '';
  const [before, setBefore] = useState({ phase, key });
  if (before.phase !== phase || before.key !== key) {
    setBefore({ phase, key });
    if (phase === 'step' && pos)
      setMessage(
        `${approved ? 'Approved for you, in the trial. ' : ''}Step ${pos.n} of ${pos.m}, ${sentence(pos.chapter.title)}. ${stepForRole(pos.step, can, caseState).title}.`,
      );
    else if (phase === 'finished') setMessage('That is the tour.');
    else if (phase === 'closed' && before.phase === 'step')
      setMessage('The tour is closed. Resume tour, in the header, takes you back to it.');
  }
  return message;
}

export function Guide() {
  const phase = useGuide((s) => s.phase);
  const progress = useGuide((s) => s.progress);
  const approvedForYou = useGuide((s) => s.approvedForYou);
  const pointAt = useGuide((s) => s.pointAt);
  const openedAt = useGuide((s) => s.openedAt);
  const exit = useGuide((s) => s.exit);
  const phone = useMediaQuery('(max-width: 47.99em)', false);
  const reduced = useReducedMotion();
  const pos = positionOf(progress);
  const message = useAnnouncement(phase, pos, !!pos && approvedForYou === pos.path);
  const [welcomeScope] = useState<GuideScope>(progress.scope);

  // On arrival with ?trial=tour or ?trial=engineer that tour starts; on a first entry the welcome opens by itself.
  // The judges' path (?trial=judge) goes straight to S8: the welcome is put off for the visit, as Explore on my own does.
  useEffect(() => {
    const s = useGuide.getState();
    if (s.phase !== 'closed') return;
    if (ENV.judgePath) s.notNow();
    else if (ENV.openGuide) {
      s.begin(ENV.openGuide);
      compactBanner();
    } else if (!s.snoozed && welcomeDue(s.progress)) s.openWelcome();
  }, []);

  // Focus goes back where the reader was when a modal or the tour closes
  const opener = useRef<HTMLElement | null>(null);
  const previous = useRef(phase);
  // The welcome's Start with S2 hands the reader to the Scenarios page, which focuses S2's Run: no focus goes back
  const handedOver = useRef(false);
  useEffect(() => {
    const was = previous.current;
    previous.current = phase;
    if (phase !== 'closed' && was === 'closed')
      opener.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    if (phase === 'closed' && was !== 'closed') {
      const back = opener.current?.isConnected ? opener.current : pageHeading();
      opener.current = null;
      if (back && !pointAt && !handedOver.current) window.setTimeout(() => focusFrom(back), 0);
      handedOver.current = false;
    }
  }, [phase, pointAt]);

  // Start with S2: the welcome is put off for the visit, as Explore on my own puts it off, and the short route's start
  // opens. It only opens a page: Run there is the reader's own press.
  const navigate = useNavigate();
  const startS2 = () => {
    handedOver.current = true;
    useGuide.getState().notNow();
    navigate(WELCOME_START_S2);
  };

  const modal = {
    onClose: exit,
    // Focus goes back by hand: where the reader was, or into the step's card
    returnFocus: false,
    // Closing is at once: no half-faded layer for a screenshot or a first click to meet
    transitionProps: reduced ? { duration: 0 } : { exitDuration: 0 },
    closeButtonProps: { 'aria-label': 'Exit guide' },
    fullScreen: phone,
    size: 'xl' as const,
    centered: true,
  };
  return (
    <>
      <VisuallyHidden aria-live="polite" data-guide-announcer>
        {message}
      </VisuallyHidden>
      <Modal {...modal} opened={phase === 'welcome'} title="Welcome to the Shutter trial">
        {phase === 'welcome' ? <Welcome initial={welcomeScope} onStartS2={startS2} /> : null}
      </Modal>
      <Modal {...modal} size="lg" opened={phase === 'chapters'} title="Choose a chapter">
        {phase === 'chapters' ? <Chapters /> : null}
      </Modal>
      {/* Keyed by the step and the moment it opened: opening it again plays its movements again */}
      {phase === 'step' && pos ? <StepHost key={`${pos.path}:${openedAt}`} pos={pos} /> : null}
      {phase === 'finished' ? <Finish /> : null}
      {pointAt ? <Pointing key={pointAt} action={pointAt} /> : null}
    </>
  );
}
