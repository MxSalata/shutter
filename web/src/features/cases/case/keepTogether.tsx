import type { ReactNode } from 'react';

/**
 * A sentence with its hyphenated names kept whole: a narrow column breaks a line after a hyphen, which would leave
 * "WARD-" at the end of one line and "B" at the start of the next. The text is unchanged, only where it may wrap. A
 * name too long for a phone's line still wraps as the browser sees fit, so it can't push the page wider.
 */
export function keepTogether(text: string): ReactNode[] {
  return text.split(/(\s+)/).map((part, i) =>
    /\S-\S/.test(part) && part.length <= 24 ? (
      <span key={i} style={{ whiteSpace: 'nowrap' }}>
        {part}
      </span>
    ) : (
      part
    ),
  );
}
