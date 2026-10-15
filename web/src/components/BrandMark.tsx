/** Interlock's mark: two linked rings on the indigo tile (public/favicon.svg). */
export function BrandMark({ size = 28 }: { size?: number }) {
  return (
    <svg width={size} height={size} viewBox="0 0 32 32" aria-hidden focusable="false">
      <defs>
        <linearGradient id="interlock-mark" x1="0" y1="0" x2="1" y2="1">
          <stop offset="0" stopColor="#095c7c" />
          <stop offset="1" stopColor="#45acd1" />
        </linearGradient>
      </defs>
      <rect width="32" height="32" rx="8" fill="url(#interlock-mark)" />
      <circle cx="12.5" cy="16" r="6" fill="none" stroke="#fff" strokeWidth="2.6" />
      <circle cx="19.5" cy="16" r="6" fill="none" stroke="#fff" strokeWidth="2.6" />
    </svg>
  );
}
