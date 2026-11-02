import { Button, Card, CloseButton, Drawer, Group, Stack, Title } from '@mantine/core';
import { useMediaQuery } from '@mantine/hooks';
import { IconMessageQuestion } from '@tabler/icons-react';
import { forwardRef, useEffect, useRef, useState, type CSSProperties, type ReactNode } from 'react';
import { useSearchParams } from 'react-router';
import { guideDock, useGuideCardShown } from '@/lib/guideDock';
import { SHOW_EVIDENCE } from '../case/evidenceLinks';
import { AskPanel } from './AskPanel';

export const ASK_PANEL_ID = 'ask-panel';
const TITLE = 'Ask about this case';

/** Opens and closes the panel; the guide points at it. */
export const AskButton = forwardRef<HTMLButtonElement, { open: boolean; onToggle: () => void }>(
  function AskButton({ open, onToggle }, ref) {
    return (
      <div data-tour="case-ask">
        <Button
          ref={ref}
          variant={open ? 'filled' : 'light'}
          leftSection={<IconMessageQuestion size={16} aria-hidden />}
          aria-expanded={open}
          aria-controls={open ? ASK_PANEL_ID : undefined}
          onClick={onToggle}
          data-tour-action="ask-open"
        >
          {TITLE}
        </Button>
      </div>
    );
  },
);

/**
 * The panel as a region with its heading, which takes focus when it opens; Escape or Close shuts it. Beside the case
 * from 1440 px; narrower, while the guide's card is on the page, the same region as a sheet over the page's right side
 * (`sheet`), with no overlay and no focus trap, so the card stays in reach.
 */
function Beside({
  onClose,
  sheet = false,
  style,
  children,
}: {
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
      id={ASK_PANEL_ID}
      aria-labelledby={`${ASK_PANEL_ID}-title`}
      className={sheet ? 'ask-sheet' : 'ask-aside'}
      padding="md"
      withBorder={!sheet}
      shadow={sheet ? 'xl' : undefined}
      radius={sheet ? 0 : undefined}
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
          <Title order={2} id={`${ASK_PANEL_ID}-title`} tabIndex={-1} ref={heading}>
            {TITLE}
          </Title>
          <CloseButton onClick={onClose} aria-label="Close Ask about this case" />
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
function Sheet({ onClose, children }: { onClose: () => void; children: ReactNode }) {
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
      <Beside onClose={onClose} sheet style={{ '--guide-dock-h': `${dockHeight}px` } as CSSProperties}>
        {children}
      </Beside>
    </>
  );
}

/**
 * The case page with the panel: side by side from 90em (1440 px), where the case keeps room for its board beside it;
 * below that a drawer from the right over the page, so the case keeps its full width, and the whole screen on a phone.
 * While the guide's card is on the page (the trial's tour), the narrower form is a sheet instead: the same place and
 * size, but no overlay and no focus trap, with the card docked beside it, so the tour goes on with Ask open. Focus goes
 * to the panel's heading when it opens, in every form (the drawer traps it), and back to the button when it closes.
 */
export function AskSurface({
  caseId,
  open,
  onClose,
  children,
}: {
  caseId: string;
  open: boolean;
  onClose: () => void;
  children: ReactNode;
}) {
  const wide = useMediaQuery('(min-width: 90em)', false, { getInitialValueInEffect: false });
  const phone = useMediaQuery('(max-width: 48em)', false, { getInitialValueInEffect: false });
  // The sheet when the guide's card is on the page as Ask opens; it stays a sheet until Ask closes, even if the tour
  // ends meanwhile, so an overlay never drops over the page while the panel is open
  const touring = useGuideCardShown();
  const [sheet, setSheet] = useState(false);
  if (open && !wide && touring && !sheet) setSheet(true);
  if (!open && sheet) setSheet(false);
  const asSheet = open && !wide && sheet;
  // A citation in an answer opens the Evidence tab behind the drawer, so the drawer closes for the evidence to be seen:
  // once the address names the tab, since closing edits the address too and must keep it
  const citing = useRef(false);
  const [search] = useSearchParams();
  const onEvidence = search.get('tab') === 'evidence';
  useEffect(() => {
    if (!open || wide) return;
    const cite = () => {
      if (onEvidence) onClose();
      else citing.current = true;
    };
    window.addEventListener(SHOW_EVIDENCE, cite);
    return () => window.removeEventListener(SHOW_EVIDENCE, cite);
  }, [open, wide, onEvidence, onClose]);
  useEffect(() => {
    if (!citing.current || !onEvidence) return;
    citing.current = false;
    if (open && !wide) onClose();
  }, [onEvidence, open, wide, onClose]);
  // The page keeps its place in the tree whether the panel is open or not, so nothing on it is mounted afresh
  return (
    <>
      <div className={wide && open ? 'ask-layout' : undefined}>
        <div style={{ minWidth: 0 }}>{children}</div>
        {wide && open ? (
          <Beside onClose={onClose}>
            <AskPanel caseId={caseId} />
          </Beside>
        ) : null}
      </div>
      {asSheet ? (
        <Sheet onClose={onClose}>
          <AskPanel caseId={caseId} />
        </Sheet>
      ) : null}
      <Drawer.Root
        opened={open && !wide && !asSheet}
        onClose={onClose}
        position="right"
        size={phone ? '100%' : 480}
      >
        <Drawer.Overlay />
        <Drawer.Content>
          <Drawer.Header>
            {/* The drawer's focus trap starts on its heading, as the panel beside the case does */}
            <Drawer.Title data-autofocus tabIndex={-1} fw={600} fz="lg">
              {TITLE}
            </Drawer.Title>
            <Drawer.CloseButton aria-label="Close Ask about this case" />
          </Drawer.Header>
          <Drawer.Body>
            {open && !wide && !asSheet ? (
              <div id={ASK_PANEL_ID}>
                <AskPanel caseId={caseId} />
              </div>
            ) : null}
          </Drawer.Body>
        </Drawer.Content>
      </Drawer.Root>
    </>
  );
}
