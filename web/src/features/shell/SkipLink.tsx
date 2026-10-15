import { useState, type CSSProperties } from 'react';

/** The id of the main content, which the skip link moves the focus to. */
export const MAIN_ID = 'main-content';

const hidden: CSSProperties = {
  position: 'absolute',
  width: 1,
  height: 1,
  overflow: 'hidden',
  clip: 'rect(0 0 0 0)',
  whiteSpace: 'nowrap',
};

const shown: CSSProperties = {
  position: 'fixed',
  top: 8,
  left: 8,
  zIndex: 1000,
  padding: '8px 12px',
  borderRadius: 'var(--mantine-radius-sm)',
  background: 'var(--mantine-color-body)',
  color: 'var(--mantine-color-text)',
  boxShadow: 'var(--mantine-shadow-md)',
  outline: '2px solid var(--mantine-primary-color-filled)',
};

/**
 * "Skip to content", the first stop of the keyboard on every page, so a keyboard user does not tab
 * through the header and the whole navigation first. Hidden until it has the focus. The router
 * uses the URL's hash, so the link moves the focus itself rather than following its href.
 */
export function SkipLink() {
  const [focused, setFocused] = useState(false);
  return (
    <a
      href={`#${MAIN_ID}`}
      style={focused ? shown : hidden}
      onFocus={() => setFocused(true)}
      onBlur={() => setFocused(false)}
      onClick={(e) => {
        e.preventDefault();
        document.getElementById(MAIN_ID)?.focus();
      }}
    >
      Skip to content
    </a>
  );
}
