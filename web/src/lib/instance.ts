import type { Health } from '@/api/types';
import { resetsHourly } from './budget';
import { failureCadence } from './hospital';
import type { Proof } from './proof';

/**
 * The live sign-in page's line on what stands behind it, under its heading, or null where it says nothing. The page is
 * never the trial's, so "Live" is always true of it; each further claim waits for the signal that makes it true:
 *
 * - a hospital's own install (`demo` false or not said) gets no line: its sign-in page is for its own staff;
 * - a demo install says only that it is a real IRIS for Health instance, which every Shutter instance is;
 * - an instance whose health answer says its live hospital is on (`live.enabled`, the banner's signal for the public
 *   demo) is the public demo, so it adds AI Hub and the build its runs were recorded on (`recordedOn`, the evaluation's
 *   image), the made-up patients, the player's cadence (`live.every_minutes`) and the hourly reset (`resetsHourly`).
 */
export function instanceLine(
  health: Health | undefined,
  recordedOn: Proof['recordedOn'] | undefined,
): string | null {
  if (health?.demo !== true) return null;
  if (!resetsHourly(health)) return 'Live on a real IRIS for Health instance.';
  const build = recordedOn?.build ? ` (build ${recordedOn.build})` : '';
  return `Live on a real IRIS for Health instance with AI Hub${build}: an Interoperability production with made-up patients, ${failureCadence(health.live?.every_minutes)}, reset on the hour.`;
}
