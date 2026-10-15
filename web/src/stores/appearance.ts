import { create } from 'zustand';
import { persist } from 'zustand/middleware';

/**
 * Device preferences that must outlive any session: they are kept in localStorage
 * and never touched by logout or by an instance switch. Colour scheme itself stays
 * with Mantine (light / dark / auto); contrast and palette are independent axes on top of it.
 */
export type ContrastSetting = 'auto' | 'normal' | 'high';
/**
 * Which light theme: the default, or Pastel (pale blue). The setting is stored as chosen and
 * written to `<html data-interlock-palette>`; styles.css applies it only while the scheme resolves
 * to light at normal contrast, so it does nothing in dark or high contrast.
 */
export type PaletteSetting = 'default' | 'pastel';

interface AppearanceState {
  /** `auto` follows the OS `prefers-contrast: more` setting. */
  contrast: ContrastSetting;
  palette: PaletteSetting;
  setContrast(contrast: ContrastSetting): void;
  setPalette(palette: PaletteSetting): void;
}

export const useAppearance = create<AppearanceState>()(
  persist(
    (set) => ({
      contrast: 'auto',
      palette: 'default',
      setContrast: (contrast) => set({ contrast }),
      setPalette: (palette) => set({ palette }),
    }),
    { name: 'interlock.appearance' },
  ),
);
