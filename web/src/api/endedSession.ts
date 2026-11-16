/**
 * Who was signed in when a session ended without a sign-out (it expired, or the server dropped it), so the next sign-in
 * can tell whether it is the same person. A sign-out clears the page's state itself; an ended session does not, and
 * someone else signing in on the same tab must not find the earlier person's drafts.
 */
let ended: string | null = null;

/** Records who was signed in when the session ended. */
export function sessionEnded(username: string | null | undefined): void {
  if (username) ended = username;
}

/** Who was signed in when the last session ended, once: the next call answers null. */
export function takeEndedSession(): string | null {
  const who = ended;
  ended = null;
  return who;
}
