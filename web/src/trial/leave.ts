import { create } from 'zustand';
import { liveHref } from '@/env/mode';

/** The one confirm every "Leave trial" opens: in the banner, the user menu, Help and the guide's finish card. */
export const useLeaveTrial = create<{ asking: boolean; ask(): void; stay(): void }>()((set) => ({
  asking: false,
  ask: () => set({ asking: true }),
  stay: () => set({ asking: false }),
}));

/** Leaving is a page load without `?trial`: nothing from the trial survives in memory. */
export function leaveTrial(): void {
  window.location.assign(liveHref());
}
