import {
  Affix,
  Alert,
  Button,
  type ButtonProps,
  Drawer,
  Group,
  Loader,
  Modal,
  Paper,
  Radio,
  Stack,
  Text,
  VisuallyHidden,
} from '@mantine/core';
import { useMediaQuery, useReducedMotion } from '@mantine/hooks';
import {
  IconArrowLeft,
  IconArrowRight,
  IconCheck,
  IconEye,
  IconMapPin,
  IconPlayerPlay,
  IconPlayerSkipForward,
  IconX,
} from '@tabler/icons-react';
import {
  useEffect,
  useEffectEvent,
  useRef,
  useState,
  type ComponentPropsWithoutRef,
  type ReactNode,
} from 'react';
import { createPortal } from 'react-dom';
import { useLocation, useNavigate } from 'react-router';
import { positionOf, welcomeDue, type GuidePosition } from './controller';
import { usePlace } from './places';
import { CHAPTERS, SCOPE_LABELS, SCOPES, type GuideScope } from './registry';
import { focusFrom, headingOf, pageHeading, waitForTarget } from './reveal';
import { useGuide, type GuidePhase } from './store';

/**
 * The first-run guide: a welcome on the first visit, then one step at a time in a dialog (a bottom sheet on a
 * phone). Show this section closes the dialog, opens the step's page and section, moves focus to its heading and
 * puts Continue guide right after it. The guide only moves between pages and opens sections; every action on them
 * stays the reader's.
 */

const DIALOG_PHASES: GuidePhase[] = ['welcome', 'step', 'chapters'];

const stepLabel = (pos: GuidePosition) => `Step ${pos.n} of ${pos.m} · ${pos.chapter.title}`;

/** The guide's buttons: at least 44 px high, for touch. */
function GuideButton(props: ButtonProps & Omit<ComponentPropsWithoutRef<'button'>, keyof ButtonProps>) {
  return <Button className="guide-control" {...props} />;
}

function Sheet({
  opened,
  title,
  onClose,
  children,
}: {
  opened: boolean;
  title: string;
  onClose: () => void;
  children: ReactNode;
}) {
  const phone = useMediaQuery('(max-width: 47.99em)', false);
  const reduced = useReducedMotion();
  const common = {
    opened,
    onClose,
    title,
    // Focus goes back by hand: where the reader was, or to the section the dialog sends them to
    returnFocus: false,
    transitionProps: reduced ? { duration: 0 } : undefined,
    closeButtonProps: { 'aria-label': 'Exit guide', size: 'xl' },
  };
  return phone ? (
    // As tall as its content, at most most of the screen, so the page behind still shows where the reader is
    <Drawer
      {...common}
      position="bottom"
      padding="md"
      styles={{ content: { flex: '0 0 auto', height: 'auto', maxHeight: '90dvh' } }}
    >
      {children}
    </Drawer>
  ) : (
    <Modal {...common} centered size="lg">
      {children}
    </Modal>
  );
}

function Welcome() {
  const progress = useGuide((s) => s.progress);
  const begin = useGuide((s) => s.begin);
  const notNow = useGuide((s) => s.notNow);
  const dontShowAgain = useGuide((s) => s.dontShowAgain);
  const [scope, setScope] = useState<GuideScope>(progress.scope);
  return (
    <Stack gap="md">
      <Text size="sm">
        A short walkthrough of the screens. It only opens pages and sections: it never plays a scenario,
        approves, dispatches, saves configuration or sends mail. Every write passes the gate, then a person,
        or the site&apos;s written policy, releases it, and each case shows which.
      </Text>
      <Radio.Group label="What to see" value={scope} onChange={(v) => setScope(v as GuideScope)}>
        <Stack gap="sm" mt="xs">
          <Radio
            value="quick"
            label={SCOPE_LABELS.quick}
            description="Scenarios, an S2 case, an S8 case with rules and the board side by side, an S20 case and the evaluation."
          />
          <Radio
            value="all"
            label={SCOPE_LABELS.all}
            description={`One or two steps on every screen, in ${SCOPES.all.length} chapters.`}
          />
        </Stack>
      </Radio.Group>
      <Group gap="sm" wrap="wrap">
        <GuideButton
          leftSection={<IconPlayerPlay size={16} />}
          onClick={() => begin(scope)}
          data-autofocus
          data-guide-focus
        >
          Start guide
        </GuideButton>
        <GuideButton variant="default" onClick={notNow}>
          Not now
        </GuideButton>
        <GuideButton variant="subtle" onClick={dontShowAgain}>
          Don&apos;t show again
        </GuideButton>
      </Group>
      <Text size="xs" c="dimmed">
        Help in the header resumes the guide, starts it again or opens a chapter.
      </Text>
    </Stack>
  );
}

