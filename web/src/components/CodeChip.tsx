import { Code, type CodeProps } from '@mantine/core';
import type { ReactNode } from 'react';

/**
 * A reason code, block reason, catalogue entry, HL7 event, key or version, as the machine names it: mono, wrapping
 * anywhere rather than widening the page, beside the plain words, never instead of them.
 */
export function CodeChip({ children, ...props }: { children: ReactNode } & Omit<CodeProps, 'children'>) {
  return (
    <Code className="code-chip" {...props}>
      {children}
    </Code>
  );
}
