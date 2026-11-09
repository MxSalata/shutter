import { useEffect, useRef } from 'react';
import { useSearchParams } from 'react-router';
import { useAssistantContext } from './panel';
import { useAssistant } from './store';

/**
 * The panel and the address: on a case page `?ask=1` opens it (a link can open it, as the README's do), and the address
 * follows the panel while the reader is on a case page, so a closed panel leaves no `ask=1` behind.
 */
export function AssistantRouteSync() {
  const ctx = useAssistantContext();
  const open = useAssistant((s) => s.open);
  const setOpen = useAssistant((s) => s.setOpen);
  const [search, setSearch] = useSearchParams();
  const asked = search.get('ask') === '1';
  const onCase = ctx.kind === 'case';
  // Whether the address asked for the panel at the last look: only an address that newly asks (a link followed, Back)
  // opens it, so closing the panel, which leaves `ask=1` behind for a moment, never reopens it
  const askedBefore = useRef(false);
  useEffect(() => {
    const newlyAsked = asked && !askedBefore.current;
    askedBefore.current = asked;
    if (!onCase) return;
    if (newlyAsked && !open) {
      setOpen(true);
      return;
    }
    if (open === asked) return;
    setSearch(
      (prev) => {
        const params = new URLSearchParams(prev);
        if (open) params.set('ask', '1');
        else params.delete('ask');
        return params;
      },
      { replace: true, preventScrollReset: true },
    );
  }, [onCase, open, asked, setOpen, setSearch]);
  return null;
}
