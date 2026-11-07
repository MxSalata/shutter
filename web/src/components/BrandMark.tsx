import { useId } from 'react';

/**
 * The blades of the mark in a 64-unit square: six, round a hexagonal opening, turning the other way from Aperture's.
 * public/favicon.svg and public/favicon-trial.svg draw the same mark: keep the three alike.
 */
const BLADES = [
  'M32.000 22.000L56.178 35.959A24.5 24.5 0 0 0 47.518 13.041Z',
  'M40.660 27.000L40.660 54.918A24.5 24.5 0 0 0 56.178 35.959Z',
  'M40.660 37.000L16.482 50.959A24.5 24.5 0 0 0 40.660 54.918Z',
  'M32.000 42.000L7.822 28.041A24.5 24.5 0 0 0 16.482 50.959Z',
  'M23.340 37.000L23.340 9.082A24.5 24.5 0 0 0 7.822 28.041Z',
  'M23.340 27.000L47.518 13.041A24.5 24.5 0 0 0 23.340 9.082Z',
];

/**
 * Shutter's mark: the blades sweep from the primary's shade 3 to violet, on the slate of the dark theme (dark-7 to
 * dark-6) with a dark-4 edge, so the tile stays visible on both a white page and a dark one.
 */
export function BrandMark({ size = 28 }: { size?: number }) {
  // Ids that url(#...) takes as they are (useId's may hold characters it does not).
  const id = useId().replace(/[^\w-]/g, '');
  const tile = `shutter-mark-tile-${id}`;
  const blades = `shutter-mark-blades-${id}`;
  return (
    <svg width={size} height={size} viewBox="0 0 64 64" aria-hidden focusable="false">
      <defs>
        <linearGradient id={tile} gradientUnits="userSpaceOnUse" x1="0" y1="0" x2="64" y2="64">
          <stop offset="0" stopColor="#1f2630" />
          <stop offset="1" stopColor="#2a323d" />
        </linearGradient>
        <linearGradient id={blades} gradientUnits="userSpaceOnUse" x1="10" y1="10" x2="54" y2="54">
          <stop offset="0" stopColor="#6fc0dc" />
          <stop offset="1" stopColor="#9775fa" />
        </linearGradient>
      </defs>
      <rect
        x="1.25"
        y="1.25"
        width="61.5"
        height="61.5"
        rx="18"
        fill={`url(#${tile})`}
        stroke="#4a5463"
        strokeWidth="2.5"
      />
      <g fill={`url(#${blades})`} stroke="#1f2630" strokeWidth="1.8" strokeLinejoin="round">
        {BLADES.map((d) => (
          <path key={d} d={d} />
        ))}
      </g>
    </svg>
  );
}
