import { Button, Card, CloseButton, Drawer, Group, Stack, Title } from '@mantine/core';
import { useMediaQuery } from '@mantine/hooks';
import { IconMessageQuestion } from '@tabler/icons-react';
import { forwardRef, useEffect, useRef, type ReactNode } from 'react';
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
        >
          {TITLE}
        </Button>
      </div>
    );
  },
);

/** The panel beside the case: a region with its heading, which takes focus when it opens; Escape or Close shuts it. */
function Beside({ onClose, children }: { onClose: () => void; children: ReactNode }) {
  const heading = useRef<HTMLHeadingElement>(null);
  useEffect(() => heading.current?.focus({ preventScroll: true }), []);
  return (
    <Card
      component="section"
      id={ASK_PANEL_ID}
      aria-labelledby={`${ASK_PANEL_ID}-title`}
      className="ask-aside"
      padding="md"
      withBorder
      onKeyDown={(e) => {
        if (e.key === 'Escape' && !e.defaultPrevented) {
          e.stopPropagation();
          onClose();
        }
      }}
    >
      <Stack gap="md">
        <Group justify="space-between" wrap="nowrap">
          <Title order={2} fz="lg" id={`${ASK_PANEL_ID}-title`} tabIndex={-1} ref={heading}>
            {TITLE}
          </Title>
          <CloseButton onClick={onClose} aria-label="Close Ask about this case" />
        </Group>
        {children}
      </Stack>
    </Card>
  );
}

/**
 * The case page with the panel: side by side from laptop width (75em), where the case stays readable beside it; below
 * that a drawer from the right, the whole screen on a phone. Focus goes to the panel's heading when it opens, in either
 * layout, and back to the button when it closes.
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
  const wide = useMediaQuery('(min-width: 75em)', false, { getInitialValueInEffect: false });
  const phone = useMediaQuery('(max-width: 48em)', false, { getInitialValueInEffect: false });
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
      <Drawer.Root opened={open && !wide} onClose={onClose} position="right" size={phone ? '100%' : 480}>
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
            {open && !wide ? (
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
