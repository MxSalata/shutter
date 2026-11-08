import { Paper, Text, VisuallyHidden } from '@mantine/core';
import { useId } from 'react';
import type { ReviewDetail, Severity } from '@/api/types';
import { NotYet } from '@/components/Section';
import { formatInt } from '@/lib/format';
import { SEVERITY_STATUS } from '@/lib/status';
import { TONE_COLOURS } from '@/lib/tone';
import { SEVERITIES } from './review';
import './reviews.css';

/** The tiers the legend always names, even at zero: the three a reader ranks by. Info joins them only when it has findings. */
const NAMED_TIERS: Severity[] = ['high', 'medium', 'low'];

/**
 * The review's counts as one line: the findings count, a bar split by severity with the count of each tier beside it
 * (the tone sits in the bar and the legend's dots; every number is text), and the two counts from the window as small
 * labelled numbers on the right. The bar is a picture of the legend, so it is hidden from a screen reader, which hears
 * "13 findings, 1 high, 10 medium, 2 low, in the window 94 errors logged, 90 messages in error". While the sweep is
 * still reading there are no counts yet; a failed review has none at all.
 */
export function ReviewSummary({ r }: { r: ReviewDetail }) {
  const id = useId();
  const s = r.summary;
  if (!s.bySeverity)
    return (
      <section aria-label="Summary">
        {r.state === 'failed' ? (
          <Text size="sm">There is no result because the review failed{r.error ? `: ${r.error}` : '.'}</Text>
        ) : (
          <NotYet>Not yet: the sweep is still reading.</NotYet>
        )}
      </section>
    );
  const by = s.bySeverity;
  const count = (sev: Severity) => by[sev] ?? 0;
  const total = s.findings ?? SEVERITIES.reduce((n, sev) => n + count(sev), 0);
  const tiers = SEVERITIES.filter((sev) => NAMED_TIERS.includes(sev) || count(sev) > 0);
  const segments = tiers.filter((sev) => count(sev) > 0);
  return (
    <Paper component="section" aria-labelledby={id} className="review-summary" px="md" py="sm">
      <VisuallyHidden id={id} component="h2">
        Summary
      </VisuallyHidden>
      <p className="review-summary-count">
        <span className="stat-figure">{formatInt(total)}</span>
        <span className="review-summary-word">{total === 1 ? 'finding' : 'findings'}</span>
      </p>
      <div className="review-summary-tiers">
        {segments.length ? (
          <div className="severity-bar" aria-hidden>
            {segments.map((sev) => (
              <span
                key={sev}
                data-tone={SEVERITY_STATUS[sev].tone}
                style={{
                  flexGrow: count(sev),
                  ['--segment' as string]: `var(--mantine-color-${TONE_COLOURS[SEVERITY_STATUS[sev].tone]}-filled)`,
                }}
              />
            ))}
          </div>
        ) : null}
        {total ? (
          <ul className="severity-legend">
            {tiers.map((sev) => (
              <li key={sev} data-zero={count(sev) === 0 || undefined}>
                <span
                  className="severity-dot"
                  style={{
                    ['--segment' as string]: `var(--mantine-color-${TONE_COLOURS[SEVERITY_STATUS[sev].tone]}-filled)`,
                  }}
                  aria-hidden
                />
                {formatInt(count(sev))} {sev}
              </li>
            ))}
            {s.intended ? <li data-zero>{formatInt(s.intended)} marked</li> : null}
          </ul>
        ) : (
          <Text component="span" size="sm" c="dimmed">
            Nothing in any tier
          </Text>
        )}
      </div>
      <div className="review-summary-window">
        <span className="overline">In the window</span>
        <ul className="review-summary-window-counts">
          <li>
            <span className="review-summary-small">{formatInt(s.errorsInWindow)}</span>{' '}
            {(s.errorsInWindow ?? 0) === 1 ? 'error logged' : 'errors logged'}
          </li>
          <li>
            <span className="review-summary-small">{formatInt(s.messageErrorsInWindow)}</span>{' '}
            {(s.messageErrorsInWindow ?? 0) === 1 ? 'message in error' : 'messages in error'}
          </li>
        </ul>
      </div>
    </Paper>
  );
}
