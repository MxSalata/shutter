import { Loader } from '@mantine/core';
import { lazy, Suspense } from 'react';
import type { PageFocus } from './store';

// What "Ask Shutter about this" opens under its question, below the wide breakpoint: loaded the first time one is pressed
const FocusAsk = lazy(() => import('./FocusAsk').then((m) => ({ default: m.FocusAsk })));

/** The question asked about, in the page under the question's row (AskAbout.tsx), where the panel would cover the form. */
export function AskAboutRegion({ id, focus }: { id: string; focus: PageFocus }) {
  return (
    <div id={id}>
      <Suspense fallback={<Loader size="xs" aria-label="Opening Ask Shutter" />}>
        <FocusAsk focus={focus} inline />
      </Suspense>
    </div>
  );
}
