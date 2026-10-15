import { useEffect, useState } from 'react';
import { useAppearance } from '@/stores/appearance';

const QUERY = '(prefers-contrast: more)';

function systemPrefersMore(): boolean {
  try {
    return typeof window !== 'undefined' && !!window.matchMedia && window.matchMedia(QUERY).matches;
  } catch {
    return false;
  }
}

/** The contrast actually in effect: the explicit setting, or the OS preference when set to auto. */
export function useResolvedContrast(): 'normal' | 'high' {
  const setting = useAppearance((s) => s.contrast);
  const [system, setSystem] = useState(systemPrefersMore);
  useEffect(() => {
    if (!window.matchMedia) return;
    const mq = window.matchMedia(QUERY);
    const onChange = (e: MediaQueryListEvent) => setSystem(e.matches);
    mq.addEventListener?.('change', onChange);
    return () => mq.removeEventListener?.('change', onChange);
  }, []);
  return setting === 'auto' ? (system ? 'high' : 'normal') : setting;
}

/**
 * Writes the resolved contrast to `<html data-interlock-contrast>` and the palette setting to
 * `<html data-interlock-palette>`, the siblings of Mantine's `data-mantine-color-scheme`, which
 * `styles.css` keys its high-contrast layer and the Pastel tokens on. The palette is written as
 * chosen: the stylesheet applies it only to the light scheme at normal contrast, so a stored
 * Pastel stays inert in dark or high contrast and returns with the light scheme. Mounted above
 * the router so the login page and error screens are covered too.
 */
export function useApplyAppearance(): 'normal' | 'high' {
  const contrast = useResolvedContrast();
  const palette = useAppearance((s) => s.palette);
  useEffect(() => {
    document.documentElement.dataset.interlockContrast = contrast;
  }, [contrast]);
  useEffect(() => {
    document.documentElement.dataset.interlockPalette = palette;
  }, [palette]);
  return contrast;
}
