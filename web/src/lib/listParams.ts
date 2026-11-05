import { useEffect } from 'react';
import { useSearchParams } from 'react-router';

/** The address a list has asked for and the router has not reached yet, shared by the parts of one page. */
let asked: URLSearchParams | null = null;

/**
 * A list's filters in the address, so Back from a case returns to them. A navigation finishes a moment after it is asked
 * for, on a slow machine longer, so each change starts from the last one asked for and not from the last one rendered:
 * a second quick choice keeps the first.
 */
export function useListParams() {
  const [params, setParams] = useSearchParams();
  useEffect(() => {
    if (asked?.toString() === params.toString()) asked = null;
  }, [params]);
  useEffect(
    () => () => {
      asked = null;
    },
    [],
  );
  const change = (edit: (next: URLSearchParams) => void) => {
    const next = new URLSearchParams(asked ?? params);
    edit(next);
    asked = next;
    setParams(next, { replace: true, preventScrollReset: true });
  };
  return [params, change] as const;
}
