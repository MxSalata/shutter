/** Shutter's mark: a six-blade shutter, its opening in the middle, on the teal tile (public/favicon.svg). */
export function BrandMark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden focusable="false">
      <defs>
        <linearGradient id="shutter-mark" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#095c7c" />
          <stop offset="1" stopColor="#45acd1" />
        </linearGradient>
      </defs>
      <rect width="32" height="32" rx="8" fill="url(#shutter-mark)" />
      <g fill="none" stroke="#fff" strokeWidth="1.9" strokeLinecap="round">
        <circle cx="16" cy="16" r="10.2" />
        <line x1="16" y1="11.4" x2="26.12" y2="17.24" />
        <line x1="19.98" y1="13.7" x2="19.98" y2="25.39" />
        <line x1="19.98" y1="18.3" x2="9.86" y2="24.14" />
        <line x1="16" y1="20.6" x2="5.88" y2="14.76" />
        <line x1="12.02" y1="18.3" x2="12.02" y2="6.61" />
        <line x1="12.02" y1="13.7" x2="22.14" y2="7.86" />
      </g>
    </svg>
  );
}
