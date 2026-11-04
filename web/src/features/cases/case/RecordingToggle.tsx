import { type ComponentType, lazy, Suspense, useEffect, useRef } from 'react';
import type { AgentRun } from '@/api/types';
import { usePrefersReducedMotion } from '@/lib/motion';
import { MoreToggle } from './MoreToggle';
import { RecordingReading, RecordingUnavailable } from './RecordingUnavailable';

/** A run's recording: its chunk, and the recording's own, load when this opens. */
const RunRecording = lazy<ComponentType<{ caseId: string; run: AgentRun }>>(() =>
  import('./RunRecording').catch(() => ({ default: RecordingUnavailable })),
);

export interface RecordingToggleProps {
  caseId: string;
  run: AgentRun;
  open: boolean;
  onToggle: () => void;
  describedBy: string;
}

/**
 * The toggle for what a board member was sent and did, and the recording under it, in the card. Trial pages alone load
 * this file (`BoardPanel`). Opening moves the card to a row of its own and closing drops a long panel, so on both the
 * toggle is brought to just under the sticky tabs, with no animation for a reader who asks for less motion.
 */
export default function RecordingToggle({ caseId, run, open, onToggle, describedBy }: RecordingToggleProps) {
  const id = `${describedBy}-recording`;
  const reduced = usePrefersReducedMotion();
  const toggle = useRef<HTMLDivElement>(null);
  const shown = useRef(open);
  useEffect(() => {
    if (shown.current === open) return;
    shown.current = open;
    toggle.current?.scrollIntoView?.({ block: 'start', behavior: reduced ? 'auto' : 'smooth' });
  }, [open, reduced]);
  return (
    <>
      <div ref={toggle} style={{ scrollMarginTop: 'calc(var(--shutter-header-h) + 3.5rem)' }}>
        <MoreToggle
          open={open}
          onToggle={onToggle}
          controls={id}
          describedBy={describedBy}
          label="the recording"
        />
      </div>
      <div id={id} hidden={!open}>
        {open ? (
          <Suspense fallback={<RecordingReading />}>
            <RunRecording caseId={caseId} run={run} />
          </Suspense>
        ) : null}
      </div>
    </>
  );
}
