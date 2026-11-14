import { AppShell, Card, CloseButton, Drawer, Group, Stack, Title } from '@mantine/core';
import {
  lazy,
  Suspense,
  useCallback,
  useEffect,
  useRef,
  useState,
  type CSSProperties,
  type ReactNode,
} from 'react';
import { Outlet, useSearchParams } from 'react-router';
import { AssistantRouteSync } from './AssistantRouteSync';
import { Loader } from '@mantine/core';
import { useMediaQuery } from '@mantine/hooks';
import { guideDock, useGuideCardShown } from '@/lib/guideDock';
import { SHOW_EVIDENCE } from '@/features/cases/case/evidenceLinks';
import { ASSISTANT_BUTTON_ID } from './HeaderAssistantButton';
import {
  ASSISTANT_PANEL_ID,
  askAboutButtonId,
  assistantTitle,
  useAssistantContext,
  useAssistantWide,
  type AssistantContext,
} from './panel';
import { useAssistant } from './store';

export { ASSISTANT_ASIDE_WIDTH } from './panel';
export { AssistantRouteSync } from './AssistantRouteSync';

// The case panel carries the What-if card and the case's recorded conversations; a page's chat is lighter. Each loads
// when the panel first shows it.
const AskPanel = lazy(() => import('@/features/cases/ask/AskPanel').then((m) => ({ default: m.AskPanel })));
const PageChat = lazy(() => import('./PageChat').then((m) => ({ default: m.PageChat })));

/** What the panel holds: Ask about this case on a case page, Ask Shutter about the page everywhere else. */
function PanelBody({ ctx }: { ctx: AssistantContext }) {
  const autoAsk = useAssistant((s) => s.autoAsk);
  return (
    <Suspense fallback={<Loader size="sm" aria-label="Opening the panel" />}>
      {ctx.kind === 'case' ? (
        <AskPanel key={ctx.caseId} caseId={ctx.caseId} autoAsk={autoAsk === ctx.caseId} />
      ) : (
        <PageChat key={ctx.page} page={ctx.page} />
      )}
    </Suspense>
  );
}

/**
 * The panel as a region with its heading, which takes focus when it opens; Escape or Close shuts it. Beside the page from
 * the wide breakpoint; narrower, while the guide's card is on the page, the same region as a sheet over the page's right
 * side (`sheet`), with no overlay and no focus trap, so the card stays in reach.
 */
function Beside({
  title,
  onClose,
  sheet = false,
  style,
  children,
}: {
  title: string;
  onClose: () => void;
  sheet?: boolean;
  style?: CSSProperties;
  children: ReactNode;
}) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => heading.current?.focus({ preventScroll: true }), []);
  return (
    <Card
      component="section"
      id={ASSISTANT_PANEL_ID}
      aria-labelledby={`${ASSISTANT_PANEL_ID}-title`}
      className={sheet ? 'ask-sheet' : 'ask-aside'}
      padding="md"
      withBorder={false}
      shadow={sheet ? 'xl' : 'none'}
      radius={0}
      style={style}
      onKeyDown={(e) => {
        if (e.key === 'Escape' && !e.defaultPrevented) {
          e.stopPropagation();
          onClose();
        }
      }}
    >
      <Stack gap="md">
        <Group justify="space-between" wrap="nowrap">
          <Title order={2} id={`${ASSISTANT_PANEL_ID}-title`} tabIndex={-1} ref={heading}>
            {title}
          </Title>
          <CloseButton onClick={onClose} aria-label={`Close ${title}`} />
        </Group>
        {children}
      </Stack>
      {/* On a phone the guide's card stands over the sheet's foot: room to scroll the last of the panel above it */}
      {sheet ? <div className="ask-sheet-spacer" aria-hidden /> : null}
    </Card>
  );
}

/**
 * The sheet and, just before it, the dock the guide's card moves into while the sheet is open (lib/guideDock.ts). The
 * dock's height is kept on the sheet, so on a phone, where the card covers the sheet's foot, the panel's end can still
 * be scrolled into view above it.
 */
