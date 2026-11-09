const FIRST_TRY_MS = 250;
const RETRY_MS = 100;
const GIVE_UP_MS = 3000;

/**
 * Scrolls to the first of these sections that is on the page and moves focus to its heading (`<id>-title`). A tab's panel
 * can take longer than the first wait to mount or show on a slow machine, and a focus before that is lost with no error,
 * so it tries again until the heading holds the focus, and gives up after three seconds. `mayFocus` is asked at each
 * try: once the reader has moved on, the section is still scrolled to but the focus stays where they put it.
 */
export function revealSection(targets: string[], mayFocus: () => boolean = () => true): void {
  const started = Date.now();
  const attempt = () => {
    // The page can be gone before a retry fires (a closed tab, a test's torn-down document): then there is nothing to reveal
    if (typeof document === 'undefined') return;
    const timeUp = Date.now() - started >= GIVE_UP_MS;
    const section = targets.map((t) => document.getElementById(t)).find(Boolean);
    if (!section) {
      if (!timeUp) window.setTimeout(attempt, RETRY_MS);
      return;
    }
    const heading = document.getElementById(`${section.id}-title`);
    const wanted = heading !== null && mayFocus();
    if (wanted) heading.focus({ preventScroll: true });
    if (!wanted || document.activeElement === heading || timeUp) {
      section.scrollIntoView?.({ block: 'start' });
      return;
    }
    window.setTimeout(attempt, RETRY_MS);
  };
  window.setTimeout(attempt, FIRST_TRY_MS);
}
