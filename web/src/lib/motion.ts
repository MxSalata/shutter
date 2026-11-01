import { useReducedMotion } from '@mantine/hooks';
import { useEffect, useRef, useState, type RefObject } from 'react';

/**
 * Motion that points and confirms, never decorates (the design system, section 6): one movement at a time, each ending
 * at rest in its final state, and none at all for a reader who asks for reduced motion. The movement itself is CSS,
 * switched by an attribute these hooks set, so a component holds no animation timers of its own.
 */

/** Whether the reader asked for reduced motion (`prefers-reduced-motion: reduce`). */
export function usePrefersReducedMotion(): boolean {
  return useReducedMotion() ?? false;
}

/**
 * Reveals `count` steps one at a time, `interval` ms apart, once `start` is true: the replay after a trial approval
 * (each lifecycle step takes `data-revealed`, styles.css `.lifecycle-step`). Under reduced motion every step is
 * revealed at once. `onDone` is called once, when the last step is revealed. Before `start`, nothing is revealed.
 */
export function useStagedReveal(
  count: number,
  { start, interval = 400, onDone }: { start: boolean; interval?: number; onDone?: () => void },
): { revealed: number; done: boolean; stepProps: (i: number) => { 'data-revealed': 'true' | 'false' } } {
  const reduced = usePrefersReducedMotion();
  // The intervals elapsed since the replay started; the first step shows at once
  const [ticks, setTicks] = useState(0);
  const revealed = !start ? 0 : reduced ? count : Math.min(count, 1 + ticks);
  const done = start && revealed >= count;
  const callback = useRef(onDone);
  useEffect(() => {
    callback.current = onDone;
  }, [onDone]);

  useEffect(() => {
    if (!start || reduced || count <= 1) return;
    let n = 0;
    const timer = window.setInterval(() => {
      n += 1;
      setTicks(n);
      if (n >= count - 1) window.clearInterval(timer);
    }, interval);
    return () => {
      window.clearInterval(timer);
      setTicks(0);
    };
  }, [start, reduced, count, interval]);

  const finished = useRef(false);
  useEffect(() => {
    if (!start) finished.current = false;
    else if (done && !finished.current) {
      finished.current = true;
      callback.current?.();
    }
  }, [start, done]);

  return {
    revealed,
    done,
    stepProps: (i: number) => ({ 'data-revealed': i < revealed ? 'true' : 'false' }),
  };
}

/**
 * Whether an element is at least `threshold` in view (an IntersectionObserver), for a movement that must not play off
 * screen: the guide's try-it pointer starts only once its control is half in view. Where the browser has no observer,
 * the element counts as in view.
 */
export function useInView(
  ref: RefObject<Element | null>,
  { threshold = 0.5 }: { threshold?: number } = {},
): boolean {
  const [inView, setInView] = useState(typeof IntersectionObserver === 'undefined');
  useEffect(() => {
    const el = ref.current;
    if (!el || typeof IntersectionObserver === 'undefined') return;
    const observer = new IntersectionObserver(
      (entries) => {
        for (const e of entries) setInView(e.isIntersecting && e.intersectionRatio >= threshold);
      },
      { threshold },
    );
    observer.observe(el);
    return () => observer.disconnect();
  }, [ref, threshold]);
  return inView;
}
