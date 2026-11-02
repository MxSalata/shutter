import { create } from 'zustand';
import { persist } from 'zustand/middleware';
import { ENV, type DetailLevel } from '@/env/mode';

/**
 * Device preferences that must outlive any session: they are kept in localStorage
 * and never touched by logout or by an instance switch. Colour scheme itself stays
 * with Mantine (light / dark / auto); contrast and palette are independent axes on top of it.
 */
export type ContrastSetting = 'auto' | 'normal' | 'high';
/**
 * Which light theme: the default, or Pastel (pale blue). The setting is stored as chosen and
 * written to `<html data-shutter-palette>`; styles.css applies it only while the scheme resolves
 * to light at normal contrast, so it does nothing in dark or high contrast.
 */
export type PaletteSetting = 'default' | 'pastel';

interface AppearanceState {
  /** `auto` follows the OS `prefers-contrast: more` setting. */
  contrast: ContrastSetting;
  palette: PaletteSetting;
  /**
   * How much the pages say: the plain words only (the default), or the technical detail too (every disclosure of
   * data open, the codes beside the words, UTC beside local times). The header's Detail switch sets it.
   */
  detail: DetailLevel;
  setContrast(contrast: ContrastSetting): void;
  setPalette(palette: PaletteSetting): void;
  setDetail(detail: DetailLevel): void;
}

export const useAppearance = create<AppearanceState>()(
  persist(
    (set) => ({
      contrast: 'auto',
      palette: 'default',
      detail: 'plain',
      setContrast: (contrast) => set({ contrast }),
      setPalette: (palette) => set({ palette }),
      setDetail: (detail) => set({ detail }),
    }),
    { name: 'shutter.appearance' },
  ),
);

// The address can set the Detail level at start (`?detail=technical` before the `#`, read once like `?trial`), so a
// link for judges opens in Technical; it is kept as the device's choice from then on.
if (ENV.detail) useAppearance.setState({ detail: ENV.detail });

/** The Detail level the pages read, through this hook and never the store directly, so a page test can set it. */
export const useDetail = (): DetailLevel => useAppearance((s) => s.detail);

/** Whether the pages show their technical detail. */
export const useTechnical = (): boolean => useAppearance((s) => s.detail === 'technical');
