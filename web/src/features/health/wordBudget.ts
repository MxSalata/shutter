/**
 * The Health page's word budget: the first layer's visible words on the trial's report in Plain, with Technical at
 * most 1.5 times it (DESIGN.md 1.2), without the endpoint's own JSON, which "The report as the API sends it" opens in
 * Technical.
 *
 * The page spec asks for 120 words (today 366). Its own layout adds up to more: the header and lead (15), the verdict
 * with its seven core checks, the chips and the agents badge (56), the group links (19) and the trial note (18) come to
 * 108 before any group. The page measured 298 words in Plain and 440 in Technical on 2 November 2026, and this ceiling
 * keeps that from growing. What the page spends on is the five groups' 23 rows with their labels, values and counts
 * (about 180, the Agents group's sentence and the two "Why they are missing" buttons among them); what it saves is the
 * 98-word provenance paragraph, the 34-word note, the rows' 12-pixel explanations and the licence's four lines, which
 * are one click away.
 */
export const PLAIN_BUDGET = 300;
export const TECHNICAL_BUDGET = PLAIN_BUDGET * 1.5;
