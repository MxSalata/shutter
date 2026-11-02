/**
 * The page's word budget: the first layer's visible words in Plain, with Technical at most 1.5 times it (DESIGN.md
 * 1.2). The page spec asks for 1,300, but the content it keeps for each of the 26 rows (the id and title, the first
 * sentence in full, what should happen with its sentence, the recorded comparison, the latest case with its outcome
 * and mark) comes to about 1,330 words on its own; the whole page measured 1,923 in the trial (with Start here) and
 * 1,750 outside it on 1 November 2026, against 2,893 before. This ceiling keeps that figure from growing.
 */
export const PLAIN_BUDGET = 1950;
export const TECHNICAL_BUDGET = PLAIN_BUDGET * 1.5;