function StepBody({ pos }: { pos: GuidePosition }) {
  const next = useGuide((s) => s.next);
  const back = useGuide((s) => s.back);
  const skipChapter = useGuide((s) => s.skipChapter);
  const exit = useGuide((s) => s.exit);
  const show = useGuide((s) => s.show);
  const place = usePlace(pos.step);
  const missing = place.data && 'missing' in place.data ? place.data.missing : undefined;
  return (
    <Stack gap="md">
      <Text size="sm">{pos.step.text}</Text>
      {place.isPending ? (
        <Group gap="xs">
          <Loader size="xs" />
          <Text size="sm" c="dimmed">
            Finding the page…
          </Text>
        </Group>
      ) : null}
      {missing ? (
        <Alert color="gray" variant="light" title="Not here yet">
          <Text size="sm">{missing}</Text>
        </Alert>
      ) : null}
      <Group gap="sm" wrap="wrap">
        {!missing ? (
          <GuideButton
            leftSection={<IconEye size={16} />}
            onClick={show}
            disabled={!place.data}
            data-autofocus
            data-guide-focus
          >
            Show this section
          </GuideButton>
        ) : null}
        <GuideButton
          variant={missing ? 'filled' : 'light'}
          rightSection={pos.last ? <IconCheck size={16} /> : <IconArrowRight size={16} />}
          onClick={next}
          data-autofocus={missing ? true : undefined}
          data-guide-focus={missing ? true : undefined}
        >
          {pos.last ? 'Finish' : missing ? 'Skip this step' : 'Next'}
        </GuideButton>
      </Group>
      <Group gap="sm" wrap="wrap">
        <GuideButton
          variant="default"
          leftSection={<IconArrowLeft size={16} />}
          onClick={back}
          disabled={pos.first}
        >
          Back
        </GuideButton>
        <GuideButton
          variant="default"
          leftSection={<IconPlayerSkipForward size={16} />}
          onClick={skipChapter}
        >
          Skip chapter
        </GuideButton>
        <GuideButton variant="subtle" leftSection={<IconX size={16} />} onClick={exit}>
          Exit guide
        </GuideButton>
      </Group>
    </Stack>
  );
}

function Chapters() {
  const progress = useGuide((s) => s.progress);
  const choose = useGuide((s) => s.chooseChapter);
  const exit = useGuide((s) => s.exit);
  return (
    <Stack gap="sm">
      <Text size="sm">
        Every chapter of {SCOPE_LABELS.all}. The {SCOPE_LABELS.quick.toLowerCase()} has {SCOPES.quick.length}{' '}
        of them.
      </Text>
      <Stack gap={6} component="ul" style={{ listStyle: 'none', padding: 0, margin: 0 }}>
        {CHAPTERS.map((c, i) => {
          const done = progress.completed.includes(c.id);
          const current = progress.chapter === c.id;
          return (
            <li key={c.id}>
              <GuideButton
                variant={current ? 'light' : 'default'}
                fullWidth
                justify="space-between"
                // The current chapter says so in words and with a mark, not by its tint alone
                leftSection={current ? <IconMapPin size={16} aria-hidden /> : null}
                rightSection={done ? <IconCheck size={16} aria-hidden /> : null}
                onClick={() => choose(c.id)}
                data-autofocus={i === 0 || undefined}
                data-guide-focus={i === 0 || undefined}
              >
                {c.title}
                {done ? <VisuallyHidden> (finished)</VisuallyHidden> : null}
                {current ? (
                  <Text span size="xs" fw={600}>
                    {' '}
                    (current)
                  </Text>
                ) : null}
              </GuideButton>
            </li>
          );
        })}
      </Stack>
      <Group>
        <GuideButton variant="subtle" leftSection={<IconX size={16} />} onClick={exit}>
          Exit guide
        </GuideButton>
      </Group>
    </Stack>
  );
}

