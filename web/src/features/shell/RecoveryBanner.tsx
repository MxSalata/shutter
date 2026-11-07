import { useRecoveryControl } from '@/api/hooks';
import { StatusNotice } from '@/components/StatusBadge';

/** Across every page while recovery is off or stopped: what is happening, and that the ordinary feed goes on. */
export function RecoveryBanner() {
  const c = useRecoveryControl().data;
  if (!c) return null;
  if (c.stopped) {
    return (
      <StatusNotice tone="blocking" title={`Shutter recovery stopped by ${c.stoppedBy} at ${c.stoppedAt}.`}>
        No new recovery dispatches are admitted. {c.outstandingCount} earlier calls may still complete.
        Read-back continues.
      </StatusNotice>
    );
  }
  if (c.mode === 'enabled') return null;
  return (
    <StatusNotice tone="attention" title="Shadow mode.">
      Shutter investigates, but sends no recovery write, rehearsal or resend preview. The hospital&apos;s
      ordinary feed continues.
    </StatusNotice>
  );
}
