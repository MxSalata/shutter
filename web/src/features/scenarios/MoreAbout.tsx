import { VisuallyHidden } from '@mantine/core';
import type { ReactNode } from 'react';
import { TechDetail } from '@/components/TechDetail';

/**
 * The rest of a description, one click away: a real button that reads "More" and is named for what it opens ("More
 * about S2"), with `aria-expanded`. It is an explaining detail, so it stays closed in Plain and in Technical alike.
 */
export function MoreAbout({ about, children }: { about: string; children: ReactNode }) {
  return (
    <TechDetail
      kind="explain"
      label={
        <>
          More<VisuallyHidden> about {about}</VisuallyHidden>
        </>
      }
    >
      {children}
    </TechDetail>
  );
}