function Sheet({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  const [dock, setDock] = useState<HTMLDivElement | null>(null);
  const [dockHeight, setDockHeight] = useState(0);
  useEffect(() => {
    guideDock.set(dock);
    return () => guideDock.set(null);
  }, [dock]);
  useEffect(() => {
    if (!dock || typeof ResizeObserver === 'undefined') return;
    const observer = new ResizeObserver(() => setDockHeight(dock.offsetHeight));
    observer.observe(dock);
    return () => observer.disconnect();
  }, [dock]);
  return (
    <>
      <div ref={setDock} className="guide-dock" data-guide-dock />
      <Beside
        title={title}
        onClose={onClose}
        sheet
        style={{ '--guide-dock-h': `${dockHeight}px` } as CSSProperties}
      >
        {children}
      </Beside>
    </>
  );
}

/**
 * Focus on the button that opened the panel: a page question's "Ask Shutter about this" (`from`, its question's id) while
 * it is on the page, else a case's own, else the header's.
 */
function focusOpener(from?: string) {
  const asked = from ? document.getElementById(askAboutButtonId(from)) : null;
  const own = document.querySelector<HTMLElement>('[data-tour-action="ask-open"]');
  (asked ?? own ?? document.getElementById(ASSISTANT_BUTTON_ID))?.focus();
}

/**
 * Closes the panel; focus goes back to the button that opened it once it has closed. The drawer does the same again when
 * its closing transition ends, since its focus trap holds focus until then.
 */
function useClosePanel() {
  const setOpen = useAssistant((s) => s.setOpen);
  return useCallback(() => {
    const from = useAssistant.getState().focus?.id;
    setOpen(false);
    window.setTimeout(() => focusOpener(from), 0);
  }, [setOpen]);
}

/**
 * The panel beside the page, from the wide breakpoint: the shell's aside, which the page keeps clear of. Rendered by the
 * shell inside its AppShell while the panel is open and the window is wide.
 */
export function AssistantAside() {
  const ctx = useAssistantContext();
  const onClose = useClosePanel();
  return (
    <AppShell.Aside className="assistant-aside">
      <Beside title={assistantTitle(ctx)} onClose={onClose}>
        <PanelBody ctx={ctx} />
      </Beside>
    </AppShell.Aside>
  );
}

/**
 * The panel below the wide breakpoint: a drawer from the right over the page (the whole screen on a phone), or, while the
 * guide's card is on the page (the trial's tour), a sheet instead: the same place and size, but no overlay and no focus
 * trap, with the card docked beside it, so the tour goes on with the panel open. Focus goes to the panel's heading when it
 * opens, in every form (the drawer traps it), and back to the button when it closes.
 */
export function AssistantOverlay() {
  const ctx = useAssistantContext();
  const title = assistantTitle(ctx);
  const open = useAssistant((s) => s.open);
  const onClose = useClosePanel();
  const wide = useAssistantWide();
  const phone = useMediaQuery('(max-width: 48em)', false, { getInitialValueInEffect: false });
  // The sheet when the guide's card is on the page as the panel opens; it stays a sheet until the panel closes, even if
  // the tour ends meanwhile, so an overlay never drops over the page while the panel is open
  const touring = useGuideCardShown();
  const [sheet, setSheet] = useState(false);
  if (open && !wide && touring && !sheet) setSheet(true);
  if (!open && sheet) setSheet(false);
  const asSheet = open && !wide && sheet;
  // A citation in an answer opens the Evidence tab behind the drawer, so the drawer closes for the evidence to be seen:
  // once the address names the tab, since closing edits the address too and must keep it
  const citing = useRef(false);
  // Closed for a citation: focus goes to the cited evidence, not back to the button, when the drawer has closed
  const toEvidence = useRef(false);
  const setOpen = useAssistant((s) => s.setOpen);
  const closeForEvidence = useCallback(() => {
    toEvidence.current = true;
    setOpen(false);
  }, [setOpen]);
  const [search] = useSearchParams();
  const onEvidence = search.get('tab') === 'evidence';
  useEffect(() => {
    if (!open || wide) return;
    const cite = () => {
      if (onEvidence) closeForEvidence();
      else citing.current = true;
    };
    window.addEventListener(SHOW_EVIDENCE, cite);
    return () => window.removeEventListener(SHOW_EVIDENCE, cite);
  }, [open, wide, onEvidence, closeForEvidence]);
  useEffect(() => {
    if (!citing.current || !onEvidence) return;
    citing.current = false;
    if (open && !wide) closeForEvidence();
  }, [onEvidence, open, wide, closeForEvidence]);
  return (
    <>
      {asSheet ? (
        <Sheet title={title} onClose={onClose}>
          <PanelBody ctx={ctx} />
        </Sheet>
      ) : null}
      <Drawer.Root
        opened={open && !wide && !asSheet}
        onClose={onClose}
        position="right"
        size={phone ? '100%' : 480}
        returnFocus={false}
        onExitTransitionEnd={() => {
          if (toEvidence.current) toEvidence.current = false;
          else focusOpener();
        }}
      >
        <Drawer.Overlay />
        <Drawer.Content>
          <Drawer.Header>
            {/* The drawer's focus trap starts on its heading, as the panel beside the page does */}
            <Drawer.Title data-autofocus tabIndex={-1} fw={600} fz="lg">
              {title}
            </Drawer.Title>
            <Drawer.CloseButton aria-label={`Close ${title}`} />
          </Drawer.Header>
          <Drawer.Body>
            {open && !wide && !asSheet ? (
              <div id={ASSISTANT_PANEL_ID}>
                <PanelBody ctx={ctx} />
              </div>
            ) : null}
          </Drawer.Body>
        </Drawer.Content>
      </Drawer.Root>
    </>
  );
}

/**
 * The pages with the panel's narrow forms and the address sync, for tests that render a page without the shell: the
 * shell itself places these inside its AppShell, with the aside beside them.
 */
export function AssistantFrame() {
  return (
    <>
      <Outlet />
      <AssistantOverlay />
      <AssistantRouteSync />
    </>
  );
}
