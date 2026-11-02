import { Button, Group, Paper, Text } from '@mantine/core';
import { useEffect, useRef, type ReactNode } from 'react';
import { plural } from '@/lib/format';

/**
 * The foot of the page while the draft differs from the saved version: "2 changes", Discard, and Review and save. It
 * sticks to the bottom of the window and rises 8 px in 220 ms (the page's global rule drops that under reduced motion).
 * It never covers the focused field: while it shows, the window's scroll padding is its height, so the browser keeps a
 * field it focuses clear of the bar. The public demo's role reads the changes and cannot save them, so its bar offers
 * the review and carries the read-only note.
 */
export function SaveBar({
  count,
  onReview,
  onDiscard,
  reviewLabel,
  alert,
  note,
}: {
  count: number;
  onReview: () => void;
  /** Absent when the draft cannot be discarded by this reader. */
  onDiscard?: () => void;
  reviewLabel: string;
  /** What the last review refused, above the buttons. */
  alert?: ReactNode;
  note?: ReactNode;
}) {
  const bar = useRef<HTMLDivElement>(null);
  useEffect(() => {
    const el = bar.current;
    if (!el) return;
    const root = document.documentElement;
    const pad = () => root.style.setProperty('scroll-padding-bottom', `${el.offsetHeight + 16}px`);
    pad();
    const watch = typeof ResizeObserver === 'undefined' ? null : new ResizeObserver(pad);
    watch?.observe(el);
    return () => {
      watch?.disconnect();
      root.style.removeProperty('scroll-padding-bottom');
    };
  }, []);
  return (
    <Paper
      component="section"
      ref={bar}
      aria-label="Unsaved changes"
      withBorder
      shadow="md"
      p="sm"
      style={{
        position: 'sticky',
        bottom: 0,
        zIndex: 20,
        animation: 'rise-in var(--motion-base) var(--motion-ease) 1',
      }}
    >
      {alert ? <div style={{ marginBottom: 8 }}>{alert}</div> : null}
      <Group justify="space-between" gap="sm" wrap="wrap">
        <Group gap="sm" wrap="wrap">
          <Text fw={600}>{plural(count, 'change')}</Text>
          {note}
        </Group>
        <Group gap="sm" wrap="wrap">
          {onDiscard ? (
            <Button variant="default" onClick={onDiscard}>
              Discard changes
            </Button>
          ) : null}
          <Button onClick={onReview}>{reviewLabel}</Button>
        </Group>
      </Group>
    </Paper>
  );
}
