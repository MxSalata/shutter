import { Group, Modal, type ModalRootProps } from '@mantine/core';
import type { ReactNode } from 'react';
import { EnvChip } from './EnvChip';

/**
 * The confirm of an action with an effect outside the browser (DESIGN.md 5.6 and 7.1): the title, and beside it the
 * `EnvChip` ("Trial only" in a trial page, "Live system" in a live one), so nobody approves a real write believing it
 * is the trial. The chip sits beside the title, not in it: the title alone names the dialog, so tests and the guide
 * find it by its exact words ("Approve the resend: plan v1"). `chip={false}` leaves the chip out, for a dialog that only lets
 * the reader look (a read-only review of a change). It keeps the theme's rules for `Modal`, which a `Modal.Root`
 * does not read: a stray click outside does not discard it (Escape still closes), and its close button is named.
 */
export function ConfirmModal({
  title,
  chip = true,
  children,
  ...props
}: {
  /** The dialog's name: its title, without the chip. */
  title: string;
  /** Whether the chip stands beside the title. */
  chip?: boolean;
  children: ReactNode;
} & Omit<ModalRootProps, 'title' | 'children'>) {
  return (
    <Modal.Root closeOnClickOutside={false} {...props}>
      <Modal.Overlay />
      <Modal.Content>
        <Modal.Header>
          <Group gap="sm" wrap="wrap" style={{ minWidth: 0 }}>
            <Modal.Title>{title}</Modal.Title>
            {chip ? <EnvChip /> : null}
          </Group>
          <Modal.CloseButton aria-label="Close" />
        </Modal.Header>
        <Modal.Body>{children}</Modal.Body>
      </Modal.Content>
    </Modal.Root>
  );
}
