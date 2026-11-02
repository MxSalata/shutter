import { notifications } from '@mantine/notifications';
import { useEffect } from 'react';
import { takeTrialVisit } from './visit';

/** What a live page says to a tab that has just been in the trial (DESIGN.md 7.1, N18). */
export const BACK_IN_LIVE = 'You are back in the live system. Actions here are real.';

function tell() {
  notifications.show({
    id: 'back-from-trial',
    title: 'Live system',
    message: BACK_IN_LIVE,
    color: 'yellow',
    autoClose: 8_000,
    withCloseButton: true,
  });
}

/**
 * On a live page, the warning that the tab has come back from the trial: on load (after Leave trial, or Back into
 * a fresh page) and on a `pageshow` from the back-forward cache, whenever the tab carries the trial's mark. Back is
 * the likeliest way to mistake the live system for the trial, so it is not only shown after Leave trial.
 */
export function BackFromTrial() {
  useEffect(() => {
    if (takeTrialVisit()) tell();
    const shown = (e: PageTransitionEvent) => {
      if (e.persisted && takeTrialVisit()) tell();
    };
    window.addEventListener('pageshow', shown);
    return () => window.removeEventListener('pageshow', shown);
  }, []);
  return null;
}