/** Continue guide, placed right after the shown section's heading, or at the foot of the screen when it has none. */
function ContinueBar({ pos, notFound }: { pos: GuidePosition; notFound: boolean }) {
  const continueGuide = useGuide((s) => s.continueGuide);
  const exit = useGuide((s) => s.exit);
  return (
    <Paper
      withBorder
      shadow="sm"
      p="xs"
      my="xs"
      role="region"
      aria-label="Guide"
      className="guide-continue"
      onKeyDown={(e) => {
        if (e.key === 'Escape') exit();
      }}
    >
      <Group gap="sm" justify="space-between" wrap="wrap">
        <Text size="sm">
          {stepLabel(pos)}
          {notFound ? '. This section is not on the page just now.' : ''}
        </Text>
        <Group gap="xs" wrap="wrap">
          <GuideButton size="sm" rightSection={<IconArrowRight size={16} />} onClick={continueGuide}>
            Continue guide
          </GuideButton>
          <GuideButton size="sm" variant="subtle" onClick={exit}>
            Exit guide
          </GuideButton>
        </Group>
      </Group>
    </Paper>
  );
}

/** The shown phase: opens the step's page and section, marks it, focuses its heading and offers Continue guide. */
function Shown({ pos }: { pos: GuidePosition }) {
  const place = usePlace(pos.step);
  const navigate = useNavigate();
  const location = useLocation();
  const here = location.pathname + location.search;
  // The same address again still counts: the case page reopens its story step on every visit
  const go = useEffectEvent((to: string) => navigate(to, { replace: here === to }));
  const reduced = useReducedMotion();
  const [host, setHost] = useState<HTMLElement | null>(null);
  const [notFound, setNotFound] = useState(false);
  const path = place.data && 'path' in place.data ? place.data.path : undefined;
  const target = pos.step.target;

  useEffect(() => {
    if (path) go(path);
  }, [path]);

  // Only once the address is the step's: until then the page before it, with its own sections, is still showing
  const arrived = !!path && here === path;
  const started = useRef(false);
  useEffect(() => {
    if (!arrived || started.current) return;
    started.current = true;
    let cancelled = false;
    let marked: HTMLElement | null = null;
    let placed: HTMLElement | null = null;
    void waitForTarget(target).then((el) => {
      if (cancelled) return;
      if (!el) {
        setNotFound(true);
        const h = pageHeading();
        if (h) focusFrom(h);
        return;
      }
      // A story step opening below its heading moves the page: wait for the panel before scrolling to it
      window.setTimeout(
        () => {
          if (cancelled) return;
          marked = el;
          el.dataset.tourActive = 'true';
          el.scrollIntoView?.({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
          const heading = headingOf(el);
          placed = document.createElement('div');
          placed.dataset.guideHost = 'true';
          // Right after the heading, so Continue guide is the next stop; first in a section with no heading
          heading.insertAdjacentElement(/^H[1-6]$/.test(heading.tagName) ? 'afterend' : 'afterbegin', placed);
          setHost(placed);
          focusFrom(heading);
        },
        reduced ? 0 : 250,
      );
    });
    // Leaving the page ends the showing; coming back by hand does not show it again, unless it never got as far
    return () => {
      cancelled = true;
      if (marked) delete marked.dataset.tourActive;
      else started.current = false;
      placed?.remove();
    };
  }, [arrived, target, reduced]);

  // The reader may leave the page: Continue guide then waits at the foot of the screen
  useEffect(() => {
    if (!host) return;
    const timer = window.setInterval(() => {
      if (!host.isConnected) setHost(null);
    }, 500);
    return () => window.clearInterval(timer);
  }, [host]);

  if (host?.isConnected) return createPortal(<ContinueBar pos={pos} notFound={notFound} />, host);
  return (
    <Affix position={{ bottom: 16, right: 16, left: 16 }} zIndex={150}>
      <ContinueBar pos={pos} notFound={notFound} />
    </Affix>
  );
}

/** One polite announcement per step change, short: the step, never the page's content. */
function useAnnouncement(phase: GuidePhase, pos: GuidePosition | undefined) {
  const [message, setMessage] = useState('');
  const key = pos ? `${pos.chapter.id}:${pos.n}` : '';
  const [before, setBefore] = useState({ phase, key });
  if (before.phase !== phase || before.key !== key) {
    setBefore({ phase, key });
    if (phase === 'step' && pos && before.phase === 'step')
      setMessage(`${stepLabel(pos)}: ${pos.step.title}`);
    else if (phase === 'shown' && pos)
      setMessage(`Showing ${pos.step.title}. Continue guide follows its heading.`);
    else if (phase === 'closed' && before.phase === 'step' && !pos)
      setMessage('The guide is finished. Help in the header starts it again.');
  }
  return message;
}

export function Guide() {
  const phase = useGuide((s) => s.phase);
  const progress = useGuide((s) => s.progress);
  const exit = useGuide((s) => s.exit);
  const shownAt = useGuide((s) => s.shownAt);
  const pos = positionOf(progress);
  const message = useAnnouncement(phase, pos);

  // The first visit: the welcome opens by itself, once
  useEffect(() => {
    const s = useGuide.getState();
    if (s.phase === 'closed' && !s.snoozed && welcomeDue(s.progress)) s.openWelcome();
  }, []);

  // Focus: into the dialog's main action when it turns to another view, and back where the reader was when it closes
  const opener = useRef<HTMLElement | null>(null);
  const previous = useRef(phase);
  const dialog = DIALOG_PHASES.includes(phase);
  useEffect(() => {
    const was = previous.current;
    previous.current = phase;
    const wasDialog = DIALOG_PHASES.includes(was);
    if (dialog && !wasDialog)
      opener.current = document.activeElement instanceof HTMLElement ? document.activeElement : null;
    if (dialog && wasDialog)
      window.requestAnimationFrame(() =>
        document.querySelector<HTMLElement>('[data-guide-focus]:not([disabled])')?.focus(),
      );
    if (phase === 'closed' && wasDialog) {
      const back = opener.current?.isConnected ? opener.current : pageHeading();
      opener.current = null;
      if (back) window.setTimeout(() => focusFrom(back), 0);
    }
  }, [phase, dialog]);

  const title =
    phase === 'welcome'
      ? 'Welcome to Shutter'
      : phase === 'chapters'
        ? 'Choose a chapter'
        : (pos?.step.title ?? '');
  return (
    <>
      <VisuallyHidden aria-live="polite" data-guide-announcer>
        {message}
      </VisuallyHidden>
      <Sheet opened={dialog && (phase !== 'step' || !!pos)} title={title} onClose={exit}>
        {phase === 'welcome' ? <Welcome /> : null}
        {phase === 'chapters' ? <Chapters /> : null}
        {phase === 'step' && pos ? (
          <Stack gap="xs">
            <Text size="xs" c="dimmed" fw={600}>
              {stepLabel(pos)}
            </Text>
            {/* Not keyed by step: the button pressed keeps focus as the step changes */}
            <StepBody pos={pos} />
          </Stack>
        ) : null}
      </Sheet>
      {/* Keyed by the moment it was asked for: Show this section again on the same step starts afresh */}
      {phase === 'shown' && pos ? <Shown key={`${pos.chapter.id}:${pos.n}:${shownAt}`} pos={pos} /> : null}
    </>
  );
}
