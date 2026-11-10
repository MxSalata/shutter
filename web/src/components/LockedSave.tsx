import { Button, Text, type ButtonProps } from '@mantine/core';
import { IconLock } from '@tabler/icons-react';

/**
 * A Save the reader may not use, shown where an approver's Save stands: the same label with a lock, styled disabled,
 * and described by the note that says why (`LockedNote`). It stays in the tab order (`aria-disabled`, not `disabled`),
 * so a keyboard or a screen reader reaches it and hears why it is locked; pressing it does nothing. The editors around
 * it stay usable, and the server refuses the save anyway.
 */
export function LockedSaveButton({
  label,
  noteId,
  size,
  'aria-label': ariaLabel,
}: {
  label: string;
  /** The id of the `LockedNote` that says why. */
  noteId: string;
  size?: ButtonProps['size'];
  'aria-label'?: string;
}) {
  return (
    <Button
      size={size}
      data-disabled
      aria-disabled="true"
      aria-describedby={noteId}
      aria-label={ariaLabel}
      leftSection={<IconLock size={16} aria-hidden />}
      onClick={(e) => e.preventDefault()}
    >
      {label}
    </Button>
  );
}

/** Why the Save beside it is locked: `saveLocked(can)`. */
export function LockedNote({ id, children }: { id?: string; children: string }) {
  return (
    <Text size="sm" c="dimmed" id={id} data-testid="save-locked">
      {children}
    </Text>
  );
}
