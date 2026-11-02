import { Button, type ButtonProps } from '@mantine/core';
import { IconHelp } from '@tabler/icons-react';
import { forwardRef, type ComponentPropsWithoutRef } from 'react';

/**
 * The header's help button, the target of the Help menu: its icon and its word from a tablet up ("Help" on a live
 * page, "Tour" or "Resume tour" in the trial), the icon alone on a phone (styles.css `.header-help`), named by the same
 * word in both, so the name a person reads is the name a screen reader says.
 */
export const HeaderHelpButton = forwardRef<
  HTMLButtonElement,
  ButtonProps & Omit<ComponentPropsWithoutRef<'button'>, keyof ButtonProps> & { label: string }
>(function HeaderHelpButton({ label, className, ...props }, ref) {
  return (
    <Button
      ref={ref}
      variant="subtle"
      color="gray"
      leftSection={<IconHelp size={18} aria-hidden />}
      aria-label={label}
      {...props}
      // The menu's target passes a class of its own: keep this one beside it
      className={className ? `header-help ${className}` : 'header-help'}
    >
      <span className="header-help-label">{label}</span>
    </Button>
  );
});
