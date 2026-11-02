import { Portal } from '@mantine/core';
import { useEffect, useId, useRef, useState, type ReactNode } from 'react';
import { glossary, type GlossaryKey } from '@/lib/glossary';
import { useDetail } from '@/stores/appearance';

const GAP = 8;

/** Where the definition's bubble goes: above the word when there is room, below it otherwise, never off screen. */
function place(r: DOMRect): { top: number; left: number; width: number; above: boolean } {
  const width = Math.min(280, window.innerWidth - 2 * GAP);
  const left = Math.max(GAP, Math.min(r.left + r.width / 2 - width / 2, window.innerWidth - width - GAP));
  const above = r.top > 140;
  return { top: above ? r.top - GAP : r.bottom + GAP, left, width, above };
}

/**
 * A word the newcomer may not know, with its plain definition one hover, focus or tap away: a dotted underline in the
 * text colour, keyboard reachable, described by the definition. A tap opens it and a second tap, a tap outside or
 * Escape closes it (Mantine's Tooltip does not open on a tap). The bubble is placed by hand rather than by a
 * positioning library, since a page carries many terms. Wrap only a term's first use on a page. In Technical, HL7's
 * own terms (ADT, MSH-7, the PAS) read as plain text, and Shutter's own terms lose the underline but keep their
 * definition.
 */
export function Term({
  term,
  definition,
  children,
}: {
  /** The glossary's entry; `definition` instead for a term only one page uses. */
  term?: GlossaryKey;
  definition?: string;
  /** The words on the page; the entry's own term when absent. */
  children?: ReactNode;
}) {
  const technical = useDetail() === 'technical';
  const entry = term ? glossary(term) : undefined;
  const text = definition ?? entry?.definition ?? '';
  const words = children ?? entry?.term;
  const id = useId();
  const word = useRef<HTMLSpanElement>(null);
  const bubble = useRef<HTMLDivElement>(null);
  // A tap: the browser follows it with an emulated hover and focus, which must not open what the tap then closes
  const touch = useRef(false);
  const [at, setAt] = useState<ReturnType<typeof place> | null>(null);
  const show = () => {
    const r = word.current?.getBoundingClientRect();
    if (r) setAt(place(r));
  };
  const hide = () => setAt(null);

  useEffect(() => {
    if (!at) return;
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') setAt(null);
    };
    const onDown = (e: PointerEvent) => {
      const t = e.target as Node;
      if (!word.current?.contains(t) && !bubble.current?.contains(t)) setAt(null);
    };
    const onMove = () => {
      const r = word.current?.getBoundingClientRect();
      if (r) setAt(place(r));
    };
    document.addEventListener('keydown', onKey);
    document.addEventListener('pointerdown', onDown);
    window.addEventListener('scroll', onMove, true);
    window.addEventListener('resize', onMove);
    return () => {
      document.removeEventListener('keydown', onKey);
      document.removeEventListener('pointerdown', onDown);
      window.removeEventListener('scroll', onMove, true);
      window.removeEventListener('resize', onMove);
    };
  }, [at]);

  if (technical && entry?.standard) return <>{words}</>;
  return (
    <>
      <span
        ref={word}
        className="term"
        data-plain={technical || undefined}
        tabIndex={0}
        aria-describedby={id}
        onPointerDown={(e) => {
          touch.current = e.pointerType !== 'mouse';
        }}
        onMouseEnter={() => (touch.current ? undefined : show())}
        onMouseLeave={() => (touch.current ? undefined : hide())}
        onFocus={() => (touch.current ? undefined : show())}
        onBlur={() => {
          touch.current = false;
          hide();
        }}
        onClick={() => (touch.current ? (at ? hide() : show()) : undefined)}
      >
        {words}
      </span>
      {/* The definition is always in the page, for aria-describedby; the bubble shows it on demand */}
      <span id={id} hidden>
        {text}
      </span>
      {at ? (
        <Portal>
          <div
            ref={bubble}
            role="tooltip"
            className="term-bubble"
            data-side={at.above ? 'top' : 'bottom'}
            style={{ top: at.top, left: at.left, width: at.width }}
          >
            {text}
          </div>
        </Portal>
      ) : null}
    </>
  );
}
